"""The source guard is deliberately limited; runtime validation covers aliases."""
import importlib.util
from pathlib import Path
import unittest

GUARD = Path(__file__).with_name("structure_write_guard.py")

class GuardTests(unittest.TestCase):
    def test_write_guard_exists_and_detects_live_writes(self):
        self.assertTrue(GUARD.exists(), "Automated live-structure write guard is required")
        spec = importlib.util.spec_from_file_location("structure_write_guard", GUARD)
        guard = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(guard)
        bad = ["sim.state.structures.append(record)", 'sim.state["structures"].clear()',
               "var items = sim.state.structures\nitems.erase(record)",
               'var item = sim._find_structure([1,2])\nitem["lit"] = false',
               "for item: Dictionary in sim.state.structures:\n\titem.open = true"]
        for source in bad:
            with self.subTest(source=source):
                self.assertTrue(guard.violations(source), source)
        self.assertFalse(guard.violations("sim.add_structure(record)\nvar open = bool(item.open)"))
        self.assertFalse(guard.violations("var structures: Array = []\nstructures.append(record)"))

if __name__ == "__main__":
    unittest.main()
