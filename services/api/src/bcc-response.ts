const allowed=new Set(['ORDER','TERMINAL','TRTYPE','TRAN_TRTYPE','AMOUNT','TRAN_AMOUNT','CURRENCY','ACTION','RC','RRN','INT_REF','AUTH_CODE','TIMESTAMP','NONCE']);
const decode=(v:string)=>v.replace(/&#x([a-f0-9]+);/gi,(_,x)=>String.fromCodePoint(parseInt(x,16))).replace(/&#(\d+);/g,(_,x)=>String.fromCodePoint(Number(x))).replace(/&quot;/g,'"').replace(/&#39;|&apos;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&');
export function parseBccResponse(raw:string){
 const result:Record<string,string>={};
 const add=(key:string,value:any)=>{key=key.toUpperCase();if(!allowed.has(key))return;if(typeof value!=='string'&&typeof value!=='number')throw Error('Invalid BCC field');value=String(value);if(Object.hasOwn(result,key)&&result[key]!==value)throw Error('Conflicting BCC fields');result[key]=value;};
 const text=raw.trim();
 if(text.startsWith('{')){const json=JSON.parse(text);if(!json||Array.isArray(json))throw Error('Invalid BCC object');for(const [k,v]of Object.entries(json))add(k,v);return result;}
 for(const tag of text.match(/<input\b[^>]*>/gi)??[]){const attrs:Record<string,string>={};for(const m of tag.matchAll(/([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g))attrs[m[1].toLowerCase()]=decode(m[2]??m[3]??m[4]);if(attrs.name&&attrs.value!==undefined)add(attrs.name,attrs.value);}
 if(Object.keys(result).length)return result;
 for(const m of text.matchAll(/<([A-Z_]+)\b[^>]*>([^<]*)<\/\1>/gi))add(m[1],decode(m[2]));
 if(!Object.keys(result).length&&/(?:^|&)(?:ACTION|RC|ORDER)=/i.test(text))for(const [k,v]of new URLSearchParams(text))add(k,v);
 return result;
}
