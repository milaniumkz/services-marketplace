export const okedNames:Record<string,string>={
 '63120':'Деятельность веб-порталов',
 '63115':'Предоставление в пользование программных продуктов, электронных информационных ресурсов, мобильных и иных приложений',
};
export const okedLabel=(code:string)=>code+(okedNames[code]?' — '+okedNames[code]:'');
export function operatorActivityText(p:any){
 if(!p.oked_primary)return '';
 return '\nОсновной ОКЭД (Республика Казахстан): '+okedLabel(p.oked_primary)+
  (p.oked_additional?.length?'\nДополнительные ОКЭД (Республика Казахстан): '+p.oked_additional.map(okedLabel).join('; '):'')+
  (p.oked_status==='updating'?'\nИзменение регистрационных сведений об ОКЭД оформляется.':'');
}
