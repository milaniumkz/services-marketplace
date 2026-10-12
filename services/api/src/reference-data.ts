import { createHash } from 'node:crypto';
import { Store } from './store';
const categories=[
  {ru:'Ремонт',kk:'Жөндеу',be:'Рамонт',sr:'Поправке'},
  {ru:'Уборка',kk:'Тазалау',be:'Прыборка',sr:'Чишћење'},
  {ru:'Перевозки',kk:'Тасымалдау',be:'Перавозкі',sr:'Превоз'},
  {ru:'Красота',kk:'Сұлулық',be:'Прыгажосць',sr:'Лепота'},
  {ru:'Обучение',kk:'Оқыту',be:'Навучанне',sr:'Образовање'}
];
export function referenceId(value:string) {const h=createHash('sha256').update(value).digest('hex');return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-8${h.slice(17,20)}-${h.slice(20,32)}`;}
export async function seedReferenceData(store:Store) {
  const existing=await store.all('category');
  for(const country of ['KZ','RS','RU','BY'])for(let i=0;i<categories.length;i++) {
    const id=referenceId(`joba:category:${country}:${i}`);if(existing.some(x=>x.id===id))continue;
    await store.put({id,kind:'category',country,owner:'system',version:1,created_at:new Date().toISOString(),status:'effective',legacy_id:String(i+1),title:categories[i].ru,payload:{labels:categories[i],source:'reference_catalog',category_id:id}});
  }
}
