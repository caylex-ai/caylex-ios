#!/usr/bin/env python3
"""Allow a new stable version or a retry of the same immutable commit."""
import re
import subprocess
import sys

PATTERN = r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'


def validate(version: str, tags: list[str], resume_commit: str | None = None,
             tag_commits: dict[str, str] | None = None) -> str:
    match = re.fullmatch(PATTERN, version)
    if not match:
        raise ValueError('Enter a stable semantic version such as 0.1.0, without a v prefix')
    number = tuple(map(int, match.groups()))
    target = 'v' + version
    if (target in tags and resume_commit is not None and
            (tag_commits or {}).get(target) == resume_commit):
        return target
    for tag in tags:
        existing = re.fullmatch(PATTERN, tag.removeprefix('v'))
        if existing and tuple(map(int, existing.groups())) >= number:
            raise ValueError(f'Version must be newer than existing release tag {tag}, or retry its exact commit')
    return 'v' + version


if __name__ == '__main__':
    try:
        tags = subprocess.check_output(['git', 'tag'], text=True).splitlines()
        commit = sys.argv[2] if len(sys.argv) > 2 else None
        target = 'v' + sys.argv[1]
        commits = {}
        if commit and target in tags:
            commits[target] = subprocess.check_output(
                ['git', 'rev-parse', f'refs/tags/{target}^{{commit}}'], text=True).strip()
        print(validate(sys.argv[1], tags, commit, commits))
    except (ValueError, IndexError) as error:
        sys.exit(str(error))
