import importlib.util
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
spec = importlib.util.spec_from_file_location('metrics', Path(__file__).with_name('collect-server-metrics.py'))
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)

class HostMetricsTest(unittest.TestCase):
    def test_counters_and_delta(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root/'net').mkdir()
            (root/'meminfo').write_text('MemTotal: 4000 kB\nMemAvailable: 3000 kB\nMemFree: 100 kB\nSwapTotal: 100 kB\nSwapFree: 80 kB\n')
            (root/'stat').write_text('cpu 100 0 0 900 0 0 0 0 40 0\n')
            (root/'cpuinfo').write_text('processor\t: 0\nprocessor\t: 1\n')
            (root/'loadavg').write_text('0.1 0.2 0.3 1/10 42\n')
            (root/'uptime').write_text('3600.5 4000.0\n')
            (root/'net/route').write_text('Iface Destination\neth0 00000000\n')
            (root/'net/dev').write_text('head\nhead\neth0: 1000 0 0 0 0 0 0 0 2000 0 0 0 0 0 0 0\nveth1: 9000 0 0 0 0 0 0 0 9000 0 0 0 0 0 0 0\n')
            disk=lambda _: SimpleNamespace(f_blocks=1000,f_bfree=700,f_bavail=600,f_frsize=4096)
            first=metrics.collect(root,clock=lambda:100,disk=disk)
            self.assertIsNone(first['cpu']['usage_percent'])
            self.assertEqual(first['cpu']['logical_cores'],2)
            self.assertEqual(first['memory']['used_bytes'],1000*1024)
            self.assertEqual(first['disk']['used_bytes'],300*4096)
            (root/'stat').write_text('cpu 150 0 0 950 0 0 0 0 40 0\n')
            (root/'net/dev').write_text('head\nhead\neth0: 1400 0 0 0 0 0 0 0 2600 0 0 0 0 0 0 0\n')
            second=metrics.collect(root,previous=first,clock=lambda:120,disk=disk)
            self.assertEqual(second['cpu']['usage_percent'],50)
            self.assertEqual(second['network']['received_bytes_per_second'],20)
            self.assertEqual(second['network']['sent_bytes_per_second'],30)
            self.assertEqual(len(second['history']),2)

if __name__ == '__main__':
    unittest.main()
