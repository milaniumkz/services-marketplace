import {Store} from './store';
export const defaultCommunicationLanguages=[{code:'ru',title:'Русский'},{code:'ky',title:'Киргизский'},{code:'kk',title:'Казахский'},{code:'be',title:'Белорусский'},{code:'en',title:'Английский'}];
export async function communicationLanguages(store:Store,country:string){const record=(await store.all('communication_language_catalog',country))[0];const items:Array<{code:string;title:string}>=record?.items??defaultCommunicationLanguages;return {version:record?.version??0,items};}
