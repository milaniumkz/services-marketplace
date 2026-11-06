/** The third, separate image is the selfie; document files are never used as avatars. */
export function verificationPages(policy:any,type:string):string[]{
 const supplied=Array.isArray(policy?.required_pages?.[type])?policy.required_pages[type].filter((x:any)=>typeof x==='string'&&!/селфи|selfie/i.test(x)):[];
 return [supplied[0]??'Лицевая сторона удостоверения',supplied[1]??'Обратная сторона удостоверения','Селфи'];
}
