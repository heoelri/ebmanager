import fs from 'node:fs/promises';
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
  await page.getByRole('button', {name: 'Öffnen'}).first().click();
  await page.waitForURL(/incident=\d+/);
  await page.getByRole('button', {name: '← Zurück'}).waitFor();
  await page.screenshot({path: `${output}/${prefix}-einsatzdetail.png`, fullPage: true});
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
        ['verwaltung', 'admin', 'Verwaltung'],
        ['system', 'system', 'System'],
        ['divera', 'divera', 'DIVERA 24/7']
      ]
    }
  ];

  for (const role of roles) {
    const {context, page} = await login(role.email);
    for (const [name, view, heading, ready] of role.views) {
      await captureView(page, role.prefix, name, view, heading, ready);
    }
    await captureIncident(page, role.prefix);
    await context.close();
  }
} finally {
  await browser.close();
}
