import assert from 'node:assert/strict';

export async function checkReportWorkflow({login, close, baseUrl}) {
  const sessions = [];
  async function signIn(email) {
    const session = await login(email);
    sessions.push(session);
    return session.page;
  }
  async function json(page, path) {
    const response = await page.request.get(`${baseUrl}/api/${path}`);
    assert.equal(response.status(), 200, path);
    return response.json();
  }
  async function write(page, method, path, action, status = 200) {
    const [response] = await Promise.all([
      page.waitForResponse(response => response.request().method() === method &&
        new URL(response.url()).pathname === `/api/${path}`),
      action()
    ]);
    assert.equal(response.status(), status, `${method} ${path}: ${await response.text()}`);
    return response.json();
  }
  try {
    const author = await signIn('fuehrung.mitte@demo.local');
    const title = `Browser-Berichtsworkflow ${Date.now()}`;
    await author.getByText('Einsatz anlegen', {exact: true}).click();
    const incidentForm = author.locator('#incident');
    await incidentForm.getByLabel('Stichwort').fill(title);
    await incidentForm.getByLabel('Zeitpunkt').fill('2026-09-21T10:00');
    await incidentForm.getByText('Einheiten auswählen', {exact: true}).click();
    await incidentForm.getByLabel('Löschzug Mitte', {exact: true}).check();
    const {id} = await write(author, 'POST', 'incidents',
      () => incidentForm.getByRole('button', {name: 'Anlegen', exact: true}).click(), 201);
    const url = `${baseUrl}/?incident=${id}`;
    const open = async page => {
      await page.goto(url, {waitUntil: 'networkidle'});
      await page.getByRole('heading', {name: title, exact: true}).waitFor();
    };
    await open(author);
    const form = author.locator('#report');
    await form.getByLabel('Laufende Nummer').fill(`E2E-${id}`);
    await form.locator('[name=departedAt]').fill('10:05');
    await form.locator('[name=arrivedAt]').fill('10:10');
    await form.locator('[name=endedAt]').fill('11:00');
    await form.getByLabel('Einsatzart').selectOption({index: 1});
    await form.getByLabel('Einsatzverlauf').fill('Erster Browserbericht');
    const {id: reportId} = await write(author, 'POST', `incidents/${id}/reports`,
      () => form.getByRole('button', {name: 'Speichern', exact: true}).click(), 201);
    await author.getByRole('button', {name: 'Bearbeiten', exact: true}).waitFor();

    async function report(page, status, narrative) {
      const reports = await json(page, `incidents/${id}/reports`);
      assert.equal(reports.length, 1);
      const value = reports[0];
      assert.equal(value.id, reportId);
      assert.equal(value.status, status);
      assert.equal(value.narrative, narrative);
      await page.getByText(narrative, {exact: true}).waitFor();
      assert.equal(value.running_number, `E2E-${id}`);
      assert.equal(value.alarmed_at, '2026-09-21T08:00:00.000Z');
      assert.equal(value.departed_at, '2026-09-21T08:05:00.000Z');
      assert.equal(value.arrived_at, '2026-09-21T08:10:00.000Z');
      assert.equal(value.ended_at, '2026-09-21T09:00:00.000Z');
      return value;
    }
    async function edit(page, text) {
      await page.getByRole('button', {name: 'Bearbeiten', exact: true}).click();
      const editForm = page.locator('#edit');
      await editForm.getByLabel('Einsatzverlauf').fill(text);
      await write(page, 'PUT', `reports/${reportId}`,
        () => editForm.getByRole('button', {name: 'Speichern', exact: true}).click());
      await page.locator('#dialog').waitFor({state: 'hidden'});
      await page.getByRole('button', {name: 'Bearbeiten', exact: true}).waitFor();
    }
    async function submit(page, action, label) {
      await write(page, 'POST', `reports/${reportId}/${action}`,
        () => page.getByRole('button', {name: label, exact: true}).click());
      await page.getByRole('button', {name: label, exact: true}).waitFor({state: 'hidden'});
      assert.equal(await page.getByRole('button', {name: 'Bearbeiten', exact: true}).count(), 0);
    }
    async function returnReport(page, action, label, comment) {
      await page.getByRole('button', {name: label, exact: true}).click();
      const returnForm = page.locator('#returnReport');
      await returnForm.getByLabel('Kommentar').fill(comment);
      await write(page, 'POST', `reports/${reportId}/${action}`,
        () => returnForm.getByRole('button', {name: 'Zurückgeben', exact: true}).click());
      await page.locator('#dialog').waitFor({state: 'hidden'});
      await page.getByRole('button', {name: label, exact: true}).waitFor({state: 'hidden'});
    }
    await open(author);
    const initial = await report(author, 'author_draft', 'Erster Browserbericht');
    await edit(author, 'Bearbeiteter Browserbericht');
    await open(author);
    const edited = await report(author, 'author_draft', 'Bearbeiteter Browserbericht');
    assert.equal(edited.revision, initial.revision + 1);
    await submit(author, 'submit-to-unit', 'An Einheitsführung senden');
    await author.getByText(/Der Einsatzbericht ist für Sie jetzt nur noch lesbar/).waitFor();

    const leader = await signIn('leitung.mitte@demo.local');
    await open(leader);
    await report(leader, 'unit_review', 'Bearbeiteter Browserbericht');
    await returnReport(leader, 'return-to-author', 'An Führungskraft zurückgeben', 'Bitte Verlauf ergänzen.');
    await open(author);
    await edit(author, 'Ergänzter Browserbericht');
    await submit(author, 'submit-to-unit', 'An Einheitsführung senden');
    await open(leader);
    await submit(leader, 'submit-to-command', 'An Wehrführung senden');

    const command = await signIn('wehrleitung@demo.local');
    await open(command);
    await report(command, 'wehr_review', 'Ergänzter Browserbericht');
    async function consolidate(text) {
      const form = command.locator('#consolidate');
      await form.getByLabel('Konsolidierter Bericht').fill(text);
      await write(command, 'PUT', `incidents/${id}/consolidation`,
        () => form.getByRole('button', {name: 'Speichern', exact: true}).click());
      await command.getByRole('button', {name: 'Gesamtbericht als PDF', exact: true}).waitFor();
      await open(command);
      assert.equal(await command.getByLabel('Konsolidierter Bericht').inputValue(), text);
      const incident = (await json(command, 'incidents')).find(item => item.id === id);
      assert(incident.consolidated_at);
      assert.equal(incident.consolidated_text, text);
    }
    await consolidate('Erster Gesamtbericht aus dem Browser');
    await returnReport(command, 'return-to-unit', 'An Einheitsführung zurückgeben', 'Bitte abschließend prüfen.');
    await open(command);
    const returned = (await json(command, 'incidents')).find(item => item.id === id);
    assert.equal(returned.consolidated_at, null);
    assert.equal(returned.consolidated_text, 'Erster Gesamtbericht aus dem Browser');
    assert.equal(await command.locator('#consolidate').count(), 0);
    await open(leader);
    await edit(leader, 'Abschließend geprüfter Browserbericht');
    await submit(leader, 'submit-to-command', 'An Wehrführung senden');
    await open(command);
    const final = await report(command, 'wehr_review', 'Abschließend geprüfter Browserbericht');
    assert.deepEqual(final.history.map(item => item.to_status),
      ['author_draft', 'unit_review', 'author_draft', 'unit_review', 'wehr_review', 'unit_review', 'wehr_review']);
    assert(final.history.some(item => item.comment === 'Bitte Verlauf ergänzen.'));
    assert(final.history.some(item => item.comment === 'Bitte abschließend prüfen.'));
    await consolidate('Abgeschlossener Gesamtbericht aus dem Browser');

    // Der echte Browser entfernt das sichere Cookie; dessen Wiederverwendung bleibt serverseitig unwirksam.
    const cookie = (await author.context().cookies()).find(item => item.name === '__Host-session');
    assert(cookie?.secure && cookie.httpOnly && cookie.sameSite === 'Strict');
    await write(author, 'POST', 'logout',
      () => author.getByRole('button', {name: 'Abmelden', exact: true}).click());
    await author.getByRole('heading', {name: 'Anmelden', exact: true}).waitFor();
    assert(!(await author.context().cookies()).some(item => item.name === '__Host-session'));
    const replay = await author.request.get(`${baseUrl}/api/me`, {headers: {Cookie: `${cookie.name}=${cookie.value}`}});
    assert.equal(replay.status(), 401);
    assert.equal((await leader.request.get(`${baseUrl}/api/me`)).status(), 200);
  } finally {
    for (const session of sessions) await close(session);
  }
}
