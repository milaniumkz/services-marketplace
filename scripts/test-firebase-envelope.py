import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


def module(name):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(name+'.py'))
    loaded=importlib.util.module_from_spec(spec);spec.loader.exec_module(loaded);return loaded


class FirebaseEnvelope(unittest.TestCase):
    def test_large_payload_authentication_and_job_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            private,request=module('acquire-deployment-credential').challenge(Path(directory),'isolated-run-1','isolated-commit')
            request['purpose']='firebase-config-v1'
            helper=module('acquire-firebase-configuration');aad=helper.context(request)
            payload={'test_secret':'isolated-data-'*400}
            result=subprocess.run(['node',str(Path(__file__).with_name('firebase-envelope.cjs'))],input=json.dumps({'mode':'encrypt','public_key_der':request['public_key_der'],'aad':aad,'payload':payload}).encode(),capture_output=True,check=True)
            envelope=json.loads(result.stdout)
            self.assertNotIn('isolated-data',result.stdout.decode())
            self.assertEqual(helper.decrypt(private,request,envelope),payload)
            with self.assertRaises(ValueError):helper.decrypt(private,{**request,'nonce':'another-job'},envelope)
            with self.assertRaises(ValueError):helper.decrypt(private,request,{**envelope,'ciphertext':envelope['ciphertext'][:-8]+'AAAAAAAA'})


if __name__=='__main__':unittest.main()
