"""Targeted read-only counts for a public referral code; never exports identities."""
import datetime,json,re,subprocess,sys
from pathlib import Path
code=sys.argv[1]
if not re.fullmatch(r'[0-9a-f]{12}',code):raise SystemExit('Invalid public referral code')
root=Path('/opt/joba/current').resolve()
cmd=['docker','compose','--env-file','/etc/joba/production.env','-f',str(root/'infra/production/compose.yaml'),'exec','-T','database','psql','-U','joba','-d','joba','-At','-v','ON_ERROR_STOP=1','-c']
sql="""
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout='10s';
WITH c AS (SELECT owner,country FROM records WHERE kind='referral_code' AND data->>'code'='%s')
SELECT json_build_object(
 'country',c.country,
 'outgoing_total',(SELECT count(*) FROM records r WHERE r.kind='referral_attribution' AND r.country=c.country AND r.data->>'referrer_id'=c.owner::text),
 'outgoing_qualified',(SELECT count(*) FROM records r WHERE r.kind='referral_attribution' AND r.country=c.country AND r.data->>'referrer_id'=c.owner::text AND r.data->>'status'='qualified'),
 'outgoing_pending',(SELECT count(*) FROM records r WHERE r.kind='referral_attribution' AND r.country=c.country AND r.data->>'referrer_id'=c.owner::text AND r.data->>'status'='pending'),
 'has_entered_someone_elses_code',EXISTS(SELECT 1 FROM records r WHERE r.kind='referral_attribution' AND r.country=c.country AND r.owner=c.owner AND r.data->>'referrer_id'<>c.owner::text),
 'rewards_owned',(SELECT count(*) FROM records r WHERE r.kind='referral_reward' AND r.country=c.country AND r.owner=c.owner),
 'country_attributions',(SELECT count(*) FROM records r WHERE r.kind='referral_attribution' AND r.country=c.country),
 'account_active',EXISTS(SELECT 1 FROM records r WHERE r.kind='user' AND r.id::text=c.owner::text AND r.data->>'status'='active')
) FROM c;
ROLLBACK;
"""%code
p=subprocess.run(cmd+[sql],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,check=True)
rows=[json.loads(line) for line in p.stdout.splitlines() if line.startswith('{')]
print(json.dumps({'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'read_only':True,'matching_codes':len(rows),'counts':rows},ensure_ascii=False))
