import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('vtb_config',Path(__file__).with_name('acquire-vtb-configuration.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Configuration(unittest.TestCase):
 def test_sandbox_bound_origin_and_credentials(self):
  valid={'environment':'sandbox','user_name':'isolated','password':'synthetic-only','public_origin':'https://joba.com.kz','payment_form_path':'/payment/merchants/ecom/payment.html'}
  m.validate(valid)
  for patch in [{'environment':'production'},{'public_origin':'https://other.example'},{'password':''},{'password':'synthetic\ninjection'},{'payment_form_path':'https://other.example/payment/'}]:
   with self.assertRaises(ValueError):m.validate({**valid,**patch})
if __name__=='__main__':unittest.main()
