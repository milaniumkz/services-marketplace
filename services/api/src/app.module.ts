import { Controller, Get, Module } from '@nestjs/common';
@Controller()
export class HealthController {
  @Get('health') health() { return { status: 'ok', mode: 'demo' }; }
}
@Module({ controllers: [HealthController] })
export class AppModule {}
