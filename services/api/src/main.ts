import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
async function bootstrap() {
  const port = Number(process.env.API_PORT ?? 3000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid API_PORT');
  const app = await NestFactory.create(AppModule);
  await app.listen(port, process.env.API_HOST ?? '127.0.0.1');
}
void bootstrap();
