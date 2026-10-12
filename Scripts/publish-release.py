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
    # Never force a tag or write to main. A concurrent matching tag is reusable.
    pushed = command('git', 'push', 'origin', f'refs/tags/{tag}', check=False)
    if pushed.returncode != 0:
        if remote_tag_commit(tag) != commit:
            pushed.check_returncode()


def list_releases(repository):
    # The tag lookup endpoint excludes drafts. The listing includes drafts for
    # this workflow's write-capable token; paginate so old partial releases count.
    response = command('gh', 'api', '--paginate', '--slurp',
                       f'repos/{repository}/releases?per_page=100')
    response.check_returncode()
    pages = json.loads(response.stdout)
    if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
        raise ValueError('Could not determine existing GitHub release state')
    return [release for page in pages for release in page]


def find_release(repository, tag, releases=None):
    if releases is None:
        releases = list_releases(repository)
    return next((release for release in releases if release.get('tag_name') == tag), None)


def version_number(tag):
    match = re.fullmatch(r'v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', tag)
    return tuple(map(int, match.groups())) if match else None


def publish(tag, commit, repository, notes):
    if not re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', tag):
        raise ValueError('Invalid stable release tag')
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Invalid release commit')
    if command('git', 'rev-parse', 'HEAD').stdout.strip() != commit:
        raise ValueError('Checkout does not match the tested release commit')
    releases = list_releases(repository)
    ensure_tag(tag, commit)
    release = find_release(repository, tag, releases)
    # Repairing an old release must not displace a newer published stable release.
    newer_published = any(
        not item.get('draft') and not item.get('prerelease') and
        version_number(item.get('tag_name', '')) is not None and
        version_number(item['tag_name']) > version_number(tag)
        for item in releases
    )
    latest_option = ['--latest=false'] if newer_published else []
    if release is not None:
        if release.get('draft'):
            # A tag-only API failure or a manually staged draft can be completed.
            command('gh', 'release', 'edit', tag, '--repo', repository, '--draft=false', *latest_option)
        print(f'{tag} already exists; keeping its tag and release contents')
        return
    command('gh', 'release', 'create', tag, '--repo', repository, '--verify-tag',
            '--title', f'CaylexChat {tag}', '--notes-file', notes, *latest_option)
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
