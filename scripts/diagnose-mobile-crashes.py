"""Read-only crash diagnostics from the production database (no user records)."""
import datetime,json,subprocess
from pathlib import Path
root=Path('/opt/joba/current').resolve()
cmd=['docker','compose','--env-file','/etc/joba/production.env','-f',str(root/'infra/production/compose.yaml'),'exec','-T','database','psql','-U','joba','-d','joba','-At','-c']
def query(sql):
 result=subprocess.run(cmd+[sql],capture_output=True,text=True,check=True)
 return [json.loads(line) for line in result.stdout.splitlines() if line]
reports=query("SELECT json_build_object('id',id,'received_at',received_at,'report',report) FROM mobile_crash_reports ORDER BY received_at DESC LIMIT 50")
counts=query("SELECT json_build_object('kind',report->>'kind','app_version',report->>'app_version','count',COUNT(*)) FROM mobile_crash_reports WHERE received_at>now()-interval '7 days' GROUP BY report->>'kind',report->>'app_version'")
print(json.dumps({'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'read_only':True,'retention_days':30,'source':'client_reported','counts_7_days':counts,'reports':reports},ensure_ascii=False))
