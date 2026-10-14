import {pipeline} from 'node:stream/promises';
import { All, Controller, Get, Module, Req, Res, ServiceUnavailableException, MiddlewareConsumer, NestModule } from '@nestjs/common';
import express from 'express';
import { Marketplace } from './marketplace';
import { APP_FILTER } from '@nestjs/core';
import { HttpErrors } from './http-errors';
let marketplace: Marketplace | undefined;
let ready: Promise<void> | undefined;
export async function getMarketplace() {marketplace??=new Marketplace();ready??=marketplace.initialize();await ready;return marketplace;}
@Controller()
export class HealthController {
  @Get('health') async health() {
    try {
      const service=await getMarketplace();await service.store.db.query('SELECT 1');
      return {status:'ok',mode:process.env.NODE_ENV==='production'?'production':'development',database:'ready'};
    }catch{throw new ServiceUnavailableException('Database readiness check failed');}
  }
}
@Controller('api/v1')
export class MarketplaceController {
  @All('*path')
  async request(@Req() req: any, @Res() res: any) {
    const started=performance.now();req.joba_request_id=crypto.randomUUID();
    const marketplace=await getMarketplace();
    const path = req.path.replace(/^\/api\/v1/, '');
    const body=path.startsWith('/webhooks/')?{raw_body:req.rawBody,headers:req.headers}:Buffer.isBuffer(req.body)?req.body:{...req.body,...(req.headers['if-match']?{expected_version:Number(String(req.headers['if-match']).replaceAll('"',''))}:{})};
    const result = await marketplace.handle(req.method,path,body??{},req.headers.authorization,path.startsWith('/webhooks/')?undefined:req.headers['idempotency-key'],req.query,req.ip);
    res.setHeader('Cache-Control','no-store');
    res.setHeader('Server-Timing',`application;dur=${(performance.now()-started).toFixed(2)}`);
    if(path==='/me/monetization-config'&&req.method==='GET') {
      const etag=`"config-${result.version}"`;res.setHeader('ETag',etag);res.setHeader('X-Config-Expires-At',result.expires_at);
      if(req.headers['if-none-match']===etag){res.status(304).end();return;}
    }
    if(result?.download_stream){
      res.setHeader('Content-Type',result.mime);res.setHeader('Content-Disposition',`attachment; filename="${result.download_filename==='joba-icons.zip'?'joba-icons.zip':'joba-export.zip'}"`);res.setHeader('X-Content-Type-Options','nosniff');
      if(Number.isSafeInteger(result.download_size))res.setHeader('Content-Length',result.download_size);
      try{await pipeline(result.download_stream,res);}catch{if(res.headersSent)res.destroy();else{res.removeHeader('Content-Length');res.status(503).json({error:{code:'DOWNLOAD_UNAVAILABLE',message:'Архив недоступен. Повторите запрос.',details:{},retryable:true}});}}return;
    }
    if(result?.download_buffer){res.setHeader('Content-Type',result.mime);res.setHeader('Content-Disposition',`attachment; filename="document.${result.mime==='application/zip'?'zip':result.mime==='application/json'?'json':result.mime==='application/pdf'?'pdf':result.mime==='image/png'?'png':'jpg'}"`);res.setHeader('X-Content-Type-Options','nosniff');res.send(result.download_buffer);return;}
    res.json({data:result,meta:{request_id:req.joba_request_id,server_time:new Date().toISOString()}});
  }
}
@Module({ controllers: [HealthController, MarketplaceController], providers:[{provide:APP_FILTER,useClass:HttpErrors}] })
export class AppModule implements NestModule {
  configure(consumer:MiddlewareConsumer) {
    consumer.apply(express.raw({type:'application/octet-stream',limit:'10mb',verify:(request,_response,buffer)=>{(request as any).rawBody=buffer;}})).forRoutes(MarketplaceController);
  }
}
