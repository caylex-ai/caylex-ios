#!/usr/bin/env python3
"""Publish the tested commit, recovering safely from a tag-only partial release."""
import argparse
import json
import re
import subprocess
import sys


def command(*args, check=True):
    return subprocess.run(args, text=True, capture_output=True, check=check)


def remote_tag_commit(tag):
    # Read the remote tag at publication time; checkout's local tags may be stale.
    result = command('git', 'ls-remote', '--exit-code', 'origin', f'refs/tags/{tag}', check=False)
    if result.returncode == 2:
        return None
    result.check_returncode()
    command('git', 'fetch', '--no-tags', 'origin', f'refs/tags/{tag}')
    return command('git', 'rev-parse', 'FETCH_HEAD^{commit}').stdout.strip()


def ensure_tag(tag, commit):
    existing = remote_tag_commit(tag)
    if existing is not None:
        if existing != commit:
            raise ValueError(f'{tag} already points to a different commit; it will not be moved')
        return
    local = command('git', 'rev-parse', '--verify', f'refs/tags/{tag}^{{commit}}', check=False)
    if local.returncode == 0:
        if local.stdout.strip() != commit:
            raise ValueError(f'Local {tag} points to a different commit')
    else:
        command('git', 'tag', '-a', tag, commit, '-m', f'CaylexChat {tag}')
    # Never force a tag or write to prod. A concurrent matching tag is reusable.
    pushed = command('git', 'push', 'origin', f'refs/tags/{tag}', check=False)
    if pushed.returncode != 0:
        if remote_tag_commit(tag) != commit:
            pushed.check_returncode()


def find_release(repository, tag):
    response = command('gh', 'api', '--include', f'repos/{repository}/releases/tags/{tag}', check=False)
    status = re.match(r'HTTP/\S+\s+(\d+)', response.stdout)
    if status and status.group(1) == '404':
        return None
    # Authentication/network failures must not be mistaken for a missing release.
    response.check_returncode()
    if not status or status.group(1) != '200':
        raise ValueError('Could not determine existing GitHub release state')
    _, body = re.split(r'\r?\n\r?\n', response.stdout, maxsplit=1)
    return json.loads(body)


def publish(tag, commit, repository, notes):
    if not re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', tag):
        raise ValueError('Invalid stable release tag')
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Invalid release commit')
    if command('git', 'rev-parse', 'HEAD').stdout.strip() != commit:
        raise ValueError('Checkout does not match the tested release commit')
    ensure_tag(tag, commit)
    release = find_release(repository, tag)
    if release is not None:
        if release.get('draft'):
            # A tag-only API failure or a manually staged draft can be completed.
            command('gh', 'release', 'edit', tag, '--repo', repository, '--draft=false')
        print(f'{tag} already exists; keeping its tag and release contents')
        return
    command('gh', 'release', 'create', tag, '--repo', repository, '--verify-tag',
            '--title', f'CaylexChat {tag}', '--notes-file', notes)
    print(f'Published {tag} at tested commit {commit}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--notes', required=True)
    args = parser.parse_args()
    try:
        publish(args.tag, args.commit, args.repository, args.notes)
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
