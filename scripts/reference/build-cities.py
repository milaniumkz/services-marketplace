from pathlib import Path
import zipfile,json,hashlib,datetime,collections,re
root=Path('/workspace/joba-reference-sources');out=Path('services/api/reference');out.mkdir(exist_ok=True)
country_codes=['KZ','KG','RU','BY'];cities=[]
with zipfile.ZipFile(root/'cities500.zip') as z:
 for line in z.read('cities500.txt').decode().splitlines():
  f=line.split('\t')
  if f[8] in country_codes and f[6]=='P' and f[7] not in ['PPLX','PPLH','PPLQ','PPLW']:
   cities.append(f)
# Alatau became a city in 2024; the old Zhetygen record has no population
# and is therefore absent from cities500. Retain the real GeoNames identifier.
with zipfile.ZipFile(root/'KZ.zip') as z:
 for line in z.read('KZ.txt').decode().splitlines():
  f=line.split('\t')
  if f[0]=='1539946' and not any(c[0]==f[0] for c in cities):cities.append(f)
admin={}
for line in (root/'admin1CodesASCII.txt').read_text().splitlines():
 f=line.split('\t')
 if f[0].split('.')[0] in country_codes:admin[f[0]]={'name':f[1],'id':f[3]}
needed={f[0] for f in cities}|{v['id'] for v in admin.values()};names=collections.defaultdict(dict);aliases=collections.defaultdict(set)
for country in country_codes:
 with zipfile.ZipFile(root/(country+'-alternates.zip')) as z:
  for line in z.read(country+'.txt').decode().splitlines():
   f=line.split('\t');f+=['']*(10-len(f))
   if f[1] not in needed or f[2] not in ['ru','kk','ky','be','en'] or not f[3] or len(f[3])>100:continue
   aliases[f[1]].add(f[3]);score=(f[6]!='1',bool(re.search('[А-Яа-яЁё]',f[3])) if f[2]=='ru' else True,f[4]=='1',f[5]!='1')
   if f[2] not in names[f[1]] or score>names[f[1]][f[2]][0]:names[f[1]][f[2]]=(score,f[3])
result={c:[] for c in country_codes}
for f in cities:
 labels={k:v[1] for k,v in names[f[0]].items()};name=labels.get('ru')
 if not name or not re.search('[А-Яа-яЁё]',name):
  name=next((n for n in f[3].split(',') if re.fullmatch('[А-Яа-яЁё0-9 .()—-]+',n)),f[1])
 if f[0]=='1539946':name='Алатау';labels['ru']=name
 if f[0]=='1528249':name='Манас';labels['ru']=name
 a=admin.get(f[8]+'.'+f[10],{});region=names[a.get('id','')].get('ru',(None,a.get('name','')))[1]
 result[f[8]].append({'geonames_id':int(f[0]),'name':name,'labels':labels,'region':region,'admin_code':f[10],'latitude':float(f[4]),'longitude':float(f[5]),'population':int(f[14]),'feature_code':f[7],'aliases':sorted(aliases[f[0]]|{f[1],f[2]})})
for c,items in result.items():
 duplicates=collections.Counter(x['name'].casefold() for x in items)
 for x in items:
  x['display_name']=x['name']
  if duplicates[x['name'].casefold()]>1:x['display_name']=(x['name']+' — '+(x['region'] or x['admin_code']))[:100]
 # Keep distinct settlements even where names and regions coincide.
 counts=collections.Counter(x['display_name'].casefold() for x in items)
 for x in items:
  if counts[x['display_name'].casefold()]>1:x['display_name']=x['display_name'][:83]+' · '+str(x['geonames_id'])
 items.sort(key=lambda x:(-x['population'],x['display_name']))
 (out/('cities-'+c+'.json')).write_text(json.dumps(items,ensure_ascii=False,separators=(',',':'))+'\n')
 print(c,len(items),'Cyrillic names',sum(bool(re.search('[А-Яа-я]',x['name'])) for x in items))
manifest={'source':'GeoNames','license':'CC BY 4.0','attribution':'GeoNames geographical database, https://www.geonames.org/','downloaded_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'corrections':[{'geonames_id':1539946,'name':'Алатау','source':'https://www.akorda.kz/ru/ob-izmeneniyah-v-administrativno-territorialnom-ustroystve-almatinskoy-oblasti-902819'},{'geonames_id':1528249,'name':'Манас','source':'https://24.kg/vlast/343904_sadyir_japarov_podpisal_zakon_opereimenovanii_djalal-abada_vgorod_manas/'}],'scope':'Cities and populated settlements from cities500 (population over 500 or administrative seats); not an official national city-status register. Excludes neighbourhoods, abandoned and historical places.','urls':['https://download.geonames.org/export/dump/KZ.zip','https://download.geonames.org/export/dump/cities500.zip','https://download.geonames.org/export/dump/admin1CodesASCII.txt']+['https://download.geonames.org/export/dump/alternatenames/'+c+'.zip' for c in country_codes],'counts':{c:len(v) for c,v in result.items()},'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in root.iterdir() if p.is_file()}}
(out/'cities-source.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
