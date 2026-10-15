"""Read-only diagnostics from the authorized GitHub runner; no credentials."""
import hashlib,os,socket,subprocess
host=os.environ.get('JOBA_SSH_HOST','188.241.217.228')
port=int(os.environ.get('JOBA_SSH_PORT','22'))
domain=os.environ.get('JOBA_DOMAIN','jobs.app.kz')
try: print('::notice title=Public DNS::'+domain+' '+', '.join(sorted({r[4][0] for r in socket.getaddrinfo(domain,443,type=socket.SOCK_STREAM)})))
except OSError as e: print('::warning title=Public DNS unavailable::'+str(e))
try:
    with socket.create_connection((host,port),timeout=10) as connection:
        connection.settimeout(10);print('SSH banner:',connection.recv(512).decode('ascii',errors='replace').strip())
except OSError as e:
    print('::error title=SSH connection unavailable::'+str(e));raise SystemExit('SSH connection failed before authentication')
keys=subprocess.run(['ssh-keyscan','-T','10','-p',str(port),host],check=True,capture_output=True,text=True).stdout
if not keys.strip(): raise SystemExit('No SSH host key was returned')
# Public host keys only. Pin after checking the fingerprint in the hosting panel.
open('server-known-hosts.txt','w').write(keys)
fingerprints=subprocess.run(['ssh-keygen','-lf','server-known-hosts.txt'],check=True,capture_output=True,text=True).stdout
for line in fingerprints.splitlines():print('::notice title=SSH host key fingerprint::'+line)
