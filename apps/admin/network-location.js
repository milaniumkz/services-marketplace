export function networkLocationLabel(value){
 if(value?.status!=='estimated')return value?.reason==='non_public_ip'?'Локальная или служебная сеть':'Местоположение не определено';
 const place=[value.city,value.region,value.country||value.country_code].filter(Boolean).join(', ');
 return (place||'Не определено')+' · примерно по IP'+(value.historical_lookup?' · по текущей базе для старого IP':'');
}
export const networkLocationNotice='Местоположение определяется приблизительно по IP, а не по GPS. VPN, прокси и мобильные сети могут показывать город оператора. Улица и дом по IP не определяются. Для старых записей оценка по нынешней базе не подтверждает фактическое место в прошлом. Источник: DB-IP City Lite (CC BY 4.0), база 2026-11. Журнал хранится в рамках действующих сроков хранения данных безопасности.';

export const networkLocationAttribution='<a href="https://db-ip.com/db/lite.php" target="_blank" rel="noopener noreferrer">DB-IP City Lite</a> · <a href="https://creativecommons.org/licenses/by/4.0/" target="_blank" rel="noopener noreferrer">CC BY 4.0</a>';

export const securityEventTime=value=>value&&Number.isFinite(Date.parse(value))?new Intl.DateTimeFormat('ru',{dateStyle:'short',timeStyle:'medium',timeZone:'UTC'}).format(new Date(value)):'Не записано';
