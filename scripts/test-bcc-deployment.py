import importlib.util,json,tempfile,pathlib,stat,unittest
spec=importlib.util.spec_from_file_location('bcc',pathlib.Path(__file__).with_name('prepare-bcc-deployment.py'));bcc=importlib.util.module_from_spec(spec);spec.loader.exec_module(bcc)
class ConfigTests(unittest.TestCase):
 def test_private_configuration_and_allowlists(self):
  c={'environment':'sandbox','terminal':'12345678','merchant':'12345678','mac_key':'12'*16,'public_origin':'https://joba.com.kz','countries':['KZ'],'currencies':['KZT']}
  with tempfile.TemporaryDirectory() as d:
   path=bcc.prepare(json.dumps(c),d);self.assertEqual(stat.S_IMODE(path.stat().st_mode),0o600);self.assertEqual(json.loads(path.read_text())['terminal'],c['terminal'])
   for patch in [{'public_origin':'https://evil.example'},{'environment':'unknown'},{'mac_key':'bad'},{'countries':['RU']},{'currencies':['RUB']}]:
    with self.assertRaises(ValueError):bcc.prepare(json.dumps({**c,**patch}),d)
   self.assertIsNone(bcc.prepare('',d))
if __name__=='__main__':unittest.main()
