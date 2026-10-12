import contextlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('publisher', ROOT / 'Scripts/publish-release.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


@contextlib.contextmanager
def repository():
    previous = Path.cwd()
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        remote = root / 'remote.git'
        local = root / 'local'
        def git(*args, cwd=local):
            return subprocess.check_output(['git', *args], cwd=cwd, text=True, stderr=subprocess.DEVNULL).strip()
        git('init', '--bare', str(remote), cwd=root)
        git('init', str(local), cwd=root)
        git('config', 'user.name', 'Release Test')
        git('config', 'user.email', 'test@example.invalid')
        (local / 'file').write_text('first')
        git('add', 'file'); git('commit', '-m', 'first')
        first = git('rev-parse', 'HEAD')
        git('remote', 'add', 'origin', str(remote))
        git('push', 'origin', 'HEAD:refs/heads/main')
        os.chdir(local)
        try:
            yield git, first, remote
        finally:
            os.chdir(previous)


class PublicationTests(unittest.TestCase):
    def test_main_advancing_does_not_change_the_tested_release(self):
        with repository() as (git, tested, remote):
            Path('file').write_text('second')
            git('commit', '-am', 'second')
            newer = git('rev-parse', 'HEAD')
            git('push', 'origin', 'HEAD:refs/heads/main')
            git('checkout', '--detach', tested)
            publisher.ensure_tag('v0.1.0', tested)
            self.assertEqual(git('--git-dir=' + str(remote), 'rev-parse', 'refs/tags/v0.1.0^{commit}'), tested)
            self.assertEqual(git('--git-dir=' + str(remote), 'rev-parse', 'refs/heads/main'), newer)

    def test_partial_publication_resumes_without_replacing_the_tag(self):
        real_command = publisher.command
        attempts = []
        fail_create = True
        def fake_gh(*args, check=True):
            nonlocal fail_create
            if args[0] != 'gh':
                return real_command(*args, check=check)
            if args[1] == 'api':
                return subprocess.CompletedProcess(args, 0, '[[]]', '')
            attempts.append(args)
            if fail_create:
                fail_create = False
                raise subprocess.CalledProcessError(1, args, stderr='Transient API failure')
            return subprocess.CompletedProcess(args, 0, '', '')
        with repository() as (git, tested, remote), patch.object(publisher, 'command', side_effect=fake_gh):
            with self.assertRaises(subprocess.CalledProcessError):
                publisher.publish('v0.1.0', tested, 'example/sdk', 'notes.md')
            before = git('--git-dir=' + str(remote), 'rev-parse', 'refs/tags/v0.1.0')
            publisher.publish('v0.1.0', tested, 'example/sdk', 'notes.md')
            self.assertEqual(git('--git-dir=' + str(remote), 'rev-parse', 'refs/tags/v0.1.0'), before)
            self.assertEqual(len(attempts), 2)
            self.assertTrue(all('--verify-tag' in attempt for attempt in attempts))

    def test_tag_pointing_elsewhere_is_rejected(self):
        with repository() as (git, tested, remote):
            git('tag', 'v0.1.0'); git('push', 'origin', 'refs/tags/v0.1.0')
            Path('file').write_text('second'); git('commit', '-am', 'second')
            with self.assertRaisesRegex(ValueError, 'different commit'):
                publisher.ensure_tag('v0.1.0', git('rev-parse', 'HEAD'))
            self.assertEqual(git('--git-dir=' + str(remote), 'rev-parse', 'refs/tags/v0.1.0'), tested)

    def test_completed_release_is_not_overwritten(self):
        result = subprocess.CompletedProcess([], 0, '[[{"tag_name":"v0.1.0","draft":false}]]', '')
        with patch.object(publisher, 'command', return_value=result) as command:
            self.assertEqual(publisher.find_release('example/sdk', 'v0.1.0'), {'tag_name': 'v0.1.0', 'draft': False})
        self.assertEqual(command.call_count, 1)
        with patch.object(publisher, 'command') as command, patch.object(publisher, 'ensure_tag'), patch.object(publisher, 'list_releases', return_value=[{'tag_name': 'v0.1.0', 'draft': False}]):
            command.return_value.stdout = 'a' * 40
            publisher.publish('v0.1.0', 'a' * 40, 'example/sdk', 'notes.md')
            self.assertEqual(command.call_count, 1)  # Only checks HEAD; no release mutation.

    def test_api_errors_are_not_treated_as_missing_releases(self):
        result = subprocess.CompletedProcess([], 1, 'HTTP/2.0 403 Forbidden\n\n{}', 'Forbidden')
        with patch.object(publisher, 'command', return_value=result):
            with self.assertRaises(subprocess.CalledProcessError):
                publisher.find_release('example/sdk', 'v0.1.0')

    def test_draft_on_a_later_page_is_published_without_creating_another_release(self):
        real_command = publisher.command
        mutations = []
        pages = [[{'tag_name': 'v0.2.0', 'draft': False}],
                 [{'tag_name': 'v0.1.0', 'draft': True}]]
        def fake_gh(*args, check=True):
            if args[0] != 'gh':
                return real_command(*args, check=check)
            if args[1] == 'api':
                self.assertIn('--paginate', args)
                self.assertIn('--slurp', args)
                return subprocess.CompletedProcess(args, 0, json.dumps(pages), '')
            mutations.append(args)
            return subprocess.CompletedProcess(args, 0, '', '')
        with repository() as (_, tested, _), patch.object(publisher, 'command', side_effect=fake_gh):
            publisher.publish('v0.1.0', tested, 'example/sdk', 'notes.md')
        self.assertEqual(len(mutations), 1)
        self.assertEqual(mutations[0][1:3], ('release', 'edit'))
        self.assertIn('--draft=false', mutations[0])
        self.assertIn('--latest=false', mutations[0])

    def test_old_partial_release_recovery_preserves_newer_latest_release(self):
        real_command = publisher.command
        mutations = []
        def fake_gh(*args, check=True):
            if args[0] != 'gh':
                return real_command(*args, check=check)
            if args[1] == 'api':
                return subprocess.CompletedProcess(args, 0,
                    '[[{"tag_name":"v0.2.0","draft":false}]]', '')
            mutations.append(args)
            return subprocess.CompletedProcess(args, 0, '', '')
        with repository() as (git, tested, remote), patch.object(publisher, 'command', side_effect=fake_gh):
            git('tag', 'v0.1.0'); git('push', 'origin', 'refs/tags/v0.1.0')
            before = git('--git-dir=' + str(remote), 'rev-parse', 'refs/tags/v0.1.0')
            publisher.publish('v0.1.0', tested, 'example/sdk', 'notes.md')
            self.assertEqual(git('--git-dir=' + str(remote), 'rev-parse', 'refs/tags/v0.1.0'), before)
        self.assertEqual(len(mutations), 1)
        self.assertEqual(mutations[0][1:3], ('release', 'create'))
        self.assertIn('--latest=false', mutations[0])
