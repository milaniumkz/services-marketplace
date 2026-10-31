"""Read-only aggregate JOBA advertising counters; no private account information."""
import datetime,json,subprocess
from pathlib import Path
from zoneinfo import ZoneInfo
now=datetime.datetime.now(datetime.timezone.utc);local=now.astimezone(ZoneInfo('Asia/Yekaterinburg'));start=local.replace(hour=0,minute=0,second=0,microsecond=0).astimezone(datetime.timezone.utc);end=start+datetime.timedelta(days=1)
root=Path('/opt/joba/current').resolve();cmd=['docker','compose','--env-file','/etc/joba/production.env','-f',str(root/'infra/production/compose.yaml'),'exec','-T','database','psql','-U','joba','-d','joba','-At','-c']
def query(sql):return [json.loads(r) for r in subprocess.run(cmd+[sql],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,check=True).stdout.splitlines() if r]
window="data->>'created_at'>='"+start.isoformat().replace('+00:00','Z')+"' AND data->>'created_at'<'"+end.isoformat().replace('+00:00','Z')+"'"
sessions=query("SELECT json_build_object('country',country,'status',data->>'status','count',COUNT(*)) FROM records WHERE kind='web_ad_session' AND "+window+" GROUP BY country,data->>'status'")
completed=query("SELECT json_build_object('country',country,'completed_views',COUNT(*)) FROM records WHERE kind='web_ad_session' AND data->>'status' IN('credited','granted') AND "+window+" GROUP BY country")
redemptions=query("SELECT json_build_object('country',country,'target',data->>'target','count',COUNT(*)) FROM records WHERE kind='web_ad_redemption' AND "+window+" GROUP BY country,data->>'target'")
print(json.dumps({'checked_at':now.isoformat(),'local_day':str(local.date()),'timezone':'Asia/Yekaterinburg','read_only':True,'rewarded_sessions_today':sessions,'reported_completed_views_today':completed,'reward_redemptions_today':redemptions,'ordinary_banner_impressions_tracking':'not_recorded_in_joba','yandex_income_import':'not_connected','yandex_income_amount':None},ensure_ascii=False))
