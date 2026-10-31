"""Reproducible inventory; links are review aids, never proof of acceptance."""
import hashlib,json,re,importlib.util
from pathlib import Path
root=Path(__file__).resolve().parents[1]
module_spec=importlib.util.spec_from_file_location('design_audit',root/'scripts/audit-design.py');design_audit=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(design_audit)
spec=root/'docs/spec/services-marketplace-spec-v1.ru.md'
lines=spec.read_text().splitlines()
blocks={1:[12,18],2:[13,18],3:[12,13,15,18],4:[11,15,16],5:[8,9,17],6:[11],7:[11,14],8:[11,15],9:[5,13,16],10:[8,9,10,15],11:[12,13,15],12:[5,12,13],13:[12],14:[12,13],15:[12,13],16:[14],17:[14,15,16],18:[12,13,14],19:[14,16],20:[12,13],21:[14,16],22:[14,16],23:[5,12,13],24:[6,7,13],25:[13],26:[13],27:[16],28:[6,16],29:[18],30:[11,12,13,14,15,16,17],31:[5,13],32:[5,13],33:[6,16],34:[2,3,4],35:[16],36:[5,13],37:[5,16],38:[16],39:[5,13],40:[13],41:[16],42:[8,9,10,16],43:[14],44:[5,12,13],45:[5,6,7,13]}
# Section-level links are explicit navigation candidates, requiring review within each block.
topics={1:['orders','search','customer'],2:['contractor','offer'],3:['entitlement','customer-free'],4:['kyrgyzstan','country'],5:['country','retention'],6:['auth','trust'],7:['trust','session'],8:['session'],9:['verification','document-policy'],10:['privacy','retention'],11:['account','contractor'],12:['category'],13:['order'],14:['order','workflow'],15:['offer'],16:['conversation','realtime','chat'],17:['push'],18:['completion','workflow'],19:['case'],20:['review'],21:['case','trust'],22:['case'],23:['customer','entitlement'],24:['billing','commerce','refund'],25:['reward'],26:['reward'],27:['admin'],28:['audit','billing'],29:['http','openapi'],30:['visual','browser'],31:['price','customer'],32:['settings','monetization'],33:['admin-report'],34:['banner'],35:['push'],36:['promotion','price'],37:['dictionary','trust'],38:['branding'],39:['referral'],40:['portfolio'],41:['staff-account','account-overview'],42:['account-restriction','retention'],43:['support','recovery'],44:['ranking','top-listings'],45:['boost','placement']}
tests=list((root/'services/api/test').glob('*.test.cjs'))+list((root/'apps/mobile/test').glob('*.dart'))+[root/'scripts/verify-admin-browser.cjs']
requirements=[]
for number,line in enumerate(lines,1):
 m=re.match(r'^\*\*(FR-(\d+)([A-Z]?))\s+',line)
 if not m:continue
 n=int(m[2]);requirements.append({'id':m[1],'source_line':number,'source_text':line,'blocks':[12,13] if m[3]=='A' else blocks[n],'review_status':'pending','test_candidates':[str(p.relative_to(root)) for p in tests if any(t in p.name for t in topics[n])],'verified_api_operations':[],'verified_controls':[],'evidence':[]})
for number,line in enumerate(lines,1):
 m=re.match(r'^\| (NFR-\d{2}) \|',line)
 if m:requirements.append({'id':m[1],'source_line':number,'source_text':line,'blocks':[19,20],'review_status':'pending','test_candidates':[],'verified_api_operations':[],'verified_controls':[],'evidence':[]})
acceptance=[{'id':m[1],'source_line':i,'source_text':line,'review_status':'pending'} for i,line in enumerate(lines,1) if (m:=re.match(r'^- (T\d{2})\s',line))]
audit=json.loads((root/'docs/design/screen-audit.json').read_text());visual=json.loads((root/'docs/design/review/visual-audit.json').read_text());lookup={(x['surface'],x['id'],x['route']):x for x in visual['frames']}
frames=[]
for f in audit['frames']:
 v=lookup.get((f['surface'],f['id'],f['design_route']));assert v, f['id']
 controls=[]
 for i,c in enumerate(f['controls'],1):controls.append({'id':f['id']+':'+str(i),'design':c,'functional_review':'pending','api_operations':[],'evidence':[]})
 frames.append({'id':f['id'],'surface':f['surface'],'route':f['design_route'],'blocks':([11,12,13,14,15] if f['surface']=='mobile' else [16] if f['surface']=='admin' else [17]),'scope_review':'pending','visual_acceptance':v['visual_acceptance'],'controls':controls})
for num,title,kind in [(6,'Оплата','payments'),(7,'Возврат','refunds'),(8,'Оферта','public_offer'),(9,'Контакты','contacts')]:
 assert (root/f'apps/web/W0{num}.html').is_file()
 parser=design_audit.Controls();parser.feed((root/f'apps/web/W0{num}.html').read_text());new_controls=[]
 for i,c in enumerate(parser.controls,1):
  c.pop('depth',None);c['label']=' '.join(c['label'].split());new_controls.append({'id':f'W0{num}:'+str(i),'design':c,'functional_review':'pending','api_operations':[],'evidence':[]})
 frames.append({'id':f'W0{num}','surface':'public','route':f'W0{num}.html','blocks':[17],'origin':'owner_request_2026-10-16','reference':None,'document_type':kind,'title':title,'scope_review':'pending','visual_acceptance':'pending','controls':new_controls,'control_inventory_status':'inventoried_review_pending'})
overrides=[{'id':'OWNER-CUSTOMER-FREE','requirements':['FR-003','FR-023','FR-031','FR-032','FR-036'],'rule':'Заказчик без подписки; подписка только исполнителю. Продвижение собственного объекта — отдельный продукт.'},{'id':'OWNER-KG','requirements':['FR-004','FR-005'],'rule':'Сербия заменена Кыргызстаном; KZ/KG/RU/BY включены.'},{'id':'OWNER-DEFAULTS','requirements':[],'rule':'Предложенные параметры разрешены как исходные настройки; это не подтверждение внешних договоров или финальных обязательных сроков.'},{'id':'OWNER-PROVIDERS','requirements':['FR-024','FR-025','FR-026','FR-033','FR-035'],'rule':'Внешние интеграции отложены; фиктивный успех запрещён. Apple/Google billing пока не нужны.'},{'id':'OWNER-LEGAL','requirements':['FR-005'],'rule':'Коммерческие документы опубликованы в репозитории; реквизиты заполняет владелец через админку.'}]
result={'source':'docs/spec/services-marketplace-spec-v1.ru.md','source_sha256':hashlib.sha256(spec.read_bytes()).hexdigest(),'rule':'Inventory only. Candidate tests and block associations are not verified coverage. Empty evidence means pending. Original controls and owner changes must be reviewed together.','api_catalog':'docs/api/openapi.json','requirements':requirements,'acceptance_scenarios':acceptance,'owner_overrides':overrides,'frames':frames}
out=root/'docs/design/review/completion-registry.json'
if out.exists():
 previous=json.loads(out.read_text())
 if 'supplementary_screens' in previous:result['supplementary_screens']=previous['supplementary_screens']
 for collection in ['requirements','acceptance_scenarios']:
  old={x['id']:x for x in previous.get(collection,[])}
  for item in result[collection]:
   prior=old.get(item['id'])
   if prior and prior['source_text']==item['source_text']:
    for field in ['review_status','verified_api_operations','verified_controls','evidence']:
     if field in prior:item[field]=prior[field]
 old={(x['surface'],x['id'],x['route']):x for x in previous.get('frames',[])}
 for item in result['frames']:
  prior=old.get((item['surface'],item['id'],item['route']))
  if not prior:continue
  item['scope_review']=prior.get('scope_review','pending')
  controls={x['id']:x for x in prior.get('controls',[])}
  for control in item['controls']:
   saved=controls.get(control['id'])
   if saved and saved['design']==control['design']:
    for field in ['functional_review','api_operations','evidence']:control[field]=saved.get(field,control[field])
out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
summary={'requirements':len(requirements),'functional':sum(x['id'].startswith('FR-') for x in requirements),'nonfunctional':sum(x['id'].startswith('NFR-') for x in requirements),'acceptance_scenarios':len(acceptance),'frames':len(frames),'original_controls':sum(len(x['controls']) for x in frames if 'origin' not in x),'new_page_controls':sum(len(x['controls']) for x in frames if 'origin' in x)}
assert summary['functional']==46 and summary['nonfunctional']==12 and summary['acceptance_scenarios']==33,summary
print(json.dumps(summary,ensure_ascii=False))
