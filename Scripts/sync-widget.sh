#!/bin/bash
set -euo pipefail
package_root="$(cd "$(dirname "$0")/.." && pwd)"
frontend_root="${1:-$package_root/../caylex-frontend}"
widget_root="$frontend_root/packages/chat-widget"
if [ ! -f "$widget_root/vite.ios.config.ts" ]; then
  echo 'The frontend checkout must include the iOS bridge and build configuration.' >&2
  exit 1
fi
(cd "$frontend_root" && npm run build:ios -w @caylex/chat-widget)
cp "$widget_root/dist-ios/chat-widget.js" "$package_root/Sources/CaylexChat/Resources/chat-widget.js"
python3 - "$frontend_root" "$package_root" <<'PY'
import hashlib, json, pathlib, subprocess, sys
frontend, package = map(pathlib.Path, sys.argv[1:])
bundle = package / 'Sources/CaylexChat/Resources/chat-widget.js'
metadata = {
    'frontendCommit': subprocess.check_output(['git', '-C', str(frontend), 'rev-parse', 'HEAD'], text=True).strip(),
    'frontendHasLocalChanges': bool(subprocess.check_output(['git', '-C', str(frontend), 'status', '--porcelain'], text=True).strip()),
    'widgetVersion': json.loads((frontend / 'packages/chat-widget/package.json').read_text())['version'],
    'sha256': hashlib.sha256(bundle.read_bytes()).hexdigest(),
}
(package / 'Sources/CaylexChat/Resources/widget-build.json').write_text(json.dumps(metadata, indent=2) + '\n')
PY
