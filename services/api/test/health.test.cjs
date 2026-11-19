const { test } = require('node:test');
const assert = require('node:assert/strict');
const { NestFactory } = require('@nestjs/core');
// This test owns an isolated embedded database, never the running app database.
process.env.JOBA_DATA_DIR='memory://';
const { AppModule, getMarketplace } = require('../dist/app.module');
require('reflect-metadata');
test('HTTP health and unknown route', async () => {
 const app = await NestFactory.create(AppModule, { logger: false });
 try {
  await app.listen(0, '127.0.0.1');
  const base = await app.getUrl();
  const response = await fetch(base + '/health');
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok', mode: 'development', database: 'ready' });
  assert.equal((await fetch(base + '/orders')).status, 404);
  await (await getMarketplace()).store.close();
  assert.equal((await fetch(base + '/health')).status,503);
 } finally { await app.close(); }
});
