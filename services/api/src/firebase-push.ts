import {existsSync, readFileSync} from 'node:fs';
import {firebaseClientPlatforms, firebaseDefaultVapidKey} from './firebase-client-config';
import {applicationDefault, getApps, initializeApp} from 'firebase-admin/app';
import {getMessaging, Message} from 'firebase-admin/messaging';
import {PushProvider} from './providers';

/** Only public, explicitly whitelisted Firebase options may leave the server. */
export function firebasePublicConfig(env:NodeJS.ProcessEnv=process.env) {
  const configFile=env.JOBA_FIREBASE_CONFIG_FILE;
  const saved=configFile&&existsSync(configFile)?JSON.parse(readFileSync(configFile,'utf8')):{};
  const platforms:Record<string,Record<string,string>>={};
  for(const platform of ['web','android','ios']) {
    const raw=env['JOBA_FIREBASE_'+platform.toUpperCase()+'_CONFIG'];
    const parsed=raw?JSON.parse(raw):saved.platforms?.[platform]??(firebaseClientPlatforms as Record<string,Record<string,string>>)[platform];
    if(!parsed)continue;
    const options:Record<string,string>={};
    for(const key of ['apiKey','appId','messagingSenderId','projectId','authDomain','storageBucket','iosBundleId'])if(typeof parsed[key]==='string')options[key]=parsed[key];
    if(!options.apiKey||!options.appId||!options.messagingSenderId||options.projectId!==(env.JOBA_FIREBASE_PROJECT_ID??'joba-832c7'))throw Error('Invalid Firebase public configuration: '+platform);
    platforms[platform]=options;
  }
  return {enabled:env.JOBA_FIREBASE_ENABLED==='1',project_id:env.JOBA_FIREBASE_PROJECT_ID??'joba-832c7',platforms,vapid_key:env.JOBA_FIREBASE_VAPID_KEY||saved.vapid_key||firebaseDefaultVapidKey};
}

export function firebaseMessage(token:string,event:Parameters<PushProvider['send']>[1]):Message {
  // No names, chat text, identity documents, tokens or arbitrary URLs on a lock screen.
  return {token,notification:{title:event.title,body:event.body},data:{event_id:event.event_id,route:'notifications'},
    android:{priority:'high',notification:{channelId:'joba_events',tag:event.event_id}},
    apns:{payload:{aps:{sound:'default','thread-id':'joba_events'}}},
    webpush:{fcmOptions:{link:'https://joba.com.kz/app/?joba_push=notifications'},notification:{tag:event.event_id,icon:'/icons/joba-192.png'}}};
}
export class FirebasePushProvider implements PushProvider {
  private readonly app;
  constructor(projectId:string) {
    this.app=getApps().find(a=>a.name==='joba-push')??initializeApp({projectId,credential:applicationDefault()},'joba-push');
  }
  async send(token:string,event:Parameters<PushProvider['send']>[1]) {
    try {return {provider_message_id:await getMessaging(this.app).send(firebaseMessage(token,event))};}
    catch(e) {
      if(['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes((e as any)?.code))throw new InvalidPushToken();
      throw Error('Firebase delivery unavailable'); // Do not log credentials, token or provider payload.
    }
  }
}
export class InvalidPushToken extends Error {}
