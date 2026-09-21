import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

export function summarizePhp(samples) {
  assert(samples.length > 0, 'Keine PHP-Coverage gemessen');
  const files = {};
  for (const sample of samples) {
    for (const [file, lines] of Object.entries(sample)) {
      assert(['api.php', 'support.php', 'constants.php'].includes(file), `Unerwartete Coverage-Datei: ${file}`);
      const merged = files[file] ??= {};
      for (const [line, hit] of Object.entries(lines)) {
        assert(/^[1-9]\d*$/.test(line) &&
          Number.isInteger(hit) && (hit > 0 || hit === -1 || hit === -2), 'Ungültige Xdebug-Zeile');
        merged[line] = Math.max(merged[line] ?? -2, hit);
      }
    }
  }
  for (const file of ['api.php', 'support.php', 'constants.php']) {
    assert(files[file], `Keine Coverage für ${file}`);
  }
  return Object.fromEntries(Object.entries(files).sort().map(([file, lines]) => {
    const executable = Object.entries(lines).filter(([, hit]) => hit !== -2);
    assert(executable.length > 0, `Keine ausführbaren Zeilen für ${file}`);
    const missingLines = executable.filter(([, hit]) => hit === -1).map(([line]) => Number(line));
    return [file, {executable: executable.length, reached: executable.length - missingLines.length, missingLines}];
  }));
}

export function summarizeBrowser(source, entries) {
  const names = [...source.matchAll(/^(?:async )?function (\w+)\(/gm)].map(match => match[1]);
  assert(names.length > 0, 'Keine benannten Top-Level-Funktionen gefunden');
  const scripts = entries.filter(entry => entry.source === source ||
    entry.source === source.replace(/start\(\)\.catch\(showError\);\s*$/, ''));
  assert(scripts.length > 0, 'Kein passendes app.js in der Browser-Coverage');
  const reached = new Set();
  for (const script of scripts) {
    for (const fn of script.functions) {
      if (names.includes(fn.functionName) && fn.ranges[0].count > 0) reached.add(fn.functionName);
    }
  }
  return {scripts: scripts.length, declared: names.length, reached: reached.size,
    missing: names.filter(name => !reached.has(name))};
}

export async function createBrowserCoverage() {
  const source = await fs.readFile('public/app.js', 'utf8');
  const groups = {backend: [], lifecycle: []};
  return {
    start: page => page.coverage.startJSCoverage({resetOnNavigation: false, reportAnonymousScripts: true}),
    async collect(page, group) {
      assert(Object.hasOwn(groups, group), 'Unbekannte Browser-Testgruppe');
      groups[group].push(...await page.coverage.stopJSCoverage());
    },
    async write(complete) {
      const report = {
        metric: 'Benannte Top-Level-Funktionen in public/app.js; keine Zeilen- oder Zweigabdeckung, ohne Node-Tests',
        complete,
        groups: Object.fromEntries(Object.entries(groups).map(([name, entries]) => [
          name, entries.length ? summarizeBrowser(source, entries) : null
        ])),
        combined: Object.values(groups).some(entries => entries.length)
          ? summarizeBrowser(source, Object.values(groups).flat()) : null
      };
      if (complete) assert(report.groups.backend && report.groups.lifecycle, 'Browser-Coverage unvollständig');
      await fs.mkdir('coverage', {recursive: true});
      await fs.writeFile('coverage/browser.json', JSON.stringify(report, null, 2));
      console.log(JSON.stringify(report, null, 2));
    }
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const directory = process.env.TEST_COVERAGE_DIR || 'coverage/php-raw';
  const files = (await fs.readdir(directory)).filter(file => /^request-[a-f0-9]+\.json$/.test(file)).sort();
  const samples = [];
  for (const file of files) samples.push(JSON.parse(await fs.readFile(path.join(directory, file), 'utf8')));
  const report = {
    metric: 'Ausführbare PHP-Zeilen der HTTP-Smoke-Requests; ohne direkte CLI-, Apache- und Browser-Aufrufe; keine Zweigabdeckung',
    requests: samples.length,
    files: summarizePhp(samples)
  };
  await fs.mkdir('coverage', {recursive: true});
  await fs.writeFile('coverage/php.json', JSON.stringify(report, null, 2));
  for (const [file, result] of Object.entries(report.files)) {
    console.log(`${file}: ${result.reached}/${result.executable} ausführbare Zeilen erreicht`);
  }
}
