const http = require('node:http');
const { readFileSync, mkdirSync } = require('node:fs');
const { join } = require('node:path');
const { randomBytes, scryptSync, timingSafeEqual } = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');

const html = readFileSync(join(__dirname, 'public', 'index.html'));
const roles = new Set(['wehrleitung', 'einheitsleitung', 'fuehrungskraft']);

function createApp({ dbPath = join(__dirname, 'data', 'app.db'), fetchImpl = fetch } = {}) {
  if (dbPath !== ':memory:') mkdirSync(join(__dirname, 'data'), { recursive: true });
  const db = new DatabaseSync(dbPath);
  db.exec(`
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS organizations (
      id INTEGER PRIMARY KEY, name TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS units (
      id INTEGER PRIMARY KEY, organization_id INTEGER NOT NULL REFERENCES organizations(id),
      name TEXT NOT NULL, divera_access_key TEXT, UNIQUE(organization_id, name)
    );
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY, organization_id INTEGER NOT NULL REFERENCES organizations(id),
      unit_id INTEGER REFERENCES units(id), name TEXT NOT NULL, email TEXT NOT NULL COLLATE NOCASE UNIQUE,
      password_hash TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('wehrleitung','einheitsleitung','fuehrungskraft')),
      CHECK(role = 'wehrleitung' OR unit_id IS NOT NULL)
    );
    CREATE TABLE IF NOT EXISTS user_units (
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      unit_id INTEGER NOT NULL REFERENCES units(id) ON DELETE CASCADE,
      PRIMARY KEY(user_id, unit_id)
    );
    INSERT OR IGNORE INTO user_units(user_id,unit_id)
      SELECT id,unit_id FROM users WHERE unit_id IS NOT NULL;
    CREATE TABLE IF NOT EXISTS sessions (
      token TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      expires_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS incidents (
      id INTEGER PRIMARY KEY, organization_id INTEGER NOT NULL REFERENCES organizations(id),
      divera_id TEXT, title TEXT NOT NULL, started_at TEXT NOT NULL, address TEXT NOT NULL DEFAULT '',
      consolidated_text TEXT NOT NULL DEFAULT '', consolidated_at TEXT,
      UNIQUE(organization_id, divera_id)
    );
    CREATE TABLE IF NOT EXISTS incident_units (
      incident_id INTEGER NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
      unit_id INTEGER NOT NULL REFERENCES units(id), vehicles TEXT NOT NULL DEFAULT '[]',
      PRIMARY KEY(incident_id, unit_id)
    );
    CREATE TABLE IF NOT EXISTS reports (
      id INTEGER PRIMARY KEY, incident_id INTEGER NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
      unit_id INTEGER NOT NULL REFERENCES units(id), author_id INTEGER NOT NULL REFERENCES users(id),
      narrative TEXT NOT NULL, vehicles TEXT NOT NULL DEFAULT '', personnel TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','released')),
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      released_at TEXT
    );
  `);

  const sql = {
    userBySession: db.prepare(`
      SELECT u.*, o.name organization_name,
        COALESCE((SELECT json_group_array(uu.unit_id) FROM user_units uu WHERE uu.user_id=u.id),'[]') unit_ids
      FROM sessions s JOIN users u ON u.id=s.user_id
      JOIN organizations o ON o.id=u.organization_id
      WHERE s.token=? AND s.expires_at > datetime('now')`),
    unit: db.prepare('SELECT * FROM units WHERE id=? AND organization_id=?'),
    incident: db.prepare('SELECT * FROM incidents WHERE id=? AND organization_id=?'),
    report: db.prepare(`
      SELECT r.* FROM reports r JOIN incidents i ON i.id=r.incident_id
      WHERE r.id=? AND i.organization_id=?`)
  };

  function json(res, status, value, headers = {}) {
    res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', ...headers });
    res.end(JSON.stringify(value));
  }

  function parseCookie(req, name) {
    const match = (`; ${req.headers.cookie || ''}`).match(`;\\s*${name}=([^;]+)`);
    return match && decodeURIComponent(match[1]);
  }

  function currentUser(req) {
    const token = parseCookie(req, 'session');
    const user = token ? sql.userBySession.get(token) : null;
    if (user) user.unitIds = JSON.parse(user.unit_ids);
    return user;
  }

  async function body(req) {
    const chunks = [];
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > 1_000_000) throw Object.assign(new Error('Anfrage zu groß'), { status: 413 });
      chunks.push(chunk);
    }
    try {
      return JSON.parse(Buffer.concat(chunks).toString() || '{}');
    } catch {
      throw Object.assign(new Error('Ungültiges JSON'), { status: 400 });
    }
  }

  function required(value, name, max = 10_000) {
    const text = String(value || '').trim();
    if (!text || text.length > max) throw Object.assign(new Error(`${name} ist ungültig`), { status: 400 });
    return text;
  }

  function passwordHash(password) {
    const salt = randomBytes(16);
    return `${salt.toString('hex')}:${scryptSync(password, salt, 64).toString('hex')}`;
  }

  function passwordMatches(password, stored) {
    const [salt, expected] = stored.split(':');
    const actual = scryptSync(password, Buffer.from(salt, 'hex'), 64);
    return timingSafeEqual(actual, Buffer.from(expected, 'hex'));
  }

  function assertRole(user, ...allowed) {
    if (!user || !allowed.includes(user.role)) throw Object.assign(new Error('Keine Berechtigung'), { status: 403 });
  }

  function assertOwnUnit(user, unitId) {
    if (user.role !== 'wehrleitung' && !user.unitIds.includes(Number(unitId))) {
      throw Object.assign(new Error('Keine Berechtigung für diese Einheit'), { status: 403 });
    }
  }

  function membershipIds(data, organizationId, requiredForRole = data.role) {
    const ids = [...new Set((data.unitIds || (data.unitId ? [data.unitId] : [])).map(Number))];
    if (requiredForRole !== 'wehrleitung' && !ids.length) {
      throw Object.assign(new Error('Für diese Rolle ist mindestens eine Einheit erforderlich'), { status: 400 });
    }
    if (ids.some(id => !Number.isInteger(id) || !sql.unit.get(id, organizationId))) {
      throw Object.assign(new Error('Einheit nicht gefunden'), { status: 404 });
    }
    return ids;
  }

  function replaceMemberships(userId, unitIds) {
    db.prepare('DELETE FROM user_units WHERE user_id=?').run(userId);
    const add = db.prepare('INSERT INTO user_units(user_id,unit_id) VALUES(?,?)');
    for (const unitId of unitIds) add.run(userId, unitId);
  }

  function route(method, pattern, handler) {
    return { method, pattern, handler };
  }

  const routes = [
    route('GET', /^\/api\/bootstrap$/, async (_req, res) => {
      json(res, 200, { needsSetup: !db.prepare('SELECT 1 FROM users LIMIT 1').get() });
    }),
    route('POST', /^\/api\/setup$/, async (req, res) => {
      if (db.prepare('SELECT 1 FROM users LIMIT 1').get()) throw Object.assign(new Error('Einrichtung abgeschlossen'), { status: 409 });
      const data = await body(req);
      const password = required(data.password, 'Passwort', 200);
      if (password.length < 10) throw Object.assign(new Error('Passwort muss mindestens 10 Zeichen haben'), { status: 400 });
      db.exec('BEGIN');
      try {
        const org = db.prepare('INSERT INTO organizations(name) VALUES(?)').run(required(data.organization, 'Wehr', 200)).lastInsertRowid;
        const unit = db.prepare('INSERT INTO units(organization_id,name) VALUES(?,?)').run(org, required(data.unit, 'Einheit', 200)).lastInsertRowid;
        const created = db.prepare(`INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) VALUES(?,?,?,?,?,'wehrleitung')`)
          .run(org, unit, required(data.name, 'Name', 200), required(data.email, 'E-Mail', 320), passwordHash(password));
        replaceMemberships(created.lastInsertRowid, [Number(unit)]);
        db.exec('COMMIT');
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
      json(res, 201, { ok: true });
    }),
    route('POST', /^\/api\/login$/, async (req, res) => {
      const data = await body(req);
      const user = db.prepare('SELECT * FROM users WHERE email=?').get(required(data.email, 'E-Mail', 320));
      if (!user || !passwordMatches(String(data.password || ''), user.password_hash)) {
        throw Object.assign(new Error('E-Mail oder Passwort falsch'), { status: 401 });
      }
      const token = randomBytes(32).toString('base64url');
      db.prepare("DELETE FROM sessions WHERE expires_at <= datetime('now')").run();
      db.prepare("INSERT INTO sessions VALUES(?,?,datetime('now','+12 hours'))").run(token, user.id);
      json(res, 200, { ok: true }, { 'set-cookie': `session=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=43200` });
    }),
    route('POST', /^\/api\/logout$/, async (req, res) => {
      const token = parseCookie(req, 'session');
      if (token) db.prepare('DELETE FROM sessions WHERE token=?').run(token);
      json(res, 200, { ok: true }, { 'set-cookie': 'session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0' });
    }),
    route('GET', /^\/api\/me$/, async (req, res, _match, user) => json(res, 200, user)),
    route('GET', /^\/api\/units$/, async (_req, res, _match, user) => {
      json(res, 200, db.prepare(`
        SELECT id,name,divera_access_key IS NOT NULL divera_configured
        FROM units WHERE organization_id=? ORDER BY name`).all(user.organization_id));
    }),
    route('POST', /^\/api\/units$/, async (req, res, _match, user) => {
      assertRole(user, 'wehrleitung');
      const data = await body(req);
      const result = db.prepare('INSERT INTO units(organization_id,name) VALUES(?,?)')
        .run(user.organization_id, required(data.name, 'Name', 200));
      json(res, 201, { id: Number(result.lastInsertRowid) });
    }),
    route('GET', /^\/api\/users$/, async (_req, res, _match, user) => {
      assertRole(user, 'wehrleitung');
      json(res, 200, db.prepare(`
        SELECT u.id,u.name,u.email,u.role,
          COALESCE((SELECT json_group_array(uu.unit_id) FROM user_units uu WHERE uu.user_id=u.id),'[]') unit_ids,
          COALESCE((SELECT group_concat(un.name, ', ') FROM user_units uu JOIN units un ON un.id=uu.unit_id WHERE uu.user_id=u.id),'') unit_names
        FROM users u
        WHERE u.organization_id=? ORDER BY u.name`).all(user.organization_id));
    }),
    route('POST', /^\/api\/users$/, async (req, res, _match, user) => {
      assertRole(user, 'wehrleitung');
      const data = await body(req);
      if (!roles.has(data.role)) throw Object.assign(new Error('Rolle ist ungültig'), { status: 400 });
      const password = required(data.password, 'Passwort', 200);
      if (password.length < 10) throw Object.assign(new Error('Passwort muss mindestens 10 Zeichen haben'), { status: 400 });
      const unitIds = membershipIds(data, user.organization_id);
      const result = db.prepare(`INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) VALUES(?,?,?,?,?,?)`)
        .run(user.organization_id, unitIds[0] || null, required(data.name, 'Name', 200), required(data.email, 'E-Mail', 320), passwordHash(password), data.role);
      replaceMemberships(result.lastInsertRowid, unitIds);
      json(res, 201, { id: Number(result.lastInsertRowid) });
    }),
    route('PUT', /^\/api\/users\/(\d+)$/, async (req, res, match, user) => {
      assertRole(user, 'wehrleitung');
      const existing = db.prepare('SELECT * FROM users WHERE id=? AND organization_id=?').get(match[1], user.organization_id);
      if (!existing) throw Object.assign(new Error('Benutzer nicht gefunden'), { status: 404 });
      const data = await body(req);
      if (!roles.has(data.role)) throw Object.assign(new Error('Rolle ist ungültig'), { status: 400 });
      const unitIds = membershipIds(data, user.organization_id);
      const password = String(data.password || '');
      if (password && password.length < 10) throw Object.assign(new Error('Passwort muss mindestens 10 Zeichen haben'), { status: 400 });
      db.exec('BEGIN');
      try {
        db.prepare(`UPDATE users SET unit_id=?,name=?,email=?,role=?,password_hash=? WHERE id=?`)
          .run(unitIds[0] || null, required(data.name, 'Name', 200), required(data.email, 'E-Mail', 320),
            data.role, password ? passwordHash(password) : existing.password_hash, existing.id);
        replaceMemberships(existing.id, unitIds);
        db.exec('COMMIT');
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
      json(res, 200, { ok: true });
    }),
    route('GET', /^\/api\/incidents$/, async (_req, res, _match, user) => {
      const where = user.role === 'wehrleitung'
        ? 'i.organization_id=?'
        : `i.organization_id=? AND EXISTS (
            SELECT 1 FROM incident_units x JOIN user_units uu ON uu.unit_id=x.unit_id
            WHERE x.incident_id=i.id AND uu.user_id=?)`;
      const args = user.role === 'wehrleitung' ? [user.organization_id] : [user.organization_id, user.id];
      json(res, 200, db.prepare(`
        SELECT i.*, group_concat(u.name, ', ') units,
          json_group_array(json_object('unitId',iu.unit_id,'vehicles',iu.vehicles)) assignments
        FROM incidents i LEFT JOIN incident_units iu ON iu.incident_id=i.id
        LEFT JOIN units u ON u.id=iu.unit_id WHERE ${where}
        GROUP BY i.id ORDER BY i.started_at DESC`).all(...args));
    }),
    route('POST', /^\/api\/incidents$/, async (req, res, _match, user) => {
      const data = await body(req);
      const unitIds = [...new Set((data.unitIds || []).map(Number))];
      if (!unitIds.length || unitIds.some(id => !sql.unit.get(id, user.organization_id))) {
        throw Object.assign(new Error('Mindestens eine gültige Einheit ist erforderlich'), { status: 400 });
      }
      for (const unitId of unitIds) assertOwnUnit(user, unitId);
      const incident = db.prepare(`INSERT INTO incidents(organization_id,title,started_at,address) VALUES(?,?,?,?)`)
        .run(user.organization_id, required(data.title, 'Stichwort', 300), required(data.startedAt, 'Zeitpunkt', 50), String(data.address || '').trim());
      const addUnit = db.prepare('INSERT INTO incident_units(incident_id,unit_id) VALUES(?,?)');
      for (const unitId of unitIds) addUnit.run(incident.lastInsertRowid, unitId);
      json(res, 201, { id: Number(incident.lastInsertRowid) });
    }),
    route('GET', /^\/api\/incidents\/(\d+)\/reports$/, async (_req, res, match, user) => {
      const incident = sql.incident.get(match[1], user.organization_id);
      if (!incident) throw Object.assign(new Error('Einsatz nicht gefunden'), { status: 404 });
      const visible = user.role === 'wehrleitung' ? ['1=1'] :
        user.role === 'einheitsleitung'
          ? ['EXISTS (SELECT 1 FROM user_units uu WHERE uu.user_id=? AND uu.unit_id=r.unit_id)', user.id]
          : ['r.author_id=?', user.id];
      json(res, 200, db.prepare(`
        SELECT r.*,u.name author_name,un.name unit_name FROM reports r
        JOIN users u ON u.id=r.author_id JOIN units un ON un.id=r.unit_id
        WHERE r.incident_id=? AND ${visible[0]} ORDER BY r.created_at`).all(match[1], ...visible.slice(1)));
    }),
    route('POST', /^\/api\/incidents\/(\d+)\/reports$/, async (req, res, match, user) => {
      const incident = sql.incident.get(match[1], user.organization_id);
      if (!incident) throw Object.assign(new Error('Einsatz nicht gefunden'), { status: 404 });
      const data = await body(req);
      const unitId = Number(data.unitId);
      assertOwnUnit(user, unitId);
      if (!db.prepare('SELECT 1 FROM incident_units WHERE incident_id=? AND unit_id=?').get(match[1], unitId)) {
        throw Object.assign(new Error('Einheit wurde nicht alarmiert'), { status: 400 });
      }
      const result = db.prepare(`
        INSERT INTO reports(incident_id,unit_id,author_id,narrative,vehicles,personnel)
        VALUES(?,?,?,?,?,?)`).run(match[1], unitId, user.id, required(data.narrative, 'Bericht'), String(data.vehicles || ''), String(data.personnel || ''));
      json(res, 201, { id: Number(result.lastInsertRowid) });
    }),
    route('PUT', /^\/api\/reports\/(\d+)$/, async (req, res, match, user) => {
      const report = sql.report.get(match[1], user.organization_id);
      if (!report) throw Object.assign(new Error('Bericht nicht gefunden'), { status: 404 });
      const mayEdit = report.status === 'draft' &&
        (report.author_id === user.id || (user.role === 'einheitsleitung' && user.unitIds.includes(report.unit_id)));
      if (!mayEdit) throw Object.assign(new Error('Der Bericht kann nicht bearbeitet werden'), { status: 403 });
      const data = await body(req);
      db.prepare(`UPDATE reports SET narrative=?,vehicles=?,personnel=?,updated_at=CURRENT_TIMESTAMP WHERE id=?`)
        .run(required(data.narrative, 'Bericht'), String(data.vehicles || ''), String(data.personnel || ''), report.id);
      json(res, 200, { ok: true });
    }),
    route('POST', /^\/api\/reports\/(\d+)\/release$/, async (_req, res, match, user) => {
      assertRole(user, 'einheitsleitung', 'wehrleitung');
      const report = sql.report.get(match[1], user.organization_id);
      if (!report) throw Object.assign(new Error('Bericht nicht gefunden'), { status: 404 });
      assertOwnUnit(user, report.unit_id);
      db.prepare(`UPDATE reports SET status='released',released_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE id=?`).run(report.id);
      json(res, 200, { ok: true });
    }),
    route('PUT', /^\/api\/incidents\/(\d+)\/consolidation$/, async (req, res, match, user) => {
      assertRole(user, 'wehrleitung');
      if (!sql.incident.get(match[1], user.organization_id)) throw Object.assign(new Error('Einsatz nicht gefunden'), { status: 404 });
      const data = await body(req);
      db.prepare(`UPDATE incidents SET consolidated_text=?,consolidated_at=CURRENT_TIMESTAMP WHERE id=?`)
        .run(required(data.text, 'Gesamtbericht'), match[1]);
      json(res, 200, { ok: true });
    }),
    route('PUT', /^\/api\/units\/(\d+)\/divera$/, async (req, res, match, user) => {
      assertRole(user, 'wehrleitung', 'einheitsleitung');
      assertOwnUnit(user, match[1]);
      if (!sql.unit.get(match[1], user.organization_id)) throw Object.assign(new Error('Einheit nicht gefunden'), { status: 404 });
      const data = await body(req);
      db.prepare('UPDATE units SET divera_access_key=? WHERE id=?').run(required(data.accessKey, 'Access-Key', 500), match[1]);
      json(res, 200, { ok: true });
    }),
    route('GET', /^\/api\/units\/(\d+)\/divera$/, async (_req, res, match, user) => {
      assertRole(user, 'wehrleitung', 'einheitsleitung');
      assertOwnUnit(user, match[1]);
      const unit = sql.unit.get(match[1], user.organization_id);
      if (!unit?.divera_access_key) throw Object.assign(new Error('DIVERA ist nicht konfiguriert'), { status: 400 });
      const key = encodeURIComponent(unit.divera_access_key);
      const [alarmsRes, vehiclesRes] = await Promise.all([
        fetchImpl(`https://app.divera247.com/api/v2/alarms?accesskey=${key}`, { method: 'GET' }),
        fetchImpl(`https://www.divera247.com/api/v2/pull/vehicle-status?accesskey=${key}`, { method: 'GET' })
      ]);
      if (!alarmsRes.ok || !vehiclesRes.ok) throw Object.assign(new Error('DIVERA-Abfrage fehlgeschlagen'), { status: 502 });
      const [alarmsRaw, vehiclesRaw] = await Promise.all([alarmsRes.json(), vehiclesRes.json()]);
      const array = value => Array.isArray(value) ? value : Object.values(value || {});
      const vehicles = array(vehiclesRaw.data?.items || vehiclesRaw.data || vehiclesRaw.items || vehiclesRaw).map(v => ({
        id: String(v.id || v.vehicle_id || ''),
        name: v.name || v.vehicle || v.callname || String(v.id || '')
      }));
      const alarms = array(alarmsRaw.data?.items || alarmsRaw.data || alarmsRaw.items || alarmsRaw).map(a => {
        const assigned = a.vehicles || a.vehicle_ids || a.vehicle || [];
        const ids = Array.isArray(assigned) ? assigned
          : typeof assigned === 'object' ? Object.keys(assigned) : String(assigned).split(',');
        return {
          id: String(a.id || a.cluster_id || a.number || ''),
          title: a.title || a.text || a.type || 'Einsatz',
          startedAt: a.ts_create || a.date || a.created_at || new Date().toISOString(),
          address: a.address || a.location || '',
          vehicles: ids.map(id => vehicles.find(v => v.id === String(id).trim())?.name || String(id).trim()).filter(Boolean)
        };
      });
      json(res, 200, { alarms, vehicles });
    }),
    route('POST', /^\/api\/units\/(\d+)\/divera\/import$/, async (req, res, match, user) => {
      assertRole(user, 'wehrleitung', 'einheitsleitung');
      assertOwnUnit(user, match[1]);
      const unit = sql.unit.get(match[1], user.organization_id);
      if (!unit) throw Object.assign(new Error('Einheit nicht gefunden'), { status: 404 });
      const data = await body(req);
      const diveraId = required(data.id, 'DIVERA-ID', 200);
      const incidentId = Number(db.prepare(`
        INSERT INTO incidents(organization_id,divera_id,title,started_at,address) VALUES(?,?,?,?,?)
        ON CONFLICT(organization_id,divera_id) DO UPDATE SET
          title=excluded.title,started_at=excluded.started_at,address=excluded.address
        RETURNING id`).get(user.organization_id, diveraId, required(data.title, 'Stichwort', 300),
          required(data.startedAt, 'Zeitpunkt', 100), String(data.address || '')).id);
      db.prepare(`INSERT INTO incident_units(incident_id,unit_id,vehicles) VALUES(?,?,?)
        ON CONFLICT(incident_id,unit_id) DO UPDATE SET vehicles=excluded.vehicles`)
        .run(incidentId, unit.id, JSON.stringify(data.vehicles || []));
      json(res, 201, { id: incidentId });
    })
  ];

  return http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      if (req.method === 'GET' && url.pathname === '/') {
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
        return res.end(html);
      }
      const found = routes.map(r => ({ ...r, match: url.pathname.match(r.pattern) }))
        .find(r => r.method === req.method && r.match);
      if (!found) return json(res, 404, { error: 'Nicht gefunden' });
      const publicRoute = ['/api/bootstrap', '/api/setup', '/api/login'].includes(url.pathname);
      const user = publicRoute ? null : currentUser(req);
      if (!publicRoute && !user) return json(res, 401, { error: 'Bitte anmelden' });
      await found.handler(req, res, found.match, user);
    } catch (error) {
      const status = error.status || (error.code?.startsWith('SQLITE_CONSTRAINT') ? 409 : 500);
      if (status === 500) console.error(error);
      json(res, status, { error: status === 500 ? 'Interner Fehler' : error.message });
    }
  });
}

if (require.main === module) {
  const port = Number(process.env.PORT || 3000);
  createApp().listen(port, () => console.log(`Einsatzberichte: http://localhost:${port}`));
}

module.exports = { createApp };
