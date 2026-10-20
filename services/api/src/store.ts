import {enabledCountries} from './country-access';
import { PGlite } from '@electric-sql/pglite';
import { mkdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { Client } from 'pg';

interface Database {
  exec(sql:string):Promise<unknown>;
  query<T extends Record<string,any> = any>(sql:string,params?:any[]):Promise<{rows:T[]}>;
  close():Promise<void>;
}
class ServerPostgres implements Database {
  private client:Client;
  private connected:Promise<void>;
  constructor(url:string){this.client=new Client({connectionString:url});this.connected=this.client.connect().then(()=>{});}
  async exec(sql:string){await this.connected;await this.client.query(sql);}
  async query<T extends Record<string,any>>(sql:string,params?:any[]){await this.connected;return this.client.query<T>(sql,params);}
  async close(){await this.connected;await this.client.end();}
}

export type RecordData = { id: string; kind: string; owner: string; country: string; version: number; created_at: string; [key: string]: any };
export class Store {
  readonly db: Database;
  contentHook?: (data:RecordData)=>Promise<void>;
  constructor(path = process.env.JOBA_DATA_DIR ?? resolve(__dirname, '../../../.local/joba')) {
    if(process.env.NODE_ENV==='production'&&!process.env.DATABASE_URL)throw Error('Production requires a regional PostgreSQL DATABASE_URL');
    if(process.env.NODE_ENV==='production'&&!['KZ','KG','RU','BY'].includes(process.env.JOBA_REGION??''))throw Error('Production requires an explicit JOBA_REGION');
    if(process.env.DATABASE_URL&&path!=='memory://')this.db=new ServerPostgres(process.env.DATABASE_URL);
    else {if(path!=='memory://')mkdirSync(path,{recursive:true});this.db=new PGlite(path);}
  }
  async initialize() {
    enabledCountries();
    await this.db.exec(readFileSync(resolve(__dirname, "../migrations/0002_runtime.up.sql"), "utf8"));
    await this.db.exec(readFileSync(resolve(__dirname, "../migrations/0003_rate_limits.up.sql"), "utf8"));
    await this.db.exec(readFileSync(resolve(__dirname, "../migrations/0004_account_views.up.sql"), "utf8"));
    await this.db.exec(readFileSync(resolve(__dirname, "../migrations/0005_invite_queries.up.sql"), "utf8"));
    await this.db.exec(readFileSync(resolve(__dirname, "../migrations/0006_ranking_votes.up.sql"), "utf8"));
    await this.db.exec(readFileSync(resolve(__dirname, "../migrations/0007_product_queries.up.sql"), "utf8"));
    await this.db.exec(readFileSync(resolve(__dirname, "../migrations/0008_push_campaigns.up.sql"), "utf8"));
    await this.db.exec(readFileSync(resolve(__dirname, "../migrations/0009_conversation_inbox.up.sql"), "utf8"));
    await this.db.exec(readFileSync(resolve(__dirname, "../migrations/0010_refund_balances.up.sql"), "utf8"));
  }
  async all(kind: string, country?: string): Promise<RecordData[]> {
    const r = await this.db.query<{data: RecordData}>('SELECT data FROM records WHERE kind=$1 AND ($2::text IS NULL OR country=$2) ORDER BY id', [kind, country ?? null]);
    return r.rows.map(x => x.data);
  }
  async select(kind:string,country:string,options:{member?:string;subjectUser?:string;owner?:string;recipient?:string;boostBucket?:string;inviteState?:string;caseActor?:string;caseBucket?:string;participant?:string;executor?:string;statuses?:string[];after?:string;limit?:number;city?:string;category?:string;search?:string;sourceId?:string;near?:{latitude:number;longitude:number;radius:number};publicActor?:string;endUserOnly?:boolean;workMode?:string;priceMin?:number;priceMax?:number;ratingMin?:number;ranking?:{windowDays:number;dislikeWeight:number;ageDays:number;sort:'popular'|'new'}}={}) {
    const args:any[]=[kind,country],where=['kind=$1','country=$2'];
    const bind=(value:any)=>{args.push(value);return '$'+args.length;};
    if(options.owner)where.push('owner='+bind(options.owner));
    if(options.member)where.push("COALESCE(data->'members','[]'::jsonb) ? "+bind(options.member));
    if(options.endUserOnly)where.push("COALESCE(jsonb_array_length(data->'staff_permissions'),0)=0");
    if(options.recipient)where.push("data->>'recipient_id'="+bind(options.recipient));
    if(options.subjectUser)where.push(`data->>'subject_user_id'=${bind(options.subjectUser)}`);
    if(options.caseActor){const actor=bind(options.caseActor);where.push(`(owner=${actor} OR data->>'subject_user_id'=${actor} AND COALESCE(data->>'reporter_private','false')<>'true')`);}
    if(options.caseBucket)where.push("data->>'status' "+(options.caseBucket==='resolved'?'IN':'NOT IN')+" ('resolved','closed','dismissed')");

    if(options.boostBucket){
      const live="(data->>'status' IN('reserved','payment_pending','scheduled','active','paused','resolution_required') AND (data->>'status'='resolution_required' OR COALESCE(CASE WHEN data->>'status' IN('reserved','payment_pending') THEN data->>'reservation_expires_at' END,data->>'ends_at')::timestamptz>CURRENT_TIMESTAMP))";
      where.push(options.boostBucket==='active'?live:'NOT '+live);
    }
    if(options.inviteState){
      if(options.inviteState==='pending')where.push("data->>'status'='pending' AND (data->>'expires_at' IS NULL OR (data->>'expires_at')::timestamptz > CURRENT_TIMESTAMP)");
      else if(options.inviteState==='expired')where.push("(data->>'status'='expired' OR data->>'status'='pending' AND (data->>'expires_at')::timestamptz <= CURRENT_TIMESTAMP)");
      else where.push("data->>'status'="+bind(options.inviteState));
    }

    if(options.executor)where.push("data->>'executor_id'="+bind(options.executor));
    if(options.participant){const participant=bind(options.participant);where.push(`(owner=${participant} OR data->>'executor_id'=${participant})`);}
    if(options.statuses)where.push("data->>'status'=ANY("+bind(options.statuses)+'::text[])');
    if(options.after)where.push('id>'+bind(options.after)+'::uuid');
    if(options.sourceId)where.push("data->>'source_id'="+bind(options.sourceId));
    if(options.city){const city=bind(options.city);where.push(kind==='contractor'?`(data->>'city'=${city} OR COALESCE(data->'service_cities','[]'::jsonb) ? ${city})`:"data->>'city'="+city);}
    if(kind==='contractor'){
      if(options.workMode)where.push("COALESCE(data->'work_modes','[\"onsite\"]'::jsonb) ? "+bind(options.workMode));
      if(options.priceMin!==undefined)where.push("(data->'price'->>'amount_min')::numeric >= "+bind(options.priceMin));
      if(options.priceMax!==undefined)where.push("(data->'price'->>'amount_min')::numeric <= "+bind(options.priceMax));
      if(options.ratingMin!==undefined)where.push(`COALESCE((SELECT avg((review.data->>'rating')::numeric) FROM records review WHERE review.kind='review' AND review.country=r.country AND review.data->>'target_id'=r.owner AND review.data->>'status'='published' AND COALESCE(review.data->>'moderation_status','') NOT IN ('quarantined','hidden','rejected')),0) >= ${bind(options.ratingMin)}`);
    }
    if(options.category){const category=bind(options.category);where.push(`(data->>'category_id'=${category} OR COALESCE(data->'category_ids','[]'::jsonb) ? ${category})`);}
    if(options.near){
      const lat=bind(options.near.latitude),lon=bind(options.near.longitude),radius=bind(options.near.radius);
      where.push(`data->'public_location' IS NOT NULL AND 6371*ACOS(LEAST(1,GREATEST(-1,SIN(RADIANS(${lat}::numeric))*SIN(RADIANS((data->'public_location'->>'latitude')::numeric))+COS(RADIANS(${lat}::numeric))*COS(RADIANS((data->'public_location'->>'latitude')::numeric))*COS(RADIANS((data->'public_location'->>'longitude')::numeric-${lon}::numeric)))))<=${radius}::numeric`);
    }
    if(options.publicActor){
      const viewer=bind(options.publicActor);
      where.push("COALESCE(data->>'moderation_status','') NOT IN ('quarantined','hidden','rejected')");
      where.push(`NOT EXISTS(SELECT 1 FROM records block WHERE block.kind='pair_block' AND block.country=r.country AND block.data->>'status'='active' AND ((block.owner=${viewer} AND block.data->>'target_id'=r.owner) OR (block.owner=r.owner AND block.data->>'target_id'=${viewer})))`);
      where.push(`EXISTS(SELECT 1 FROM records account WHERE account.kind='user' AND account.id::text=r.owner AND account.country=r.country AND account.data->>'status'='active' ${kind==='contractor'?"AND account.data->>'verification'='passed'":''})`);
      if(kind==='order')where.push("(data->>'expires_at')::timestamptz > CURRENT_TIMESTAMP");
    }
    if(options.search){const parameter=bind('%'+options.search+'%');
      if(kind==='conversation'&&options.member){const actor=bind(options.member);where.push(`(EXISTS(SELECT 1 FROM records linked WHERE linked.country=r.country AND (linked.kind='order' AND linked.id::text=r.data->>'order_id' AND linked.data->>'title' ILIKE ${parameter} OR linked.kind='user' AND COALESCE(r.data->'members','[]'::jsonb) ? linked.id::text AND linked.id::text<>${actor} AND linked.data->>'display_name' ILIKE ${parameter})))`);}
      else where.push(`(id::text ILIKE ${parameter} OR owner ILIKE ${parameter} OR data->>'event' ILIKE ${parameter} OR data->>'title' ILIKE ${parameter} OR data->>'display_name' ILIKE ${parameter} OR data->>'subject' ILIKE ${parameter})`);
    }
    if(options.ranking){
      const ranking=options.ranking,cutoff=bind(new Date(Date.now()-ranking.windowDays*86400000).toISOString());
      const alpha=bind(ranking.dislikeWeight),decay=bind(ranking.ageDays),viewer=options.publicActor?bind(options.publicActor):undefined;
      const published="COALESCE(NULLIF(data->>'published_at','')::timestamptz,(data->>'created_at')::timestamptz)";
      const likes='COALESCE(vcounts.likes,0)',dislikes='COALESCE(vcounts.dislikes,0)';
      const score=`GREATEST(0,LN(1+${likes})-${alpha}::numeric*LN(1+${dislikes}))*EXP(-GREATEST(0,EXTRACT(EPOCH FROM(CURRENT_TIMESTAMP-${published}))/86400)/${decay}::numeric)`;
      const mine=viewer?`(SELECT value FROM votes mine WHERE mine.voter=${viewer}::uuid AND mine.target=r.id)`:'NULL';
      const premium=kind==='contractor'?"CASE WHEN EXISTS(SELECT 1 FROM records entitlement WHERE entitlement.kind='grant' AND entitlement.country=r.country AND entitlement.owner=r.owner AND (entitlement.data->>'valid_until')::timestamptz>CURRENT_TIMESTAMP AND COALESCE(entitlement.data->'capabilities','[]'::jsonb) ? 'top100') THEN 0 ELSE 1 END,":'';
      const order=ranking.sort==='new'?`${published} DESC,r.id ASC`:`${score} DESC,${likes} DESC,${published} DESC,r.id ASC`;
      const result=await this.db.query<{data:RecordData}>(`SELECT r.data || jsonb_build_object('likes',${likes},'dislikes',${dislikes},'organic_score',${score},'my_vote',${mine}) AS data FROM records r
        LEFT JOIN(SELECT v.target,count(*) FILTER(WHERE v.value=1) AS likes,count(*) FILTER(WHERE v.value=-1) AS dislikes FROM votes v JOIN records target ON target.id=v.target
          WHERE target.kind=$1 AND target.country=$2 AND v.created_at>${cutoff}::timestamptz AND v.voter::text<>target.owner GROUP BY v.target)vcounts ON vcounts.target=r.id
        WHERE ${where.join(' AND ')} ORDER BY ${premium}${order} LIMIT ${bind(options.limit??100)}`,args);
      return result.rows.map(row=>row.data);
    }
    const limit=options.limit??101;const r=await this.db.query<{data:RecordData}>('SELECT data FROM records r WHERE '+where.join(' AND ')+' ORDER BY id LIMIT '+bind(limit),args);return r.rows.map(r=>r.data);
  }
  async read(id:string):Promise<RecordData|undefined>{if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id))return undefined;return (await this.db.query<{data:RecordData}>('SELECT data FROM records WHERE id=$1',[id])).rows[0]?.data;}
  async get(id: string): Promise<RecordData | undefined> {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) return undefined;
    return (await this.db.query<{data: RecordData}>('SELECT data FROM records WHERE id=$1 FOR UPDATE', [id])).rows[0]?.data;
  }
  async put(data: RecordData,options:{skipContentCheck?:boolean}={}) {
    if(this.contentHook&&!options.skipContentCheck)await this.contentHook(data);
    await this.db.query('INSERT INTO records(id,kind,owner,country,version,data) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(id) DO UPDATE SET version=excluded.version,data=excluded.data', [data.id,data.kind,data.owner,data.country,data.version,JSON.stringify(data)]);
    return data;
  }
  async close() { await this.db.close(); }
}
