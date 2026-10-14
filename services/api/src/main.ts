import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule, getMarketplace } from './app.module';
import { startRealtime } from './realtime';
async function bootstrap() {
  const port = Number(process.env.API_PORT ?? 3000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid API_PORT');
  const app = await NestFactory.create(AppModule, { rawBody: true });
  const marketplace=await getMarketplace();
  await app.listen(port, process.env.API_HOST ?? '127.0.0.1');
  const stopRealtime=startRealtime(app.getHttpServer(),marketplace);
  const worker=setInterval(()=>marketplace.maintenance().catch(()=>console.error('Maintenance failed; records remain pending for retry')),60000);
  const fileWorker=setInterval(()=>marketplace.processPendingUploads().catch(()=>console.error('File processing failed; uploads remain private for retry')),2000);
  const pushWorker=setInterval(()=>marketplace.deliverOutbox().catch(()=>console.error('Outbox delivery failed; pending events will retry')),3000);
  const shutdown=async()=>{clearInterval(worker);clearInterval(pushWorker);clearInterval(fileWorker);stopRealtime();await app.close();await marketplace.store.close();};
  process.once('SIGTERM',shutdown);process.once('SIGINT',shutdown);
}
void bootstrap();
