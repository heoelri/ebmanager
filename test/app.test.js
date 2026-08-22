const test = require('node:test');
const assert = require('node:assert/strict');
const { createApp } = require('../server');

test('setup, login and tenant-scoped incident flow', async t => {
  const diveraRequests = [];
  const server = createApp({
    dbPath: ':memory:',
    fetchImpl: async (url, options) => {
      diveraRequests.push({ url, options });
      if (url.includes('/pull/all')) return {
        ok: true,
        json: async () => ({ data: { cluster: {
          consumer: {
            10: { firstname: 'Anna', lastname: 'Muster', qualifications: [100] },
            11: { stdformat_name: 'Ben Beispiel', qualifications: [] }
          },
          qualification: { 100: { name: 'Atemschutzgeräteträger', shortname: 'AGT' } },
          vehicle: { 20: {
            id: 20,
            name: 'HLF 20',
            shortname: 'HLF',
            fullname: 'Hilfeleistungslöschfahrzeug'
          } }
        } } })
      };
      if (url.includes('/alarms')) return {
        ok: true,
        json: async () => ({ data: { items: { 42: {
          id: 42, date: 1787425200, title: 'H1', vehicle: [20, 21]
        } } } })
      };
      return { ok: true, json: async () => ({ data: [] }) };
    }
  });
  await new Promise(resolve => server.listen(0, resolve));
  t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = (path, options) => fetch(base + path, options);
  const reportDetails = {
    departedAt: '2026-08-22T19:05:00.000Z',
    arrivedAt: '2026-08-22T19:10:00.000Z',
    endedAt: '2026-08-22T20:20:00.000Z',
    incidentType: 'Technische Hilfe',
    classification: {
      site: ['Verkehrsfläche'],
      cause: [],
      technical: ['Menschen in Notlage']
    }
  };

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
  response = await call('/api/units', {
    method: 'POST', headers: { cookie, 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'Löschzug 2' })
  });
  const secondUnit = await response.json();
  assert.equal(response.status, 201);
  response = await call(`/api/units/${units[0].id}/divera`, {
    method: 'PUT', headers: { cookie, 'content-type': 'application/json' },
    body: JSON.stringify({ accessKey: 'read-only-key' })
  });
  assert.equal(response.status, 200);
  response = await call(`/api/units/${units[0].id}/divera`, { headers: { cookie } });
  assert.equal(response.status, 200);
  const divera = await response.json();
  assert.deepEqual(divera.alarms[0].vehicles[0], {
    id: '20',
    name: 'HLF 20',
    shortname: 'HLF',
    fullname: 'Hilfeleistungslöschfahrzeug',
    own: true
  });
  assert.equal(divera.alarms[0].vehicles[1].own, false);
  assert.equal(diveraRequests.length, 2);
  assert.ok(diveraRequests.every(request => request.options.method === 'GET'));
  response = await call(`/api/units/${secondUnit.id}/divera`, {
    method: 'PUT', headers: { cookie, 'content-type': 'application/json' },
    body: JSON.stringify({ accessKey: 'second-read-only-key' })
  });
  assert.equal(response.status, 200);
  for (const unitId of [units[0].id, secondUnit.id]) {
    response = await call(`/api/units/${unitId}/divera/members/sync`, { method: 'POST', headers: { cookie } });
    assert.equal(response.status, 200);
    const members = await (await call(`/api/units/${unitId}/members`, { headers: { cookie } })).json();
    assert.equal(members.length, 2);
    assert.equal(members.find(member => member.name === 'Anna Muster').qualifications, 'Atemschutzgeräteträger');
  }
  response = await call('/api/users', {
    method: 'POST', headers: { cookie, 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'Gruppenführer', email: 'gf@example.de', password: 'anderes-passwort', role: 'fuehrungskraft', unitIds: [units[0].id] })
  });
  assert.equal(response.status, 201);
  const createdUser = await response.json();
  response = await call(`/api/users/${createdUser.id}`, {
    method: 'PUT', headers: { cookie, 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'Gruppenführer Neu', email: 'gf@example.de', role: 'fuehrungskraft', unitIds: [units[0].id, secondUnit.id] })
  });
  assert.equal(response.status, 200);

  response = await call('/api/incidents', {
    method: 'POST', headers: { cookie, 'content-type': 'application/json' },
    body: JSON.stringify({ title: 'B3 Gebäude', startedAt: '2026-08-22T18:00', unitIds: [units[0].id, secondUnit.id] })
  });
  assert.equal(response.status, 201);
  const incidents = await (await call('/api/incidents', { headers: { cookie } })).json();
  assert.equal(incidents[0].title, 'B3 Gebäude');

  response = await call('/api/login', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'gf@example.de', password: 'anderes-passwort' })
  });
  const memberCookie = response.headers.get('set-cookie').split(';')[0];
  const member = await (await call('/api/me', { headers: { cookie: memberCookie } })).json();
  assert.deepEqual(member.unitIds.sort(), [units[0].id, secondUnit.id].sort());
  assert.equal(member.name, 'Gruppenführer Neu');
  assert.equal((await call('/api/users', { headers: { cookie: memberCookie } })).status, 403);
  response = await call(`/api/incidents/${incidents[0].id}/reports`, {
    method: 'POST', headers: { cookie: memberCookie, 'content-type': 'application/json' },
    body: JSON.stringify({
      ...reportDetails,
      departedAt: '2026-08-22T18:05:00.000Z',
      arrivedAt: '2026-08-22T18:10:00.000Z',
      endedAt: '2026-08-22T18:30:00.000Z',
      unitId: secondUnit.id,
      narrative: 'Brand gelöscht'
    })
  });
  const report = await response.json();
  assert.equal(response.status, 201);
  assert.equal((await call(`/api/reports/${report.id}/release`, { method: 'POST', headers: { cookie: memberCookie } })).status, 403);

  const imported = {
    id: 'divera-42',
    foreignId: '2026-0042',
    date: 1787425200,
    title: 'H1 Hilfeleistung',
    startedAt: '2026-08-22T19:00:00.000Z',
    text: 'Person in Notlage',
    address: 'Hauptstraße 1',
    lat: 50.1,
    lng: 8.6,
    remark: 'Zufahrt über Innenhof',
    patient: 'Eine betroffene Person',
    caller: 'Leitstelle',
    vehicles: divera.alarms[0].vehicles
  };
  for (const unitId of [units[0].id, units[0].id, secondUnit.id]) {
    response = await call(`/api/units/${unitId}/divera/import`, {
      method: 'POST', headers: { cookie, 'content-type': 'application/json' },
      body: JSON.stringify(imported)
    });
    assert.equal(response.status, 201);
  }
  const afterImport = await (await call('/api/incidents', { headers: { cookie } })).json();
  const diveraIncidents = afterImport.filter(incident => incident.divera_id === imported.id);
  assert.equal(diveraIncidents.length, 1);
  assert.deepEqual({
    foreignId: diveraIncidents[0].foreign_id,
    date: diveraIncidents[0].divera_date,
    text: diveraIncidents[0].message,
    lat: diveraIncidents[0].lat,
    lng: diveraIncidents[0].lng,
    remark: diveraIncidents[0].remark,
    patient: diveraIncidents[0].patient,
    caller: diveraIncidents[0].caller
  }, {
    foreignId: imported.foreignId,
    date: imported.date,
    text: imported.text,
    lat: imported.lat,
    lng: imported.lng,
    remark: imported.remark,
    patient: imported.patient,
    caller: imported.caller
  });
  const assignments = JSON.parse(diveraIncidents[0].assignments);
  assert.equal(assignments.length, 2);
  assert.equal(new Set(assignments.map(assignment => assignment.unitId)).size, 2);
  const importedVehicles = JSON.parse(assignments[0].vehicles);
  assert.deepEqual(importedVehicles.map(vehicle => vehicle.own), [true, false]);

  const members = await (await call(`/api/units/${secondUnit.id}/members`, { headers: { cookie: memberCookie } })).json();
  response = await call(`/api/incidents/${diveraIncidents[0].id}/reports`, {
    method: 'POST', headers: { cookie: memberCookie, 'content-type': 'application/json' },
    body: JSON.stringify({
      ...reportDetails,
      unitId: secondUnit.id,
      narrative: 'Ungültige fremde Besatzung',
      crew: [{ memberId: members[0].id, vehicle: '21', role: 'maschinist' }]
    })
  });
  assert.equal(response.status, 400);
  response = await call(`/api/incidents/${diveraIncidents[0].id}/reports`, {
    method: 'POST', headers: { cookie: memberCookie, 'content-type': 'application/json' },
    body: JSON.stringify({
      ...reportDetails,
      unitId: secondUnit.id,
      narrative: 'Doppelter Maschinist',
      crew: members.map(member => ({ memberId: member.id, vehicle: 'HLF 20', role: 'maschinist' }))
    })
  });
  assert.equal(response.status, 400);
  response = await call(`/api/incidents/${diveraIncidents[0].id}/reports`, {
    method: 'POST', headers: { cookie: memberCookie, 'content-type': 'application/json' },
    body: JSON.stringify({
      ...reportDetails,
      unitId: secondUnit.id,
      narrative: 'Einsatz mit Fahrzeugbesatzung',
      crew: [
        { memberId: members[0].id, vehicle: 'HLF 20', role: 'maschinist' },
        { memberId: members[1].id, vehicle: 'HLF 20', role: 'besatzung' }
      ]
    })
  });
  assert.equal(response.status, 201);
  const reports = await (await call(`/api/incidents/${diveraIncidents[0].id}/reports`, { headers: { cookie: memberCookie } })).json();
  assert.deepEqual(JSON.parse(reports[0].crew), [
    { memberId: members[0].id, name: members[0].name, vehicle: 'HLF 20', role: 'maschinist' },
    { memberId: members[1].id, name: members[1].name, vehicle: 'HLF 20', role: 'besatzung' }
  ]);
  assert.equal(reports[0].alarmed_at, imported.startedAt);
  assert.equal(reports[0].departed_at, reportDetails.departedAt);
  assert.equal(reports[0].arrived_at, reportDetails.arrivedAt);
  assert.equal(reports[0].ended_at, reportDetails.endedAt);
  assert.equal(reports[0].duration_minutes, 80);
  assert.equal(reports[0].incident_type, reportDetails.incidentType);
  assert.deepEqual(JSON.parse(reports[0].classification), reportDetails.classification);
  response = await call(`/api/incidents/${diveraIncidents[0].id}/reports`, {
    method: 'POST', headers: { cookie: memberCookie, 'content-type': 'application/json' },
    body: JSON.stringify({ unitId: secondUnit.id, narrative: 'Zweiter Bericht', crew: [] })
  });
  assert.equal(response.status, 409);
  assert.ok(diveraRequests.every(request => request.options.method === 'GET'));
});
