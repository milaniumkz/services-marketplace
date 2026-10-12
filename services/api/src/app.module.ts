import { All, Controller, Get, Module, Req, Res } from '@nestjs/common';
import { Marketplace } from './marketplace';
import { APP_FILTER } from '@nestjs/core';
import { HttpErrors } from './http-errors';
let marketplace: Marketplace | undefined;
let ready: Promise<void> | undefined;
export async function getMarketplace() {marketplace??=new Marketplace();ready??=marketplace.initialize();await ready;return marketplace;}
@Controller()
export class HealthController {
  @Get('health') health() { return { status: 'ok', mode: 'demo' }; }
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
    if(result?.download_buffer){res.setHeader('Content-Type',result.mime);res.setHeader('Content-Disposition',`attachment; filename="document.${result.mime==='application/json'?'json':result.mime==='application/pdf'?'pdf':'jpg'}"`);res.setHeader('X-Content-Type-Options','nosniff');res.send(result.download_buffer);return;}
    res.json({data:result,meta:{request_id:req.joba_request_id,server_time:new Date().toISOString()}});
  }
}
@Module({ controllers: [HealthController, MarketplaceController], providers:[{provide:APP_FILTER,useClass:HttpErrors}] })
export class AppModule {}
