"""One-time RSA-OAEP handoff to an identified GitHub job; no plaintext in Git.

Prefer Actions Secrets. Bootstrap fallback publishes only a public challenge,
reads one encrypted envelope, validates its job/commit/nonce, and destroys the
private key. The caller masks the resulting value before exporting it.
"""
import base64,json,os,secrets,subprocess,tempfile,time,urllib.error,urllib.request
from pathlib import Path

def openssl(*args,input=None):
    result=subprocess.run(['openssl',*args],input=input,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if result.returncode:raise ValueError('Deployment credential cryptography failed')
    return result.stdout

def challenge(directory,run_id,commit):
    private=directory/'recipient.pem'
    openssl('genpkey','-algorithm','RSA','-pkeyopt','rsa_keygen_bits:3072','-out',str(private))
    private.chmod(0o600)
    public=openssl('pkey','-in',str(private),'-pubout','-outform','DER')
    return private,{'run_id':run_id,'commit':commit,'nonce':secrets.token_hex(24),'public_key_der':base64.b64encode(public).decode()}

def decrypt(private,request,envelope):
    if any(envelope.get(k)!=request[k] for k in ['run_id','commit','nonce']):raise ValueError('Deployment envelope does not match this job')
    ciphertext=base64.b64decode(envelope['ciphertext'],validate=True)
    plain=openssl('pkeyutl','-decrypt','-inkey',str(private),'-pkeyopt','rsa_padding_mode:oaep','-pkeyopt','rsa_oaep_md:sha256','-pkeyopt','rsa_mgf1_md:sha256',input=ciphertext)
    value=json.loads(plain)
    if any(value.get(k)!=request[k] for k in ['run_id','commit','nonce']):raise ValueError('Deployment envelope context is invalid')
    password=value.get('password')
    if not isinstance(password,str) or not password or len(password)>2048 or '\n' in password or '\r' in password:raise ValueError('Invalid password format')
    return password

def acquire():
    if os.environ.get('SSHPASS'):return os.environ['SSHPASS']
    if os.environ.get('SSH_PRIVATE_KEY'):return ''
    if os.environ.get('GITHUB_ACTIONS')!='true':raise RuntimeError('One-time credential handoff requires GitHub Actions')
    run_id=os.environ['GITHUB_RUN_ID']+'-'+os.environ['GITHUB_RUN_ATTEMPT']
    with tempfile.TemporaryDirectory(prefix='joba-recipient-') as directory:
        private,request=challenge(Path(directory),run_id,os.environ['GITHUB_SHA'])
        print('::notice title=Deployment credential challenge::'+json.dumps(request,separators=(',',':')),flush=True)
        endpoint='https://api.github.com/repos/'+os.environ['GITHUB_REPOSITORY']+'/contents/envelope.json?ref=deploy/credential-'+run_id
        deadline=time.monotonic()+600
        while time.monotonic()<deadline:
            http=urllib.request.Request(endpoint,headers={'Authorization':'Bearer '+os.environ['GITHUB_TOKEN'],'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28','User-Agent':'joba-deployment-bootstrap'})
            try:
                with urllib.request.urlopen(http,timeout=20) as response:record=json.load(response)
                envelope=json.loads(base64.b64decode(record['content']))
                return decrypt(private,request,envelope)
            except urllib.error.HTTPError as error:
                if error.code!=404:raise RuntimeError('Credential envelope could not be read') from None
            time.sleep(5)
        raise RuntimeError('Protected deployment credential was not provided within 10 minutes')

if __name__=='__main__':
    value=acquire()
    # Escape workflow command metacharacters before registering the mask.
    if value:print('::add-mask::'+value.replace('%','%25').replace('\r','%0D').replace('\n','%0A'),flush=True)
    with open(os.environ['GITHUB_ENV'],'a') as output:output.write('JOBA_RUNTIME_SSH_PASSWORD='+value+'\n')
    print('Protected deployment credential acquired; no plaintext was published',flush=True)
