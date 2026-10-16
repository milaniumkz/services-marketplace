export const countryCodes=['KZ','KG','RU','BY'] as const;
/** JOBA_REGION identifies the host; explicitly enabled countries may share it. */
export function enabledCountries():string[]{
 const configured=process.env.JOBA_ENABLED_COUNTRIES;
 const selected=configured===undefined?(process.env.JOBA_REGION?[process.env.JOBA_REGION]:[...countryCodes]):configured.split(',').map(v=>v.trim());
 if(!selected.length||selected.some(v=>!countryCodes.includes(v as any))||new Set(selected).size!==selected.length)throw Error('JOBA_ENABLED_COUNTRIES must contain distinct supported country codes');
 return selected;
}
export const countryEnabled=(country:string)=>enabledCountries().includes(country);
