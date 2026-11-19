"""Read-only account lookup in live PostgreSQL and recent deployment snapshots.
Only targeted account metadata is printed. Credentials and document contents are never output.
"""
import datetime,json,re,subprocess,sys
from pathlib import Path
phone=sys.argv[1]
if not re.fullmatch(r'\+[0-9]{8,15}',phone):raise SystemExit('Invalid E.164 phone')
root=Path('/opt/joba/current').resolve()
compose=['docker','compose','--env-file','/etc/joba/production.env','-f',str(root/'infra/production/compose.yaml')]
def query(sql):
 p=subprocess.run(compose+['exec','-T','database','psql','-U','joba','-d','joba','-At','-c',sql],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,check=True)
 return [json.loads(line) for line in p.stdout.splitlines() if line.strip()]
fields="json_build_object('id',id,'country',country,'status',data->>'status','created_at',data->>'created_at','deleted_at',data->>'deleted_at','deletion_request_id',data->>'deletion_request_id','has_credentials',EXISTS(SELECT 1 FROM credentials c WHERE c.user_id=records.id))"
live=query("SELECT "+fields+" FROM records WHERE kind='user' AND (data->>'phone'='"+phone+"' OR id IN(SELECT user_id FROM credentials WHERE phone='"+phone+"'))")
ids={r['id'] for r in live};history=[];scanned=0
escapes={'b':'\b','f':'\f','n':'\n','r':'\r','t':'\t','v':'\v','\\':'\\'}
def uncopy(value):return re.sub(r'\\([0-7]{1,3}|.)',lambda m:chr(int(m[1],8)) if re.fullmatch('[0-7]{1,3}',m[1]) else escapes.get(m[1],m[1]),value)
for backup in sorted(Path('/var/backups/joba').glob('*/database.sql'),reverse=True)[:30]:
 columns=None;scanned+=1
 with backup.open(errors='strict') as stream:
  for line in stream:
   if line.startswith('COPY public.records '):columns=line.split('(',1)[1].split(')',1)[0].split(', ');continue
   if columns is None:continue
   if line.rstrip()=='\\.':columns=None;continue
   if phone not in line:continue
   values=line.rstrip('\n').split('\t');row=dict(zip(columns,values))
   if row.get('kind')!='user':continue
   data=json.loads(uncopy(row['data']))
   if data.get('phone')!=phone:continue
   ids.add(data['id']);history.append({'snapshot':backup.parent.name,'id':data['id'],'country':data['country'],'status':data.get('status'),'created_at':data.get('created_at'),'deleted_at':data.get('deleted_at'),'deletion_request_id':data.get('deletion_request_id')})
if ids:
 literals=','.join("'"+str(__import__('uuid').UUID(i))+"'" for i in ids)
 live=query("SELECT "+fields+" FROM records WHERE kind='user' AND id IN("+literals+")")
 audit=query("SELECT json_build_object('action',data->>'action','created_at',data->>'created_at','actor_id',data->>'actor_id','target_id',data->>'target_id') FROM records WHERE kind='audit' AND data->>'target_id' IN("+literals+") ORDER BY data->>'created_at' DESC LIMIT 30")
 privacy=query("SELECT json_build_object('id',id,'owner',owner,'country',country,'type',data->>'type','status',data->>'status','created_at',data->>'created_at','execute_after',data->>'execute_after','requested_by',data->>'requested_by') FROM records WHERE kind='privacy' AND owner IN("+literals+")")
else:audit=[];privacy=[]
print(json.dumps({'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'read_only':True,'live':live,'snapshot_matches':history,'snapshots_scanned':scanned,'audit':audit,'privacy_requests':privacy},ensure_ascii=False))
