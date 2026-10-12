const { test } = require('node:test');
const assert = require('node:assert/strict');
const { NestFactory } = require('@nestjs/core');
const { AppModule } = require('../dist/app.module');
require('reflect-metadata');
test('HTTP health and unknown route', async () => {
 const app = await NestFactory.create(AppModule, { logger: false });
 try {
  await app.listen(0, '127.0.0.1');
  const base = await app.getUrl();
  const response = await fetch(base + '/health');
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok', mode: 'demo' });
  assert.equal((await fetch(base + '/orders')).status, 404);
 } finally { await app.close(); }
});
