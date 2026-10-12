#!/usr/bin/env python3
"""Verify the committed iOS widget bundle and its frontend provenance."""
import hashlib
import json
from pathlib import Path
import re
import sys


def verify(root: Path) -> dict:
    metadata = json.loads((root / 'widget-build.json').read_text())
    checksum = hashlib.sha256((root / 'chat-widget.js').read_bytes()).hexdigest()
    if metadata.get('sha256') != checksum:
        raise ValueError('Widget bundle checksum does not match widget-build.json')
    if metadata.get('frontendHasLocalChanges') is not False:
        raise ValueError('Widget must be built from a clean committed frontend checkout')
    if not re.fullmatch(r'[0-9a-f]{40}', str(metadata.get('frontendCommit', ''))):
        raise ValueError('Missing or invalid frontend source commit')
    if not isinstance(metadata.get('widgetVersion'), str) or not metadata['widgetVersion'].strip():
        raise ValueError('Missing widget version')
    return metadata


if __name__ == '__main__':
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'Sources/CaylexChat/Resources'
    try:
        metadata = verify(root)
    except (OSError, ValueError) as error:
        sys.exit(str(error))
    print(f"Verified widget {metadata['widgetVersion']} from {metadata['frontendCommit']}")
