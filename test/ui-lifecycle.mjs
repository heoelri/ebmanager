import assert from 'node:assert/strict';
import fs from 'node:fs/promises';

export async function checkUiLifecycle(browser, coverage) {
  const source = (await fs.readFile('public/app.js', 'utf8')).replace(/start\(\)\.catch\(showError\);\s*$/, '');
  const units = [{id: 1, name: 'Mitte'}, {id: 2, name: 'Nord'}];
  const incidents = [1, 2].map(id => ({
    id, title: `Einsatz ${id}`, revision: 4, started_at: '2026-08-22T18:00:00.000Z',
    is_exercise: false, lat: null, lng: null, assignments: [
      {unitId: 1, hasReport: id === 2, vehicles: [{name: 'LF', own: true}]},
      ...(id === 1 ? [{unitId: 2, hasReport: false, vehicles: []}] : [])
    ], reportStatus: {key: 'report_required', label: 'Bericht erforderlich'}
  }));
  const reports = [{id: 9, revision: 3, unit_id: 1, incident_id: 2, status: 'wehr_review',
    history: [], crew: [], narrative: 'Gespeichert', classification: {}, incident_command: {},
    damaged_party: {}, damaging_party: {}, additionalVehicles: []}];

  async function open() {
    const context = await browser.newContext({locale: 'de-DE', timezoneId: 'Europe/Berlin'});
    const page = await context.newPage(), errors = [], calls = [], handlers = new Map();
    await coverage.start(page);
    page.on('pageerror', error => errors.push(error.message));
    await page.route('https://app.test/', route => route.fulfill({
      contentType: 'text/html',
      body: '<nav id="nav"></nav><main id="app"></main><dialog id="dialog"></dialog><div id="announcer" role="status"></div>'
    }));
    await page.route('**/api/**', async route => {
      const path = new URL(route.request().url()).pathname, method = route.request().method();
      calls.push({path, method, data: route.request().postDataJSON()});
      const handler = handlers.get(`${method} ${path}`) || handlers.get(path);
      if (handler) return handler(route);
      let json = {};
      if (path === '/api/units') json = units;
      else if (path === '/api/incidents') json = incidents;
      else if (path === '/api/options') json = {incidentTypes: ['Technische Hilfe'], ranks: {}, classifications: {site: ['Wald']}, classificationLabels: {site: 'Einsatzstelle'}};
      else if (path.endsWith('/resources')) json = {members: [{id: 1, name: 'Mitglied', active: 1}], vehicles: [{name: 'Zusatzfahrzeug'}]};
      else if (path.endsWith('/reports')) json = path.includes('/2/') ? reports : [];
      else if (path.endsWith('/exercise-history')) json = [];
      else if (path === '/api/users') json = [];
      else if (path === '/api/system') json = {application: {}, database: {}, email: {}, units: [], users: []};
      else if (path.endsWith('/divera')) json = {alarms: [{id: 'alarm', title: 'DIVERA-Test', address: '', vehicles: []}]};
      await route.fulfill({json});
    });
    await page.goto('https://app.test/');
    await page.addScriptTag({content: source});
    await page.evaluate(async () => {
      me = {id: 1, role: 'wehrleitung', unitIds: [1, 2], name: 'Test', organization_name: 'Testwehr'};
      await load();
      window.uiOperations = [];
      const track = handler => (...args) => {
        const result = handler(...args);
        uiOperations.push(result);
        return result;
      };
      pullDivera = track(pullDivera);
      importDivera = track(importDivera);
      syncDivera = track(syncDivera);
      loadReportCrew = track(loadReportCrew);
      renderResources = track(renderResources);
      renderStatistics = track(renderStatistics);
      const bind = bindForm;
      bindForm = (selector, handler) => bind(selector, track(handler));
    });
    function hold(path) {
      let release, seen;
      const waiting = new Promise(resolve => {release = resolve;});
      const received = new Promise(resolve => {seen = resolve;});
      handlers.set(path, async route => {seen(); await route.fulfill(await waiting);});
      return {received, release};
    }
    async function settle() {
      await page.evaluate(() => Promise.allSettled(uiOperations));
    }
    async function close() {
      await settle();
      assert.deepEqual(errors, [], 'Keine unbehandelten Promise-Ablehnungen');
      await coverage.collect(page, 'lifecycle');
      await context.close();
    }
    return {page, calls, handlers, hold, settle, close};
  }

  // Alte Ansichten dürfen weder DOM, URL, Fokus noch Fehlermeldungen einer neueren Navigation ändern.
  for (const [view, path] of [['incident', '/api/incidents/1/reports'], ['admin', '/api/users'], ['system', '/api/system']]) {
    for (const failed of [false, true]) {
      const test = await open(), {page} = test, old = test.hold(path);
      const pending = page.evaluate(view => navigate(view, 1), view);
      await old.received;
      await page.evaluate(() => navigate('resources'));
      await page.locator('#resourceUnit').focus();
      old.release(failed ? {status: 503, json: {error: 'Veralteter Fehler'}} : {json: []});
      await pending;
      assert.match(page.url(), /\?view=resources$/);
      assert.equal(await page.locator('h1').textContent(), 'Mitglieder & Fahrzeuge');
      assert.equal(await page.locator('#resourceUnit').evaluate(node => node === document.activeElement), true);
      assert.equal(await page.getByRole('alert').count(), 0);
      await test.close();
    }
  }

  // Auch zwei Einsätze in umgekehrter Antwortreihenfolge bleiben beim zuletzt gewählten Einsatz.
  {
    const test = await open(), {page} = test, old = test.hold('/api/incidents/1/reports');
    const pending = page.evaluate(() => navigate('incident', 1));
    await old.received;
    await page.evaluate(() => navigate('incident', 2));
    old.release({json: []});
    await pending;
    assert.match(page.url(), /\?incident=2$/);
    assert.equal(await page.locator('h1').textContent(), 'Einsatz 2');
    await test.close();
  }

  // Übungsänderungen bewahren dieselben Formular- und Besatzungsknoten; nur die eigene Einsatzrevision steigt.
  for (const id of [1, 2]) {
    const test = await open(), {page, calls, handlers} = test;
    await page.evaluate(id => navigate('incident', id), id);
    const before = await page.evaluate(id => {
      const form = document.querySelector(id === 1 ? '#report' : '#consolidate');
      window.savedForm = form;
      if (id === 1) {
        form.elements.narrative.value = 'Ungespeicherter Verlauf';
        form.elements.damagedName.value = 'Ungespeicherter Kontakt';
        form.querySelector('[data-classification]').checked = true;
        const crew = form.querySelector('[data-member]');
        crew.value = 'none';
        crew.dispatchEvent(new Event('change'));
      } else form.elements.text.value = 'Ungespeicherter Gesamttext';
      return Object.fromEntries(new FormData(form));
    }, id);
    await page.getByRole('button', {name: 'Als Übung markieren', exact: true}).click();
    await page.getByRole('button', {name: 'Übungskennzeichnung entfernen', exact: true}).waitFor();
    await page.waitForFunction(() => !document.querySelector('[data-action=toggleExercise]').disabled);
    assert.deepEqual(await page.evaluate(() => Object.fromEntries(new FormData(savedForm))), before);
    assert.equal(await page.evaluate(() => savedForm.isConnected), true);
    assert.equal(await page.evaluate(() => currentIncident.revision), 5);
    assert.equal(calls.filter(call => call.path === '/api/incidents').length, 1);
    if (id === 1) {
      assert.deepEqual(await page.evaluate(() => selectedCrew('#reportCrew')), [{memberId: 1, name: 'Mitglied', vehicle: '', role: 'besatzung'}]);
      const requests = calls.filter(call => call.path.endsWith('/resources')).length;
      await page.locator('[data-additional-vehicle]').check();
      assert.equal(await page.locator('[data-additional-vehicle]').evaluate(input => input === document.activeElement), true);
      await page.locator('[data-member]').selectOption('vehicle-1-besatzung');
      assert.equal(calls.filter(call => call.path.endsWith('/resources')).length, requests, 'Zusatzfahrzeuge verwenden bereits geladene Ressourcen ohne Antwort-Rennen');
      assert.equal((await page.evaluate(() => selectedCrew('#reportCrew')))[0].vehicle, 'Zusatzfahrzeug');
      const slow = test.hold('/api/units/2/resources');
      await page.locator('#reportUnit').selectOption('2');
      await slow.received;
      assert.equal(await page.locator('#reportCrew').evaluate(root => root.inert), true);
      assert.equal(await page.locator('#report button[type=submit]').isDisabled(), true);
      slow.release({json: {members: [], vehicles: []}});
      await page.waitForFunction(() => !document.querySelector('#reportCrew').inert);
    } else {
      handlers.set('PUT /api/incidents/2/consolidation', route => route.fulfill({status: 409, json: {error: 'Stand veraltet'}}));
      await page.locator('#consolidate button').click();
      await page.getByRole('alert').waitFor();
      const write = calls.find(call => call.path.endsWith('/consolidation'));
      assert.equal(write.data.revision, 5);
      assert.deepEqual(write.data.reportVersions, [{id: 9, revision: 3}]);
      assert.equal(await page.locator('#consolidate textarea').inputValue(), 'Ungespeicherter Gesamttext');
    }
    await test.close();
  }

  // Ein Einheitenwechsel erlaubt keinen zweiten DIVERA-Schreibvorgang, solange der erste noch läuft.
  {
    const test = await open(), {page, calls} = test;
    await page.evaluate(() => navigate('divera'));
    await page.getByRole('button', {name: 'Einsätze abrufen', exact: true}).click();
    const firstImport = test.hold('POST /api/units/1/divera/import');
    await page.getByRole('button', {name: 'Importieren', exact: true}).click();
    await firstImport.received;
    await page.locator('#pullUnit').selectOption('2');
    await page.locator('#pullUnit').selectOption('1');
    await page.getByRole('button', {name: 'Einsätze abrufen', exact: true}).click();
    await page.getByRole('button', {name: 'Importieren', exact: true}).click();
    assert.equal(calls.filter(call => call.path.endsWith('/import')).length, 1);
    firstImport.release({json: {id: 5}});
    await test.settle();
    await test.close();
  }

  // Einheitenwechsel entwertet alte DIVERA-Antworten; ein fehlgeschlagener Import bleibt ausdrücklich wiederholbar.
  {
    const test = await open(), {page, calls} = test;
    await page.evaluate(() => navigate('divera'));
    const old = test.hold('/api/units/1/divera');
    await page.getByRole('button', {name: 'Einsätze abrufen', exact: true}).click();
    await old.received;
    await page.locator('#pullUnit').selectOption('2');
    await page.getByRole('button', {name: 'Einsätze abrufen', exact: true}).click();
    await page.getByRole('button', {name: 'Importieren', exact: true}).waitFor();
    old.release({status: 503, json: {error: 'Falsche Einheit'}});
    const importRequest = test.hold('POST /api/units/2/divera/import');
    const button = page.getByRole('button', {name: 'Importieren', exact: true});
    await button.click();
    await importRequest.received;
    await page.locator('[data-import]').evaluate(button => button.onclick());
    assert.equal(calls.filter(call => call.path.endsWith('/import')).length, 1);
    importRequest.release({status: 503, json: {error: 'Import fehlgeschlagen'}});
    await page.getByRole('alert').filter({hasText: 'Import fehlgeschlagen'}).waitFor();
    assert.equal(await button.isEnabled(), true);
    test.handlers.set('POST /api/units/2/divera/import', route => route.fulfill({json: {id: 5, warning: 'Mailversand fehlgeschlagen'}}));
    await button.click();
    await page.getByRole('alert').filter({hasText: 'Mailversand fehlgeschlagen'}).waitFor();
    await test.settle();
    assert.equal(await page.getByRole('button', {name: 'Bereits importiert'}).isDisabled(), true);
    assert.doesNotMatch(await page.locator('#diveraResults').textContent(), /Falsche Einheit/);
    await test.close();
  }

  // Teilerfolg samt Warnung ist vor dem Nachladen sichtbar und wandert nicht in eine andere Ansicht.
  {
    const test = await open(), {page, handlers} = test;
    await page.evaluate(() => navigate('divera'));
    handlers.set('POST /api/units/1/divera/sync', route => route.fulfill({json: {
      members: 2, qualifications: 3, vehicles: 4, incidentsCreated: 1, incidentsUpdated: 0, incidentsUnchanged: 0,
      warning: 'Mailversand fehlgeschlagen'
    }}));
    const refresh = test.hold('/api/incidents');
    await page.getByRole('button', {name: 'Alles synchronisieren', exact: true}).click();
    await refresh.received;
    assert.match(await page.locator('#diveraResults').textContent(), /2 Mitglieder.*1 Einsätze neu importiert/);
    assert.match(await page.getByRole('alert').textContent(), /Mailversand fehlgeschlagen/);
    await page.evaluate(() => navigate('resources'));
    refresh.release({json: incidents});
    await test.settle();
    assert.equal(await page.getByRole('alert').count(), 0);
    assert.doesNotMatch(await page.locator('#announcer').textContent(), /Mailversand fehlgeschlagen/);
    await test.close();
  }

  // Verlassene Formulare zeigen keine späten Schreibfehler und starten keinen anschließenden Neuaufbau.
  {
    const test = await open(), {page, calls} = test;
    await page.evaluate(() => navigate('admin'));
    const save = test.hold('POST /api/units');
    await page.locator('#unit input').fill('Neue Einheit');
    await page.locator('#unit button').click();
    await save.received;
    await page.evaluate(() => navigate('resources'));
    save.release({status: 503, json: {error: 'Später Schreibfehler'}});
    await test.settle();
    assert.equal(await page.locator('h1').textContent(), 'Mitglieder & Fahrzeuge');
    assert.equal(await page.getByRole('alert').count(), 0);
    assert.equal(calls.filter(call => call.method === 'GET' && call.path === '/api/users').length, 1);
    await test.close();
  }

  // Ein alter Ressourcenfehler darf nicht unter der inzwischen ausgewählten Einheit erscheinen.
  {
    const test = await open(), {page} = test, old = test.hold('/api/units/1/resources');
    await page.evaluate(() => navigate('resources'));
    await old.received;
    await page.locator('#resourceUnit').selectOption('2');
    await page.locator('#resources').getByText('Mitglied', {exact: true}).waitFor();
    old.release({status: 503, json: {error: 'Alte Ressourcenantwort'}});
    await test.settle();
    assert.equal(await page.getByRole('alert').count(), 0);
    assert.equal(await page.locator('#resourceUnit').inputValue(), '2');
    await test.close();
  }

  // Eine Antwort aus einem geschlossenen Dialog verändert keinen inzwischen neu geöffneten Dialog.
  {
    const test = await open(), {page} = test;
    await page.evaluate(() => navigate('incident', 2));
    const write = test.hold('POST /api/reports/9/return-to-unit');
    await page.getByRole('button', {name: 'An Einheitsführung zurückgeben', exact: true}).click();
    await page.locator('#returnReport textarea').fill('Erster Kommentar');
    await page.getByRole('button', {name: 'Zurückgeben', exact: true}).click();
    await write.received;
    await page.getByRole('button', {name: 'Abbrechen', exact: true}).click();
    await page.getByRole('button', {name: 'An Einheitsführung zurückgeben', exact: true}).click();
    await page.locator('#returnReport textarea').fill('Neuer Kommentar');
    write.release({status: 503, json: {error: 'Alter Dialogfehler'}});
    await test.settle();
    assert.equal(await page.locator('#dialog').evaluate(dialog => dialog.open), true);
    assert.equal(await page.locator('#returnReport textarea').inputValue(), 'Neuer Kommentar');
    assert.equal(await page.getByRole('alert').count(), 0);
    await test.close();
  }

  // Auch ohne ursprünglich offenen Dialog darf ein alter Refresh keinen neuen Dialog oder dessen Ansicht verändern.
  for (const path of ['/api/incidents', '/api/incidents/2/reports']) {
    for (const failed of [false, true]) {
      const test = await open(), {page} = test;
      await page.evaluate(() => navigate('incident', 2));
      const refresh = test.hold(path);
      const pending = page.evaluate(() => refreshIncident(2, {warning: 'Alte Refresh-Warnung'}));
      await refresh.received;
      await page.getByRole('button', {name: 'An Einheitsführung zurückgeben', exact: true}).click();
      await page.locator('#returnReport textarea').fill('Ungespeicherter neuer Kommentar');
      await page.evaluate(() => {
        window.headingBeforeRefresh = app.querySelector('h1');
        window.formBeforeRefresh = dialog.querySelector('form');
        announcer.textContent = 'Neuer Dialog';
      });
      refresh.release(failed ? {status: 503, json: {error: 'Alter Refresh-Fehler'}}
        : {json: path === '/api/incidents' ? incidents : reports});
      await pending;
      assert.equal(await page.evaluate(() => app.querySelector('h1') === headingBeforeRefresh), true);
      assert.equal(await page.evaluate(() => dialog.open && dialog.querySelector('form') === formBeforeRefresh), true);
      assert.equal(await page.locator('#returnReport textarea').inputValue(), 'Ungespeicherter neuer Kommentar');
      assert.equal(await page.locator('#returnReport textarea').evaluate(node => node === document.activeElement), true);
      assert.equal(await page.getByRole('alert').count(), 0);
      assert.equal(await page.locator('#announcer').textContent(), 'Neuer Dialog');
      await test.close();
    }
  }

  // Ein sichtbarer Dialogfehler verändert nicht die Formularidentität und erlaubt einen bewussten erneuten Versuch.
  {
    const test = await open(), {page, handlers, calls} = test;
    await page.evaluate(() => navigate('incident', 2));
    handlers.set('POST /api/reports/9/return-to-unit',
      route => route.fulfill({status: 503, json: {error: 'Speichern fehlgeschlagen'}}));
    await page.getByRole('button', {name: 'An Einheitsführung zurückgeben', exact: true}).click();
    await page.locator('#returnReport textarea').fill('Kommentar bleibt erhalten');
    await page.getByRole('button', {name: 'Zurückgeben', exact: true}).click();
    await page.getByRole('alert').filter({hasText: 'Speichern fehlgeschlagen'}).waitFor();
    await test.settle();
    assert.equal(await page.locator('#returnReport').getAttribute('aria-busy'), null);
    assert.equal(await page.getByRole('button', {name: 'Zurückgeben', exact: true}).isEnabled(), true);
    assert.equal(await page.locator('#returnReport textarea').inputValue(), 'Kommentar bleibt erhalten');
    handlers.set('POST /api/reports/9/return-to-unit', route => route.fulfill({json: {}}));
    await page.getByRole('button', {name: 'Zurückgeben', exact: true}).click();
    await test.settle();
    assert.equal(calls.filter(call => call.path === '/api/reports/9/return-to-unit').length, 2);
    assert.equal(await page.locator('#dialog').evaluate(dialog => dialog.open), false);
    await test.close();
  }

  // Nach erfolgreichem Schreiben und bewusstem Dialogschluss bleibt ein Nachladefehler in der Hauptansicht sichtbar.
  {
    const test = await open(), {page} = test;
    await page.evaluate(() => navigate('incident', 2));
    const refresh = test.hold('/api/incidents');
    await page.getByRole('button', {name: 'An Einheitsführung zurückgeben', exact: true}).click();
    await page.locator('#returnReport textarea').fill('Gespeicherter Kommentar');
    await page.getByRole('button', {name: 'Zurückgeben', exact: true}).click();
    await refresh.received;
    assert.equal(await page.locator('#dialog').evaluate(dialog => dialog.open), false);
    refresh.release({status: 503, json: {error: 'Nachladen fehlgeschlagen'}});
    await test.settle();
    assert.match(await page.locator('#app [role=alert]').textContent(), /Nachladen fehlgeschlagen/);
    assert.equal(await page.locator('#app [role=alert]').evaluate(node => node === document.activeElement), true);
    assert.notEqual(await page.locator('#announcer').textContent(), 'Wird verarbeitet');
    await test.close();
  }

  // Workflow-Mailwarnungen bleiben nach dem bewusst abgeschlossenen Dialog beim zugehörigen Einsatz sichtbar.
  {
    const test = await open(), {page, handlers} = test;
    await page.evaluate(() => navigate('incident', 2));
    handlers.set('POST /api/reports/9/return-to-unit', route => route.fulfill({json: {warning: 'Workflow-Mail fehlgeschlagen'}}));
    await page.getByRole('button', {name: 'An Einheitsführung zurückgeben', exact: true}).click();
    await page.locator('#returnReport textarea').fill('Bitte ergänzen');
    await page.getByRole('button', {name: 'Zurückgeben', exact: true}).click();
    await test.settle();
    assert.equal(await page.locator('#dialog').evaluate(dialog => dialog.open), false);
    assert.match(await page.getByRole('alert').textContent(), /Workflow-Mail fehlgeschlagen/);
    assert.equal(await page.locator('#announcer').textContent(), 'Workflow-Mail fehlgeschlagen');
    await test.close();
  }

  // Ein 409 bei der Übungsänderung lässt Formular, Kennzeichnung und geladene Revision unverändert.
  {
    const test = await open(), {page, handlers} = test;
    await page.evaluate(() => navigate('incident', 2));
    await page.locator('#consolidate textarea').fill('Offener Text');
    handlers.set('PUT /api/incidents/2/exercise', route => route.fulfill({status: 409, json: {error: 'Stand veraltet'}}));
    await page.getByRole('button', {name: 'Als Übung markieren', exact: true}).click();
    await page.getByRole('alert').waitFor();
    assert.equal(await page.locator('#consolidate textarea').inputValue(), 'Offener Text');
    assert.equal(await page.evaluate(() => currentIncident.revision), 4);
    assert.equal(await page.getByRole('button', {name: 'Als Übung markieren', exact: true}).isEnabled(), true);
    await test.close();
  }

  // Eine Synchronisationswarnung aus der alten Sitzung darf nach Abmelden und erneutem Anmelden nicht erscheinen.
  {
    const test = await open(), {page} = test;
    await page.evaluate(() => navigate('divera'));
    const sync = test.hold('POST /api/units/1/divera/sync');
    await page.getByRole('button', {name: 'Alles synchronisieren', exact: true}).click();
    await sync.received;
    await page.evaluate(() => logout());
    await page.getByRole('heading', {name: 'Anmelden', exact: true}).waitFor();
    await page.evaluate(async () => {
      me = {id: 2, role: 'wehrleitung', unitIds: [1, 2], name: 'Anderer Nutzer', organization_name: 'Testwehr'};
      await load();
      await navigate('resources');
    });
    sync.release({json: {warning: 'Warnung der vorherigen Sitzung'}});
    await test.settle();
    assert.equal(await page.getByRole('alert').count(), 0);
    assert.doesNotMatch(await page.locator('#announcer').textContent(), /vorherigen Sitzung/);
    await test.close();
  }
}
