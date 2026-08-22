const test = require('node:test');
const assert = require('node:assert/strict');
const { createApp } = require('../server');

test('setup, login and tenant-scoped incident flow', async t => {
  const diveraRequests = [];
  const server = createApp({
    dbPath: ':memory:',
    fetchImpl: async (url, options) => {
      diveraRequests.push({ url, options });
      return { ok: true, json: async () => ({ data: [] }) };
    }
  });
  await new Promise(resolve => server.listen(0, resolve));
  t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = (path, options) => fetch(base + path, options);

  let response = await call('/api/setup', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ organization: 'Testwehr', unit: 'Löschzug 1', name: 'Leitung', email: 'chef@example.de', password: 'sicheres-passwort' })
  });
  assert.equal(response.status, 201);

  response = await call('/api/login', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'chef@example.de', password: 'sicheres-passwort' })
  });
  assert.equal(response.status, 200);
  const cookie = response.headers.get('set-cookie').split(';')[0];
  const units = await (await call('/api/units', { headers: { cookie } })).json();
  assert.equal(units.length, 1);
  response = await call(`/api/units/${units[0].id}/divera`, {
    method: 'PUT', headers: { cookie, 'content-type': 'application/json' },
    body: JSON.stringify({ accessKey: 'read-only-key' })
  });
  assert.equal(response.status, 200);
  response = await call(`/api/units/${units[0].id}/divera`, { headers: { cookie } });
  assert.equal(response.status, 200);
  assert.equal(diveraRequests.length, 2);
  assert.ok(diveraRequests.every(request => request.options.method === 'GET'));
  response = await call('/api/users', {
    method: 'POST', headers: { cookie, 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'Gruppenführer', email: 'gf@example.de', password: 'anderes-passwort', role: 'fuehrungskraft', unitId: units[0].id })
  });
  assert.equal(response.status, 201);

  response = await call('/api/incidents', {
    method: 'POST', headers: { cookie, 'content-type': 'application/json' },
    body: JSON.stringify({ title: 'B3 Gebäude', startedAt: '2026-08-22T18:00', unitIds: [units[0].id] })
  });
  assert.equal(response.status, 201);
  const incidents = await (await call('/api/incidents', { headers: { cookie } })).json();
  assert.equal(incidents[0].title, 'B3 Gebäude');

  response = await call('/api/login', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'gf@example.de', password: 'anderes-passwort' })
  });
  const memberCookie = response.headers.get('set-cookie').split(';')[0];
  assert.equal((await call('/api/users', { headers: { cookie: memberCookie } })).status, 403);
  response = await call(`/api/incidents/${incidents[0].id}/reports`, {
    method: 'POST', headers: { cookie: memberCookie, 'content-type': 'application/json' },
    body: JSON.stringify({ narrative: 'Brand gelöscht', vehicles: 'LF 10', personnel: '1/8' })
  });
  const report = await response.json();
  assert.equal(response.status, 201);
  assert.equal((await call(`/api/reports/${report.id}/release`, { method: 'POST', headers: { cookie: memberCookie } })).status, 403);
});
