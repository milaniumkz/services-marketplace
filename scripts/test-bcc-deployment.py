import importlib.util,json,tempfile,pathlib,stat,unittest

def load(name):
 spec=importlib.util.spec_from_file_location(name,pathlib.Path(__file__).with_name(name+'.py'));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
bcc=load('prepare-bcc-deployment');installer=load('install-bcc-config');handoff=load('acquire-bcc-configuration')
class ConfigTests(unittest.TestCase):
 def config(self,**extra):
  return {'environment':'sandbox','terminal':'99012345','merchant':'OPKPOST99012345','mac_key':'12'*16,'public_origin':'https://joba.com.kz','countries':['KZ'],'currencies':['KZT'],**extra}
 def test_private_configuration_and_allowlists(self):
  c=self.config()
  with tempfile.TemporaryDirectory() as d:
   path=bcc.prepare(json.dumps(c),d);self.assertEqual(stat.S_IMODE(path.stat().st_mode),0o600);self.assertEqual(json.loads(path.read_text())['merchant'],c['merchant'])
   for patch in [{'public_origin':'https://evil.example'},{'environment':'unknown'},{'mac_key':'bad'},{'countries':['RU']},{'currencies':['RUB']},{'merchant':'<script>'}]:
    with self.assertRaises(ValueError):bcc.prepare(json.dumps({**c,**patch}),d)
   self.assertIsNone(bcc.prepare('',d))
 def test_production_requires_real_separation_and_explicit_notification_setup(self):
  with tempfile.TemporaryDirectory() as d:
   c=self.config(environment='production')
   with self.assertRaises(ValueError):bcc.prepare(json.dumps(c),d)
   c.update(notification_mode='bank-managed',notifications_registered=True)
   saved=json.loads(bcc.prepare(json.dumps(c),d).read_text());self.assertNotIn('notify_password',saved)
   for patch in [{'terminal':'88888881'},{'mac_key':'6BB0AC02E47BDF73D98FEB777F3B5294'},{'notifications_registered':False}]:
    with self.assertRaises(ValueError):bcc.prepare(json.dumps({**c,**patch}),d)
   with self.assertRaises(ValueError):handoff.validate(c,'sandbox')
   self.assertEqual(handoff.validate(c,'production')['environment'],'production')
   pending=self.config(environment='production',notify_user='fixture-only',notify_password='synthetic-only-callback-password',callback_registered=False)
   with self.assertRaises(ValueError):handoff.validate(pending,'production')
   self.assertFalse(handoff.validate(pending,'production-pending')['callback_registered'])
 def test_atomic_backup_rollback_and_preflight_preserve_other_banks(self):
  with tempfile.TemporaryDirectory() as directory:
   root=pathlib.Path(directory);target=root/'payments/bcc.json';target.parent.mkdir();before=json.dumps(self.config()).encode();target.write_bytes(before)
   vtb=root/'payments/vtb.json';vtb.write_bytes(b'other-provider-unchanged')
   raw=json.dumps(self.config(merchant='NEW99012345'))
   with self.assertRaises(ValueError):installer.apply(raw,target,root/'backups',preflight=lambda c:False)
   self.assertEqual(target.read_bytes(),before)
   receipt=installer.apply(raw,target,root/'backups');self.assertEqual(json.loads(target.read_bytes())['merchant'],'NEW99012345');self.assertEqual(stat.S_IMODE(target.stat().st_mode),0o600)
   installer.rollback(receipt,target);self.assertEqual(target.read_bytes(),before);self.assertEqual(vtb.read_bytes(),b'other-provider-unchanged')
if __name__=='__main__':unittest.main()
