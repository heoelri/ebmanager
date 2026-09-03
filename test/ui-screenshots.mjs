import fs from 'node:fs/promises';
import {chromium} from 'playwright';

const baseUrl = process.env.SCREENSHOT_BASE_URL || 'https://localhost:8443';
const output = 'screenshots';
await fs.mkdir(output, {recursive: true});

const browser = await chromium.launch();
const context = await browser.newContext({
  ignoreHTTPSErrors: true,
  viewport: {width: 1440, height: 1000},
  colorScheme: 'light'
});
const page = await context.newPage();

try {
  await page.goto(baseUrl, {waitUntil: 'networkidle'});
  await page.getByRole('heading', {name: 'Anmelden'}).waitFor();
  await page.screenshot({path: `${output}/01-anmeldung.png`, fullPage: true});

  await page.getByLabel('E-Mail').fill('wehrleitung@demo.local');
  await page.getByLabel('Passwort').fill('Demo-Feuerwehr-2026!');
  await page.getByRole('button', {name: 'Anmelden'}).click();
  await page.getByRole('heading', {name: 'Freiwillige Feuerwehr Amt Keppel'}).waitFor();
  await page.screenshot({path: `${output}/02-einsaetze.png`, fullPage: true});

  await page.goto(`${baseUrl}/?view=resources`, {waitUntil: 'networkidle'});
  await page.getByRole('heading', {name: 'Mitglieder & Fahrzeuge'}).waitFor();
  await page.screenshot({path: `${output}/03-mitglieder-fahrzeuge.png`, fullPage: true});
} finally {
  await browser.close();
}
