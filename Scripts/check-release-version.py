#!/usr/bin/env python3
"""Allow only a new, increasing stable semantic version."""
import re
import subprocess
import sys

PATTERN = r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'


def validate(version: str, tags: list[str]) -> str:
    match = re.fullmatch(PATTERN, version)
    if not match:
        raise ValueError('Enter a stable semantic version such as 0.1.0, without a v prefix')
    number = tuple(map(int, match.groups()))
    for tag in tags:
        existing = re.fullmatch(PATTERN, tag.removeprefix('v'))
        if existing and tuple(map(int, existing.groups())) >= number:
            raise ValueError(f'Version must be newer than existing release tag {tag}')
    return 'v' + version


if __name__ == '__main__':
    try:
        tags = subprocess.check_output(['git', 'tag'], text=True).splitlines()
        print(validate(sys.argv[1], tags))
    except (ValueError, IndexError) as error:
        sys.exit(str(error))
