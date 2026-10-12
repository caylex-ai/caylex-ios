import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'Scripts' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bundle = load('verify-widget')
version = load('check-release-version')


class ReleaseChecks(unittest.TestCase):
    def test_new_stable_release(self):
        self.assertEqual(version.validate('0.2.0', ['v0.1.9', 'unrelated']), 'v0.2.0')
        self.assertEqual(version.validate('0.1.0', []), 'v0.1.0')

    def test_rejects_existing_and_older_versions(self):
        for candidate in ['0.1.9', '0.1.8']:
            with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                version.validate(candidate, ['v0.1.9'])

    def test_rejects_invalid_versions(self):
        for candidate in ['v0.1.0', '0.1', '01.2.3', '1.0.0-beta', '1.0.0\n', '$(touch secret)']:
            with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                version.validate(candidate, [])

    def test_checks_bundle_and_provenance(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'chat-widget.js').write_bytes(b'widget')
            metadata = dict(frontendCommit='a' * 40, frontendHasLocalChanges=False,
                            widgetVersion='0.1.36', sha256=hashlib.sha256(b'widget').hexdigest())
            def write(value):
                (root / 'widget-build.json').write_text(json.dumps(value))
            write(metadata)
            self.assertEqual(bundle.verify(root), metadata)
            for changes in [dict(sha256='bad'), dict(frontendHasLocalChanges=True),
                            dict(frontendCommit='bad'), dict(widgetVersion='')]:
                with self.subTest(changes=changes), self.assertRaises(ValueError):
                    write({**metadata, **changes})
                    bundle.verify(root)


if __name__ == '__main__':
    unittest.main()
