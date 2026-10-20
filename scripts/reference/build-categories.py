from pathlib import Path
import json
source=Path(__file__).with_name('category-source.txt');items=[];seen=set()
for line in source.read_text().splitlines():
 if not line or line.startswith('#'):continue
 left,right=line.split('|');root,sub=map(str.strip,left.split('>'))
 for path in [[root],[root,sub]]+[[root,sub,name.strip()] for name in right.split(';')]:
  key=' / '.join(path)
  if key not in seen:items.append({'key':key,'name':path[-1],'parent':' / '.join(path[:-1]) or None,'depth':len(path)});seen.add(key)
Path('services/api/reference/categories.json').write_text(json.dumps(items,ensure_ascii=False,separators=(',',':'))+'\n')
print('Categories:',len(items))
