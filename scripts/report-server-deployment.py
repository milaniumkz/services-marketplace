"""Publish masked CI deployment diagnostics and a read-only HTTPS probe."""
import json,os,ssl,urllib.request,urllib.error
root='https://api.github.com/repos/'+os.environ['GITHUB_REPOSITORY']
headers={'Authorization':'Bearer '+os.environ['GITHUB_TOKEN'],'Accept':'application/vnd.github+json','Content-Type':'application/json','User-Agent':'joba-server-diagnostics'}
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None
parts=[]
request=urllib.request.Request(root+'/actions/jobs/'+os.environ['JOBA_DIAGNOSTIC_JOB']+'/logs',headers=headers)
try:
    urllib.request.build_opener(NoRedirect).open(request,timeout=20)
except urllib.error.HTTPError as response:
    if response.code!=302:raise
    # Authentication is not forwarded to the signed storage URL.
    location=response.headers['Location']
    with urllib.request.urlopen(location,timeout=30) as archive:log=archive.read().decode('utf-8',errors='replace')
    parts.append('Deployment log tail (GitHub-masked):\n```\n'+'\n'.join(log.splitlines()[-100:])[-20000:]+'\n```')
url='https://188-241-217-228.sslip.io'
for path in ['/health','/','/api/v1/legal/documents?country=KZ&locale=ru&required=true']:
    try:
        with urllib.request.urlopen(url+path,timeout=15,context=ssl.create_default_context()) as response:
            data=response.read(50000).decode('utf-8',errors='replace') if path!='/' else 'HTML served'
            parts.append(url+path+' verified TLS / HTTP '+str(response.status)+': '+data)
    except Exception as error:parts.append(url+path+' unavailable: '+str(error))
payload={'name':'server-deployment-diagnostics','head_sha':os.environ['GITHUB_SHA'],'status':'completed','conclusion':'neutral','output':{'title':'Server deployment diagnostics','summary':'\n\n'.join(parts)}}
request=urllib.request.Request(root+'/check-runs',method='POST',headers=headers,data=json.dumps(payload).encode())
with urllib.request.urlopen(request,timeout=20) as response:print('Diagnostics published as check',json.load(response)['id'])
