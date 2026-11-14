const percent=value=>value==null?'Первый замер':new Intl.NumberFormat('ru',{maximumFractionDigits:1}).format(value)+'%';
const bytes=value=>new Intl.NumberFormat('ru',{maximumFractionDigits:2}).format(value/1073741824)+' ГиБ';
const rate=value=>value==null?'Первый замер':new Intl.NumberFormat('ru',{maximumFractionDigits:1}).format(value/1024)+' КиБ/с';
const clock=value=>new Intl.DateTimeFormat('ru',{dateStyle:'short',timeStyle:'medium',timeZone:'UTC'}).format(new Date(value))+' UTC';
function historyChart(rows){
 if(rows.length<2)return '<p>История появится после следующего замера.</p>';
 const points=key=>rows.map((row,i)=>row[key]==null?null:`${35+i*585/Math.max(1,rows.length-1)},${150-Math.max(0,Math.min(100,row[key]))*1.25}`).filter(Boolean).join(' ');
 return `<svg class="chart" viewBox="0 0 640 185" role="img" aria-label="История загрузки CPU, оперативной памяти и диска от 0 до 100 процентов"><g stroke="#EBEFF6"><path d="M34 25H620M34 87H620M34 150H620"/></g><text x="0" y="28">100%</text><text x="5" y="90">50%</text><text x="12" y="153">0%</text>${[['cpu_percent','#245BDB'],['memory_percent','#16805B'],['disk_percent','#A45E10']].map(([key,color])=>`<polyline fill="none" stroke="${color}" stroke-width="2" points="${points(key)}"/>`).join('')}</svg><p class="tiny">Синий — CPU · Зелёный — RAM · Коричневый — диск. Последние ${rows.length} замеров.</p>`;
}
export function mountServerMetrics(element,{api,esc,card,metric}){
 if(!element)return;
 let pending=false,timer;
 const render=data=>{
  if(!data.available)return card('Сервер',`<p role="status">Свежие показатели сервера пока недоступны. Ожидается работа сборщика.</p><button type="button" data-server-refresh>Обновить</button>`);
  const high=[data.cpu.usage_percent>=85?'CPU':null,data.memory.usage_percent>=85?'оперативная память':null,data.disk.usage_percent>=85?'диск':null].filter(Boolean);
  const uptime=Math.floor(data.uptime_seconds/86400)+' д. '+Math.floor(data.uptime_seconds%86400/3600)+' ч.';
  return card('Сервер — ресурсы и нагрузка',`<div class="row"><p class="tiny">Вся виртуальная машина JOBA · ${esc(clock(data.collected_at))} · обновление каждые 20 секунд</p><button type="button" data-server-refresh>Обновить</button></div><div class="grid cols4">${metric('CPU',percent(data.cpu.usage_percent),data.cpu.logical_cores+' логических ядер','Занято за интервал замера')}${metric('Оперативная память',percent(data.memory.usage_percent),bytes(data.memory.used_bytes)+' / '+bytes(data.memory.total_bytes),'Доступно: '+bytes(data.memory.available_bytes))}${metric('Диск /',percent(data.disk.usage_percent),bytes(data.disk.used_bytes)+' / '+bytes(data.disk.total_bytes),'Доступно: '+bytes(data.disk.available_bytes))}${metric('Время работы',uptime,'После запуска сервера','Перезапуск обнуляет показатель')}</div><div class="grid cols2 mt"><div><p><b>Средняя очередь CPU за 1 / 5 / 15 мин.</b><br>${data.cpu.load_average.map(n=>esc(new Intl.NumberFormat('ru',{maximumFractionDigits:2}).format(n))).join(' / ')}</p><p><b>Swap:</b> ${bytes(data.memory.swap_used_bytes)} / ${bytes(data.memory.swap_total_bytes)}</p></div><div><p><b>Сеть — приём:</b> ${rate(data.network.received_bytes_per_second)}</p><p><b>Сеть — передача:</b> ${rate(data.network.sent_bytes_per_second)}</p></div></div>${historyChart(data.history)}<p>${high.length?'Высокая текущая загрузка: '+high.join(', ')+'. Проверьте, сохраняется ли она на графике.':data.cpu.usage_percent==null?'Ожидается первый интервал измерения CPU.':'Текущая загрузка CPU, памяти и диска ниже 85%.'}</p><details><summary>Когда увеличивать сервер</summary><p>Если CPU долго загружен выше 85%, рассмотрите увеличение числа ядер. Если оперативная память стабильно заполнена выше 85% и используется swap, проверьте процессы и объём RAM. Если диск заполнен выше 85%, запланируйте расширение или очистку с учётом резервных копий. Изменение тарифа выполняется в панели хостинга.</p></details><div role="status" data-server-error></div>`);
 };
 const load=async()=>{
  if(pending||!element.isConnected)return;
  pending=true;clearTimeout(timer);
  try{const data=await api('/admin/server-metrics');if(element.isConnected){element.innerHTML=render(data);element.querySelector('[data-server-refresh]')?.addEventListener('click',load);}}
  catch(error){if(element.isConnected){let status=element.querySelector('[data-server-error]');if(!status){element.innerHTML=card('Сервер','<p role="status" data-server-error></p>');status=element.querySelector('[data-server-error]');}status.textContent='Не удалось обновить показатели: '+error.message;}}
  finally{pending=false;if(element.isConnected)timer=setTimeout(()=>document.hidden?schedule():load(),20000);}
 };
 const schedule=()=>{if(element.isConnected)timer=setTimeout(()=>document.hidden?schedule():load(),20000);};
 load();
}
