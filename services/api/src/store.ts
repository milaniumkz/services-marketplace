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
    if(process.env.NODE_ENV==='production'&&!['KZ','RS','RU','BY'].includes(process.env.JOBA_REGION??''))throw Error('Production requires an explicit JOBA_REGION');
    if(process.env.DATABASE_URL&&path!=='memory://')this.db=new ServerPostgres(process.env.DATABASE_URL);
    else {if(path!=='memory://')mkdirSync(path,{recursive:true});this.db=new PGlite(path);}
  }
  async initialize() {
    await this.db.exec(readFileSync(resolve(__dirname, "../migrations/0002_runtime.up.sql"), "utf8"));
    await this.db.exec(readFileSync(resolve(__dirname, "../migrations/0003_rate_limits.up.sql"), "utf8"));
  }
  async all(kind: string, country?: string): Promise<RecordData[]> {
    const r = await this.db.query<{data: RecordData}>('SELECT data FROM records WHERE kind=$1 AND ($2::text IS NULL OR country=$2) ORDER BY id', [kind, country ?? null]);
    return r.rows.map(x => x.data);
  }
  async select(kind:string,country:string,options:{owner?:string;participant?:string;executor?:string;statuses?:string[];after?:string;limit?:number;city?:string;category?:string;search?:string;sourceId?:string;publicActor?:string}={}) {
    const args:any[]=[kind,country],where=['kind=$1','country=$2'];
    const bind=(value:any)=>{args.push(value);return '$'+args.length;};
    if(options.owner)where.push('owner='+bind(options.owner));
    if(options.executor)where.push("data->>'executor_id'="+bind(options.executor));
    if(options.participant){const participant=bind(options.participant);where.push(`(owner=${participant} OR data->>'executor_id'=${participant})`);}
    if(options.statuses)where.push("data->>'status'=ANY("+bind(options.statuses)+'::text[])');
    if(options.after)where.push('id>'+bind(options.after)+'::uuid');
    if(options.sourceId)where.push("data->>'source_id'="+bind(options.sourceId));
    if(options.city)where.push("data->>'city'="+bind(options.city));
    if(options.category){const category=bind(options.category);where.push(`(data->>'category_id'=${category} OR COALESCE(data->'category_ids','[]'::jsonb) ? ${category})`);}
    if(options.publicActor){
      const viewer=bind(options.publicActor);
      where.push("COALESCE(data->>'moderation_status','') NOT IN ('quarantined','hidden','rejected')");
      where.push(`NOT EXISTS(SELECT 1 FROM records block WHERE block.kind='pair_block' AND block.country=r.country AND block.data->>'status'='active' AND ((block.owner=${viewer} AND block.data->>'target_id'=r.owner) OR (block.owner=r.owner AND block.data->>'target_id'=${viewer})))`);
      where.push(`EXISTS(SELECT 1 FROM records account WHERE account.kind='user' AND account.id::text=r.owner AND account.country=r.country AND account.data->>'status'='active' ${kind==='contractor'?"AND account.data->>'verification'='passed'":''})`);
      if(kind==='order')where.push("(data->>'expires_at')::timestamptz > CURRENT_TIMESTAMP");
    }
    if(options.search){const parameter=bind('%'+options.search+'%');where.push(`(data->>'title' ILIKE ${parameter} OR data->>'display_name' ILIKE ${parameter} OR data->>'subject' ILIKE ${parameter})`);}
    const limit=options.limit??101;const r=await this.db.query<{data:RecordData}>('SELECT data FROM records r WHERE '+where.join(' AND ')+' ORDER BY id LIMIT '+bind(limit),args);return r.rows.map(r=>r.data);
  }
  async get(id: string): Promise<RecordData | undefined> {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) return undefined;
    return (await this.db.query<{data: RecordData}>('SELECT data FROM records WHERE id=$1 FOR UPDATE', [id])).rows[0]?.data;
  }
  async put(data: RecordData) {
    if(this.contentHook)await this.contentHook(data);
    await this.db.query('INSERT INTO records(id,kind,owner,country,version,data) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(id) DO UPDATE SET version=excluded.version,data=excluded.data', [data.id,data.kind,data.owner,data.country,data.version,JSON.stringify(data)]);
    return data;
  }
  async close() { await this.db.close(); }
}
