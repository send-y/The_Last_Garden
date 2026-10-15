import importlib.util
import io
import json
import pathlib
import tempfile
import time
import unittest

MODULE = pathlib.Path(__file__).with_name("server.py")


class BridgeTests(unittest.TestCase):
    def setUp(self):
        if not MODULE.exists():
            self.fail("Garden Bridge server missing")
        spec = importlib.util.spec_from_file_location("garden_bridge", MODULE)
        self.bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.bridge)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)

    def session(self, name, age=0):
        folder = self.root / name
        folder.mkdir()
        (folder / "requests").mkdir()
        (folder / "responses").mkdir()
        (folder / "manifest.json").write_text(json.dumps({"session_id": name, "heartbeat": time.time()-age, "pid": 100}), encoding="utf-8")
        return folder

    def test_discovery_excludes_stale_and_ambiguous_requires_id(self):
        self.session("100-abcdef01")
        self.session("200-abcdef02")
        self.session("300-abcdef03", 100)
        client = self.bridge.Client(self.root)
        self.assertEqual(len(client.sessions()), 2)
        with self.assertRaisesRegex(ValueError, "session_id"):
            client.resolve("")
        with self.assertRaises(ValueError):
            client.resolve("../outside")

    def test_protocol_and_unknown_tool(self):
        source = io.StringIO('\n'.join(json.dumps(x) for x in [
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}},
            {"jsonrpc":"2.0","method":"notifications/initialized"},
            {"jsonrpc":"2.0","id":2,"method":"tools/list"},
            {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"execute_code","arguments":{}}},
        ]))
        output = io.StringIO()
        self.bridge.serve(self.bridge.Client(self.root), source, output)
        replies = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([r['id'] for r in replies], [1,2,3])
        self.assertEqual(replies[0]['result']['protocolVersion'], '2025-06-18')
        self.assertEqual(len(replies[1]['result']['tools']), 5)
        self.assertTrue(replies[2]['result']['isError'])

    def test_no_session_error_and_params_rejected(self):
        client = self.bridge.Client(self.root)
        with self.assertRaisesRegex(ValueError,"running"):
            client.resolve("")
        with self.assertRaises(ValueError):
            client.call("get_state", {"path":"C:/secret"})


if __name__ == '__main__':
    unittest.main()
