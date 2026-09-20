import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {chromium} from 'playwright';

const baseUrl = process.env.SCREENSHOT_BASE_URL || 'https://localhost:8443';
const output = 'screenshots';
const password = 'Demo-Feuerwehr-2026!';
await fs.mkdir(output, {recursive: true});

const browser = await chromium.launch();
const contextOptions = {
  ignoreHTTPSErrors: true,
  viewport: {width: 1440, height: 1000},
  colorScheme: 'light',
  locale: 'de-DE',
  timezoneId: 'Europe/Berlin'
};

async function login(email) {
  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();
  await page.goto(baseUrl, {waitUntil: 'networkidle'});
  await page.getByLabel('E-Mail').fill(email);
  await page.getByLabel('Passwort').fill(password);
  await page.getByRole('button', {name: 'Anmelden'}).click();
  await page.getByRole('heading', {name: 'Freiwillige Feuerwehr Amt Keppel'}).waitFor();
  return {context, page};
}

async function captureView(page, prefix, name, view, heading, ready) {
  await page.goto(`${baseUrl}/?view=${view}`, {waitUntil: 'networkidle'});
  await page.getByRole('heading', {name: heading, exact: true}).waitFor();
  if (ready) await page.locator(ready).first().waitFor();
  await page.screenshot({path: `${output}/${prefix}-${name}.png`, fullPage: true});
}

async function captureIncident(page, prefix) {
  await page.goto(`${baseUrl}/?view=home`, {waitUntil: 'networkidle'});
  await page.getByLabel('Status filtern').selectOption('');
  await page.getByRole('button', {name: 'Öffnen'}).first().click();
  await page.waitForURL(/incident=\d+/);
  await page.getByRole('button', {name: '← Zurück'}).waitFor();
  await page.screenshot({path: `${output}/${prefix}-einsatzdetail.png`, fullPage: true});
}

async function checkIncidentFilter(page, prefix) {
  const filter = page.getByLabel('Status filtern');
  if (prefix !== '10-fuehrungskraft') {
    assert.equal(await filter.inputValue(), '');
    return;
  }
  assert.equal(await filter.inputValue(), 'report_required');
  const response = await page.request.get(`${baseUrl}/api/me`);
  assert(response.ok());
  const user = await response.json();
  const key = `incidentStatusFilter:${user.id}:fuehrungskraft`;
  for (const {previous, expected} of [
    {previous: '', expected: 'report_required'},
    {previous: 'submitted', expected: 'submitted'}
  ]) {
    await page.evaluate(({key, previous}) => {
      localStorage.removeItem(`${key}:v2`);
      localStorage.setItem(key, previous);
    }, {key, previous});
    await page.reload({waitUntil: 'networkidle'});
    assert.equal(await filter.inputValue(), expected);
    assert.equal(await page.locator(`[data-incident-status]:not([hidden]):not([data-incident-status="${expected}"])`).count(), 0);
  }
  await filter.selectOption('');
  await page.reload({waitUntil: 'networkidle'});
  assert.equal(await filter.inputValue(), '');
  assert.equal(await page.locator('[data-incident-status][hidden]').count(), 0);
  await filter.selectOption('report_required');
}

async function checkReportDates(page) {
  const response = await page.request.get(`${baseUrl}/api/incidents`);
  assert(response.ok());
  const incidents = await response.json();
  const incident = incidents.find(item => item.reportStatus.key === 'report_required');
  assert(incident, 'Demo-Einsatz ohne eigenen Bericht fehlt');
  await page.goto(`${baseUrl}/?incident=${incident.id}`, {waitUntil: 'networkidle'});
  const form = page.locator('#report');
  await form.waitFor();
  const alarm = await form.locator('[name=alarmedAt]').inputValue();
  const day = alarm.slice(0, 10);
  assert.equal(await form.locator('[name=reportDate]').inputValue(), day);
  for (const name of ['departedAt', 'arrivedAt', 'endedAt']) {
    assert.equal(await form.locator(`[name=${name}Date]`).inputValue(), day);
    assert.equal(await form.locator(`[name=${name}]`).inputValue(), '');
  }
  await form.locator('[name=departedAtDate]').fill('2027-01-02');
  await form.locator('[name=endedAt]').fill('12:30');
  await form.locator('[name=reportDate]').fill('2027-01-03');
  await form.locator('[name=reportDate]').blur();
  assert.equal(await form.locator('[name=departedAtDate]').inputValue(), '2027-01-02');
  assert.equal(await form.locator('[name=arrivedAtDate]').inputValue(), '2027-01-03');
  assert.equal(await form.locator('[name=endedAtDate]').inputValue(), '2027-01-03');
  assert.equal(await form.locator('[name=alarmedAt]').inputValue(), alarm);
  const payload = await form.evaluate(form => reportDetailsPayload(form));
  assert.equal(payload.departedAt, null);
  assert.equal(payload.arrivedAt, null);
  assert.equal(payload.endedAt, '2027-01-03T11:30:00.000Z');
  await form.locator('[name=endedAtDate]').fill('2027-01-04');
  assert.equal((await form.evaluate(form => reportDetailsPayload(form))).endedAt, '2027-01-04T11:30:00.000Z');
}

try {
  const loginContext = await browser.newContext(contextOptions);
  const loginPage = await loginContext.newPage();
  await loginPage.goto(baseUrl, {waitUntil: 'networkidle'});
  await loginPage.getByRole('heading', {name: 'Anmelden'}).waitFor();
  await loginPage.screenshot({path: `${output}/01-anmeldung.png`, fullPage: true});
  await loginContext.close();

  const roles = [
    {
      prefix: '10-fuehrungskraft',
      email: 'fuehrung.springer@demo.local',
      views: [
        ['einsaetze', 'home', 'Freiwillige Feuerwehr Amt Keppel', '#pendingDivera:not([hidden])'],
        ['mitglieder-fahrzeuge', 'resources', 'Mitglieder & Fahrzeuge', '#resources details'],
        ['divera', 'divera', 'DIVERA 24/7']
      ]
    },
    {
      prefix: '20-einheitsfuehrung',
      email: 'leitung.mitte@demo.local',
      views: [
        ['einsaetze', 'home', 'Freiwillige Feuerwehr Amt Keppel', '#pendingDivera:not([hidden])'],
        ['mitglieder-fahrzeuge', 'resources', 'Mitglieder & Fahrzeuge', '#resources details'],
        ['statistik', 'statistics', 'Statistik', '#statisticsResults .card'],
        ['divera', 'divera', 'DIVERA 24/7']
      ]
    },
    {
      prefix: '30-wehrfuehrung',
      email: 'wehrleitung@demo.local',
      views: [
        ['einsaetze', 'home', 'Freiwillige Feuerwehr Amt Keppel', '#pendingDivera:not([hidden])'],
        ['mitglieder-fahrzeuge', 'resources', 'Mitglieder & Fahrzeuge', '#resources details'],
        ['statistik', 'statistics', 'Statistik', '#statisticsResults .card'],
        ['verwaltung', 'admin', 'Verwaltung'],
        ['system', 'system', 'System'],
        ['divera', 'divera', 'DIVERA 24/7']
      ]
    }
  ];

  for (const role of roles) {
    const {context, page} = await login(role.email);
    await checkIncidentFilter(page, role.prefix);
    if (role.prefix === '10-fuehrungskraft') await checkReportDates(page);
    for (const [name, view, heading, ready] of role.views) {
      await captureView(page, role.prefix, name, view, heading, ready);
    }
    await captureIncident(page, role.prefix);
    await context.close();
  }
} finally {
  await browser.close();
}
