const http = require('node:http');
const { readFileSync, mkdirSync } = require('node:fs');
const { join } = require('node:path');
const { randomBytes, scryptSync, timingSafeEqual } = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');

const html = readFileSync(join(__dirname, 'public', 'index.html'));
const roles = new Set(['wehrleitung', 'einheitsleitung', 'fuehrungskraft']);
const incidentTypes = new Set([
  'Kleinbrand', 'Mittelbrand', 'Großbrand', 'Wald- und Flächenbrand',
  'Schornsteinbrand', 'Kfz-Brand', 'Verkehrsunfall', 'Oelunfall/Oelspur',
  'Chemieunfall', 'Technische Hilfe', 'Sturmeinsatz', 'Hochwassereinsatz',
  'Fehlalarm BMA', 'BMA', 'Fehlalarm', 'Böswilliger Alarm', 'Sonstiges'
]);
const classifications = {
  site: new Set([
    'Wohngebäude', 'Büro und Verwaltungsgebäude', 'Landwirtschaftlicher Betrieb',
    'Gewerbebetrieb', 'Industriebetrieb', 'Theater, Kino, Versammlungsstätte',
    'Alten- u. Pflegeeinrichtung, Klinik', 'Verkehrsfläche',
    'Wald, Heide, Moor, Feldflur', 'Sonstige'
  ]),
  cause: new Set([
    'Bauliche Mängel', 'Betriebliche u. maschinelle Mängel', 'Blitzschlag',
    'Elektrizität', 'Explosion', 'Fahrlässigkeit', 'Selbstentzündung',
    'Sonst. Feuer-, Licht- u. Wärmequelle', 'Verursacht durch Kinder',
    'Vorsätzliche Brandstiftung', 'Unbekannt'
  ]),
  technical: new Set([
    'Menschen in Notlage', 'Tiere in Notlage', 'Betriebsunfall',
    'Einsturz von Baulichkeiten', 'Gasausströmung', 'Gasvergiftung',
    'Schäden durch radioaktive Stoffe', 'Wasserschaden', 'Sturmschaden',
    'Sonstige technische Hilfeleistung'
  ])
};

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
      divera_id TEXT, foreign_id TEXT NOT NULL DEFAULT '', divera_date INTEGER,
      title TEXT NOT NULL, started_at TEXT NOT NULL, message TEXT NOT NULL DEFAULT '',
      address TEXT NOT NULL DEFAULT '', lat REAL, lng REAL,
      remark TEXT NOT NULL DEFAULT '', patient TEXT NOT NULL DEFAULT '', caller TEXT NOT NULL DEFAULT '',
      consolidated_text TEXT NOT NULL DEFAULT '', consolidated_at TEXT,
      UNIQUE(organization_id, divera_id)
    );
    CREATE TABLE IF NOT EXISTS incident_units (
      incident_id INTEGER NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
      unit_id INTEGER NOT NULL REFERENCES units(id), vehicles TEXT NOT NULL DEFAULT '[]',
      PRIMARY KEY(incident_id, unit_id)
    );
    CREATE TABLE IF NOT EXISTS members (
      id INTEGER PRIMARY KEY, organization_id INTEGER NOT NULL REFERENCES organizations(id),
      divera_id TEXT NOT NULL, name TEXT NOT NULL,
      UNIQUE(organization_id, divera_id)
    );
    CREATE TABLE IF NOT EXISTS member_units (
      member_id INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
      unit_id INTEGER NOT NULL REFERENCES units(id) ON DELETE CASCADE,
      PRIMARY KEY(member_id, unit_id)
    );
    CREATE TABLE IF NOT EXISTS qualifications (
      id INTEGER PRIMARY KEY, unit_id INTEGER NOT NULL REFERENCES units(id) ON DELETE CASCADE,
      divera_id TEXT NOT NULL, name TEXT NOT NULL, shortname TEXT NOT NULL DEFAULT '',
      UNIQUE(unit_id, divera_id)
    );
    CREATE TABLE IF NOT EXISTS member_qualifications (
      member_id INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
      qualification_id INTEGER NOT NULL REFERENCES qualifications(id) ON DELETE CASCADE,
      PRIMARY KEY(member_id, qualification_id)
    );
    CREATE TABLE IF NOT EXISTS reports (
      id INTEGER PRIMARY KEY, incident_id INTEGER NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
      unit_id INTEGER NOT NULL REFERENCES units(id), author_id INTEGER NOT NULL REFERENCES users(id),
      narrative TEXT NOT NULL, vehicles TEXT NOT NULL DEFAULT '', personnel TEXT NOT NULL DEFAULT '',
      alarmed_at TEXT, departed_at TEXT, arrived_at TEXT, ended_at TEXT,
      incident_type TEXT NOT NULL DEFAULT '', classification TEXT NOT NULL DEFAULT '{}',
      status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','released')),
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      released_at TEXT, UNIQUE(incident_id, unit_id)
    );
    CREATE TABLE IF NOT EXISTS report_crew (
      report_id INTEGER NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
      member_id INTEGER NOT NULL REFERENCES members(id),
      vehicle TEXT NOT NULL DEFAULT '',
      role TEXT NOT NULL DEFAULT 'besatzung',
      PRIMARY KEY(report_id, member_id)
    );
  `);
  const incidentColumns = {
    foreign_id: "TEXT NOT NULL DEFAULT ''",
    divera_date: 'INTEGER',
    message: "TEXT NOT NULL DEFAULT ''",
    lat: 'REAL',
    lng: 'REAL',
    remark: "TEXT NOT NULL DEFAULT ''",
    patient: "TEXT NOT NULL DEFAULT ''",
    caller: "TEXT NOT NULL DEFAULT ''"
  };
  const existingIncidentColumns = new Set(db.prepare('PRAGMA table_info(incidents)').all().map(column => column.name));
  for (const [name, definition] of Object.entries(incidentColumns)) {
    if (!existingIncidentColumns.has(name)) db.exec(`ALTER TABLE incidents ADD COLUMN ${name} ${definition}`);
  }
  if (!db.prepare('PRAGMA table_info(report_crew)').all().some(column => column.name === 'role')) {
    db.exec("ALTER TABLE report_crew ADD COLUMN role TEXT NOT NULL DEFAULT 'besatzung'");
  }
  const reportColumns = {
    alarmed_at: 'TEXT',
    departed_at: 'TEXT',
    arrived_at: 'TEXT',
    ended_at: 'TEXT',
    incident_type: "TEXT NOT NULL DEFAULT ''",
    classification: "TEXT NOT NULL DEFAULT '{}'"
  };
  const existingReportColumns = new Set(db.prepare('PRAGMA table_info(reports)').all().map(column => column.name));
  for (const [name, definition] of Object.entries(reportColumns)) {
    if (!existingReportColumns.has(name)) db.exec(`ALTER TABLE reports ADD COLUMN ${name} ${definition}`);
  }
  db.exec(`UPDATE reports SET alarmed_at=(
    SELECT started_at FROM incidents WHERE incidents.id=reports.incident_id
  ) WHERE alarmed_at IS NULL`);
  db.prepare("UPDATE report_crew SET role='besatzung' WHERE role='mannschaft'").run();
  const duplicateReport = db.prepare(`
    SELECT incident_id,unit_id FROM reports GROUP BY incident_id,unit_id HAVING count(*)>1 LIMIT 1`).get();
  if (duplicateReport) throw new Error(
    `Mehrere Berichte für Einsatz ${duplicateReport.incident_id} und Einheit ${duplicateReport.unit_id}; vor dem Start manuell zusammenführen`);
  db.exec('CREATE UNIQUE INDEX IF NOT EXISTS reports_incident_unit_unique ON reports(incident_id,unit_id)');

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
    if (user) {
      user.unitIds = JSON.parse(user.unit_ids);
      delete user.unit_ids;
    }
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

  function optional(value, name, max = 10_000) {
    const text = String(value ?? '').trim();
    if (text.length > max) throw Object.assign(new Error(`${name} ist zu lang`), { status: 400 });
    return text;
  }

  function finiteNumber(value, name) {
    if (value === null || value === undefined || value === '') return null;
    const number = Number(value);
    if (!Number.isFinite(number)) throw Object.assign(new Error(`${name} ist ungültig`), { status: 400 });
    return number;
  }

  function isoDate(value) {
    if (value === null || value === undefined || value === '') return new Date().toISOString();
    const number = Number(value);
    const date = new Date(Number.isFinite(number) ? number * 1000 : value);
    if (Number.isNaN(date.getTime())) throw Object.assign(new Error('DIVERA-Zeitpunkt ist ungültig'), { status: 502 });
    return date.toISOString();
  }

  function vehicleSnapshots(value) {
    if (!Array.isArray(value)) throw Object.assign(new Error('Fahrzeuge sind ungültig'), { status: 400 });
    return value.map(vehicle => {
      if (typeof vehicle === 'string') return required(vehicle, 'Fahrzeug', 200);
      if (!vehicle || typeof vehicle !== 'object') throw Object.assign(new Error('Fahrzeug ist ungültig'), { status: 400 });
      return {
        id: optional(vehicle.id, 'Fahrzeug-ID', 200),
        name: required(vehicle.name, 'Fahrzeugname', 200),
        shortname: optional(vehicle.shortname, 'Fahrzeugtyp', 100),
        fullname: optional(vehicle.fullname, 'Fahrzeugtyp', 200),
        own: vehicle.own !== false
      };
    });
  }

  function reportDetails(data, incident) {
    if (!incidentTypes.has(data.incidentType)) {
      throw Object.assign(new Error('Einsatzart ist ungültig'), { status: 400 });
    }
    const times = {
      alarmedAt: new Date(incident.started_at),
      departedAt: new Date(required(data.departedAt, 'Ausgerückt um', 100)),
      arrivedAt: new Date(required(data.arrivedAt, 'Eingetroffen um', 100)),
      endedAt: new Date(required(data.endedAt, 'Einsatz beendet um', 100))
    };
    if (Object.values(times).some(date => Number.isNaN(date.getTime())) ||
        times.departedAt < times.alarmedAt || times.arrivedAt < times.departedAt ||
        times.endedAt < times.arrivedAt) {
      throw Object.assign(new Error('Einsatzzeiten müssen vollständig und chronologisch sein'), { status: 400 });
    }
    const selected = data.classification || {};
    const classification = {};
    for (const [group, allowed] of Object.entries(classifications)) {
      const values = Array.isArray(selected[group]) ? [...new Set(selected[group].map(String))] : [];
      if (values.some(value => !allowed.has(value))) {
        throw Object.assign(new Error('Aufgliederung ist ungültig'), { status: 400 });
      }
      classification[group] = values;
    }
    return {
      alarmedAt: times.alarmedAt.toISOString(),
      departedAt: times.departedAt.toISOString(),
      arrivedAt: times.arrivedAt.toISOString(),
      endedAt: times.endedAt.toISOString(),
      incidentType: data.incidentType,
      classification: JSON.stringify(classification)
    };
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
    const source = Array.isArray(data.unitIds) ? data.unitIds : data.unitId ? [data.unitId] : [];
    const ids = [...new Set(source.map(Number))];
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

  function replaceCrew(reportId, incidentId, unitId, crew, organizationId) {
    if (!Array.isArray(crew)) throw Object.assign(new Error('Besatzung ist ungültig'), { status: 400 });
    const vehicles = JSON.parse(db.prepare(
      'SELECT vehicles FROM incident_units WHERE incident_id=? AND unit_id=?').get(incidentId, unitId)?.vehicles || '[]')
      .filter(vehicle => typeof vehicle === 'string' || vehicle.own !== false)
      .map(vehicle => typeof vehicle === 'string' ? vehicle : vehicle.name);
    const seen = new Set();
    const crewRoles = new Set(['maschinist', 'einheitsfuehrer', 'besatzung']);
    const occupiedRoles = new Set();
    const rows = crew.map(item => {
      const memberId = Number(item.memberId);
      const vehicle = String(item.vehicle || '').trim();
      const role = String(item.role || 'besatzung');
      const occupiedRole = vehicle && role !== 'besatzung' ? `${vehicle}:${role}` : null;
      if (!Number.isInteger(memberId) || seen.has(memberId) ||
          !db.prepare(`SELECT 1 FROM members m JOIN member_units mu ON mu.member_id=m.id
            WHERE m.id=? AND m.organization_id=? AND mu.unit_id=?`).get(memberId, organizationId, unitId) ||
          (vehicle && !vehicles.includes(vehicle)) || !crewRoles.has(role) ||
          (!vehicle && role !== 'besatzung') || (occupiedRole && occupiedRoles.has(occupiedRole))) {
        throw Object.assign(new Error('Besatzung ist ungültig'), { status: 400 });
      }
      seen.add(memberId);
      if (occupiedRole) occupiedRoles.add(occupiedRole);
      return { memberId, vehicle, role };
    });
    db.prepare('DELETE FROM report_crew WHERE report_id=?').run(reportId);
    const add = db.prepare('INSERT INTO report_crew(report_id,member_id,vehicle,role) VALUES(?,?,?,?)');
    for (const row of rows) add.run(reportId, row.memberId, row.vehicle, row.role);
    return {
      vehicles: [...new Set(rows.map(row => row.vehicle).filter(Boolean))].join(', '),
      personnel: rows.map(row => db.prepare('SELECT name FROM members WHERE id=?').get(row.memberId).name).join(', ')
    };
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
    route('GET', /^\/api\/me$/, async (_req, res, _match, user) => json(res, 200, {
      id: user.id,
      organization_id: user.organization_id,
      organization_name: user.organization_name,
      name: user.name,
      email: user.email,
      role: user.role,
      unitIds: user.unitIds
    })),
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
    route('GET', /^\/api\/units\/(\d+)\/members$/, async (_req, res, match, user) => {
      assertOwnUnit(user, match[1]);
      if (!sql.unit.get(match[1], user.organization_id)) throw Object.assign(new Error('Einheit nicht gefunden'), { status: 404 });
      json(res, 200, db.prepare(`
        SELECT m.id,m.name,m.divera_id,
          COALESCE((SELECT group_concat(q.name, ', ') FROM member_qualifications mq
            JOIN qualifications q ON q.id=mq.qualification_id
            WHERE mq.member_id=m.id AND q.unit_id=mu.unit_id),'') qualifications
        FROM members m
        JOIN member_units mu ON mu.member_id=m.id
        WHERE mu.unit_id=? AND m.organization_id=? ORDER BY m.name`).all(match[1], user.organization_id));
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
          json_group_array(json_object(
            'unitId',iu.unit_id,
            'vehicles',iu.vehicles,
            'hasReport',EXISTS(SELECT 1 FROM reports r WHERE r.incident_id=i.id AND r.unit_id=iu.unit_id)
          )) assignments
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
        SELECT r.*,u.name author_name,un.name unit_name,
          CAST(ROUND((julianday(r.ended_at)-julianday(r.alarmed_at))*1440) AS INTEGER) duration_minutes,
          COALESCE((SELECT json_group_array(json_object(
            'memberId',rc.member_id,'name',m.name,'vehicle',rc.vehicle,'role',rc.role))
            FROM report_crew rc JOIN members m ON m.id=rc.member_id
            WHERE rc.report_id=r.id),'[]') crew
        FROM reports r
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
      if (db.prepare('SELECT 1 FROM reports WHERE incident_id=? AND unit_id=?').get(match[1], unitId)) {
        throw Object.assign(new Error('Für diese Einheit existiert bereits ein Einsatzbericht'), { status: 409 });
      }
      db.exec('BEGIN');
      let result;
      try {
        const details = reportDetails(data, incident);
        result = db.prepare(`
          INSERT INTO reports(
            incident_id,unit_id,author_id,narrative,alarmed_at,departed_at,arrived_at,
            ended_at,incident_type,classification
          ) VALUES(?,?,?,?,?,?,?,?,?,?)`).run(
            match[1], unitId, user.id, required(data.narrative, 'Bericht'),
            details.alarmedAt, details.departedAt, details.arrivedAt, details.endedAt,
            details.incidentType, details.classification);
        const summary = replaceCrew(result.lastInsertRowid, Number(match[1]), unitId, data.crew || [], user.organization_id);
        db.prepare('UPDATE reports SET vehicles=?,personnel=? WHERE id=?')
          .run(summary.vehicles, summary.personnel, result.lastInsertRowid);
        db.exec('COMMIT');
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
      json(res, 201, { id: Number(result.lastInsertRowid) });
    }),
    route('PUT', /^\/api\/reports\/(\d+)$/, async (req, res, match, user) => {
      const report = sql.report.get(match[1], user.organization_id);
      if (!report) throw Object.assign(new Error('Bericht nicht gefunden'), { status: 404 });
      const mayEdit = report.status === 'draft' &&
        (report.author_id === user.id || (user.role === 'einheitsleitung' && user.unitIds.includes(report.unit_id)));
      if (!mayEdit) throw Object.assign(new Error('Der Bericht kann nicht bearbeitet werden'), { status: 403 });
      const data = await body(req);
      db.exec('BEGIN');
      try {
        const incident = sql.incident.get(report.incident_id, user.organization_id);
        const details = reportDetails(data, incident);
        const summary = replaceCrew(report.id, report.incident_id, report.unit_id, data.crew || [], user.organization_id);
        db.prepare(`UPDATE reports SET narrative=?,vehicles=?,personnel=?,alarmed_at=?,
          departed_at=?,arrived_at=?,ended_at=?,incident_type=?,classification=?,
          updated_at=CURRENT_TIMESTAMP WHERE id=?`).run(
            required(data.narrative, 'Bericht'), summary.vehicles, summary.personnel,
            details.alarmedAt, details.departedAt, details.arrivedAt, details.endedAt,
            details.incidentType, details.classification, report.id);
        db.exec('COMMIT');
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
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
      const [alarmsRes, unitRes] = await Promise.all([
        fetchImpl(`https://app.divera247.com/api/v2/alarms?accesskey=${key}`, { method: 'GET' }),
        fetchImpl(`https://app.divera247.com/api/v2/pull/all?accesskey=${key}`, { method: 'GET' })
      ]);
      if (!alarmsRes.ok || !unitRes.ok) throw Object.assign(new Error('DIVERA-Abfrage fehlgeschlagen'), { status: 502 });
      const [alarmsRaw, unitRaw] = await Promise.all([alarmsRes.json(), unitRes.json()]);
      const array = value => Array.isArray(value) ? value : Object.values(value || {});
      const ownVehicles = new Map(Object.entries(unitRaw.data?.cluster?.vehicle || {})
        .map(([id, vehicle]) => [String(vehicle.id || id), vehicle]));
      const vehicles = [...ownVehicles.entries()].map(([id, vehicle]) => ({
        id,
        name: vehicle.name || vehicle.shortname || id,
        shortname: String(vehicle.shortname || ''),
        fullname: String(vehicle.fullname || ''),
        own: true
      }));
      const alarms = array(alarmsRaw.data?.items || alarmsRaw.data || alarmsRaw.items || alarmsRaw).map(a => {
        const assigned = a.vehicles || a.vehicle_ids || a.vehicle || [];
        const ids = Array.isArray(assigned) ? assigned
          : typeof assigned === 'object' ? Object.keys(assigned) : String(assigned).split(',');
        const diveraDate = finiteNumber(a.date, 'Alarmierungszeit');
        return {
          id: String(a.id || a.cluster_id || a.number || ''),
          foreignId: String(a.foreign_id || ''),
          date: diveraDate,
          title: a.title || a.text || a.type || 'Einsatz',
          startedAt: isoDate(a.date ?? a.ts_create ?? a.created_at),
          text: String(a.text || ''),
          address: a.address || a.location || '',
          lat: finiteNumber(a.lat, 'Breitengrad'),
          lng: finiteNumber(a.lng ?? a.long, 'Längengrad'),
          remark: String(a.remark || ''),
          patient: String(a.patient || ''),
          caller: String(a.caller || ''),
          vehicles: ids.map(id => {
            const vehicleId = String(id).trim();
            const ownVehicle = ownVehicles.get(vehicleId);
            return {
            id: vehicleId,
            name: ownVehicle?.name || ownVehicle?.shortname || vehicleId,
            shortname: String(ownVehicle?.shortname || ''),
            fullname: String(ownVehicle?.fullname || ''),
            own: Boolean(ownVehicle)
          }}).filter(vehicle => vehicle.id)
        };
      });
      json(res, 200, { alarms, vehicles });
    }),
    route('POST', /^\/api\/units\/(\d+)\/divera\/members\/sync$/, async (_req, res, match, user) => {
      assertRole(user, 'wehrleitung', 'einheitsleitung');
      assertOwnUnit(user, match[1]);
      const unit = sql.unit.get(match[1], user.organization_id);
      if (!unit?.divera_access_key) throw Object.assign(new Error('DIVERA ist nicht konfiguriert'), { status: 400 });
      const response = await fetchImpl(
        `https://app.divera247.com/api/v2/pull/all?accesskey=${encodeURIComponent(unit.divera_access_key)}`,
        { method: 'GET' });
      if (!response.ok) throw Object.assign(new Error('DIVERA-Mitgliederabgleich fehlgeschlagen'), { status: 502 });
      const cluster = (await response.json()).data?.cluster || {};
      const consumers = cluster.consumer || {};
      const qualifications = new Map();
      let count = 0;
      db.exec('BEGIN');
      try {
        for (const [externalId, qualification] of Object.entries(cluster.qualification || {})) {
          const diveraId = String(qualification.id || externalId);
          const saved = db.prepare(`
            INSERT INTO qualifications(unit_id,divera_id,name,shortname) VALUES(?,?,?,?)
            ON CONFLICT(unit_id,divera_id) DO UPDATE SET name=excluded.name,shortname=excluded.shortname
            RETURNING id`).get(unit.id, diveraId, required(qualification.name, 'Qualifikation', 200),
              optional(qualification.shortname, 'Qualifikationskürzel', 100));
          qualifications.set(diveraId, saved.id);
        }
        for (const [externalId, consumer] of Object.entries(consumers)) {
          const diveraId = String(consumer.id || externalId).trim();
          const name = String(consumer.stdformat_name ||
            `${consumer.firstname || ''} ${consumer.lastname || ''}`).trim();
          if (!diveraId || !name) continue;
          const member = db.prepare(`
            INSERT INTO members(organization_id,divera_id,name) VALUES(?,?,?)
            ON CONFLICT(organization_id,divera_id) DO UPDATE SET name=excluded.name
            RETURNING id`).get(user.organization_id, diveraId, name);
          db.prepare('INSERT OR IGNORE INTO member_units(member_id,unit_id) VALUES(?,?)').run(member.id, unit.id);
          db.prepare(`DELETE FROM member_qualifications WHERE member_id=? AND qualification_id IN
            (SELECT id FROM qualifications WHERE unit_id=?)`).run(member.id, unit.id);
          const addQualification = db.prepare(
            'INSERT OR IGNORE INTO member_qualifications(member_id,qualification_id) VALUES(?,?)');
          for (const qualificationId of consumer.qualifications || []) {
            const localId = qualifications.get(String(qualificationId));
            if (localId) addQualification.run(member.id, localId);
          }
          count++;
        }
        db.exec('COMMIT');
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
      json(res, 200, { count });
    }),
    route('POST', /^\/api\/units\/(\d+)\/divera\/import$/, async (req, res, match, user) => {
      assertRole(user, 'wehrleitung', 'einheitsleitung');
      assertOwnUnit(user, match[1]);
      const unit = sql.unit.get(match[1], user.organization_id);
      if (!unit) throw Object.assign(new Error('Einheit nicht gefunden'), { status: 404 });
      const data = await body(req);
      const diveraId = required(data.id, 'DIVERA-ID', 200);
      const diveraDate = finiteNumber(data.date, 'Alarmierungszeit');
      const incidentId = Number(db.prepare(`
        INSERT INTO incidents(
          organization_id,divera_id,foreign_id,divera_date,title,started_at,message,address,
          lat,lng,remark,patient,caller
        ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(organization_id,divera_id) DO UPDATE SET
          foreign_id=excluded.foreign_id,divera_date=excluded.divera_date,title=excluded.title,
          started_at=excluded.started_at,message=excluded.message,address=excluded.address,
          lat=excluded.lat,lng=excluded.lng,remark=excluded.remark,
          patient=excluded.patient,caller=excluded.caller
        RETURNING id`).get(user.organization_id, diveraId,
          optional(data.foreignId, 'Einsatznummer', 200), diveraDate,
          required(data.title, 'Stichwort', 300), required(data.startedAt, 'Zeitpunkt', 100),
          optional(data.text, 'Meldung'), optional(data.address, 'Adresse', 500),
          finiteNumber(data.lat, 'Breitengrad'), finiteNumber(data.lng, 'Längengrad'),
          optional(data.remark, 'Bemerkung'), optional(data.patient, 'Patient'),
          optional(data.caller, 'Meldende Person')).id);
      db.prepare(`INSERT INTO incident_units(incident_id,unit_id,vehicles) VALUES(?,?,?)
        ON CONFLICT(incident_id,unit_id) DO UPDATE SET vehicles=excluded.vehicles`)
        .run(incidentId, unit.id, JSON.stringify(vehicleSnapshots(data.vehicles || [])));
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
