// Public app metadata, never a server credential.
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
export const firebaseClientPlatforms:Record<string,Record<string,string>>=JSON.parse(readFileSync(join(__dirname,'../firebase-client-config.json'),'utf8'));
export const firebaseDefaultVapidKey=readFileSync(join(__dirname,'../firebase-vapid-public.txt'),'utf8').trim();
