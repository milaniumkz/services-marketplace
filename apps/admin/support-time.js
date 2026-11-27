export const supportTimeZone='Asia/Almaty';
export const supportTimeZoneLabel='Астана · UTC+5';
export function supportDate(value){const d=new Date(value);return Number.isFinite(d.getTime())?new Intl.DateTimeFormat('ru-RU',{timeZone:supportTimeZone,day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit',hour12:false}).format(d):'Время не указано';}
export function supportClock(value=new Date()){return new Intl.DateTimeFormat('ru-RU',{timeZone:supportTimeZone,hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}).format(value);}
