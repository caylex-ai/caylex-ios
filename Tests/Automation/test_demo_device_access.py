"""Verify that exposing the local demo on Wi-Fi cannot mint tokens without pairing."""
import importlib.util
import json
import pathlib
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('demo_server', ROOT / 'Examples/ChatDemo/demo-server.py')
demo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(demo)


class DeviceAccessTests(unittest.TestCase):
    def test_loopback_works_without_pairing(self):
        demo.validate_bind_address('127.0.0.1', None)

    def test_network_binding_requires_pairing(self):
        for host in ['0.0.0.0', '192.168.1.20', '::']:
            with self.subTest(host=host), self.assertRaises(ValueError):
                demo.validate_bind_address(host, None)
        demo.validate_bind_address('192.168.1.20', 'random-pairing-key')

    def test_only_paired_native_requests_can_mint(self):
        token = 'a' * 43
        result = {'apiBaseUrl': 'https://example.com/', 'widgetToken': 'short-lived-token', 'userName': 'Tester'}
        with patch.object(demo, 'device_access_token', token), patch.object(demo, 'mint_live_token', return_value=result) as mint:
            server = ThreadingHTTPServer(('127.0.0.1', 0), demo.Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                url = f'http://127.0.0.1:{server.server_port}/demo/config'
                for headers in [
                    {}, {'X-Caylex-Demo': '1'},
                    {'X-Caylex-Demo': '1', 'Authorization': 'Bearer incorrect'},
                    {'Authorization': 'Bearer ' + token},
                ]:
                    with self.subTest(headers=list(headers)), self.assertRaises(urllib.error.HTTPError) as error:
                        urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=2)
                    self.assertEqual(error.exception.code, 403)
                mint.assert_not_called()
                request = urllib.request.Request(url, headers={'X-Caylex-Demo': '1', 'Authorization': 'Bearer ' + token})
                with urllib.request.urlopen(request, timeout=2) as response:
                    self.assertEqual(json.load(response), result)
                    self.assertEqual(response.headers['Cache-Control'], 'no-store')
                mint.assert_called_once()
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)


if __name__ == '__main__':
    unittest.main()
