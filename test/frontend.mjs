import assert from 'node:assert/strict';
import fs from 'node:fs';

const html = fs.readFileSync('public/index.html', 'utf8');
const source = html.match(/function rankOptions[\s\S]*?(?=\nfunction reportDetailsFields)/)?.[0];
assert(source, 'rankOptions fehlt');

const rankOptions = new Function('ranks', 'esc', `${source}; return rankOptions;`)(
  {BM: 'Brandmeister'},
  value => String(value)
);

assert.match(rankOptions('BM'), /value="BM" selected>BM – Brandmeister/);
assert.match(rankOptions('ALT'), /value="ALT" selected>ALT/);
assert.equal((rankOptions('ALT').match(/value="ALT"/g) ?? []).length, 1);

const reportFieldsSource = html.match(/function contactFields[\s\S]*?(?=\nfunction bindDuration)/)?.[0];
assert(reportFieldsSource, 'Berichtsdetails fehlen');
const {reportDetailsFields} = new Function(
  'esc', 'ranks', 'localDateTime', 'incidentTypes', 'reportClassifications', 'classificationLabels',
  `${reportFieldsSource}; return {reportDetailsFields};`
)(
  value => String(value ?? ''),
  {BM: 'Brandmeister', BI: 'Brandinspektor'},
  value => String(value ?? ''),
  ['Technische Hilfe'],
  {site: ['Wohngebäude'], cause: ['Unbekannt'], technical: ['Menschen in Notlage']},
  {site: 'Einsatzstelle', cause: 'Schadensursache', technical: 'Technische Hilfe'}
);
const reportFields = reportDetailsFields('edit', {
  foreign_id: 'E-42',
  divera_id: '42',
  started_at: '2026-08-22T18:00'
}, {
  running_number: '7/2026',
  damaged_party: '{"name":"Max","phone":"","address":""}',
  damaging_party: '{}',
  incident_command: '{"rank":"BI","name":"A","additionalRank":"BM","additionalName":"B"}',
  classification: '{"site":["Wohngebäude"],"cause":[],"technical":[]}'
});
assert.match(reportFields, /DIVERA-Einsatznummer<input value="E-42" readonly>/);
assert.doesNotMatch(reportFields, /DIVERA-Einsatznummer<input name=/);
assert.equal((reportFields.match(/class="command-row"/g) ?? []).length, 2);
assert(reportFields.indexOf('Gesamteinsatzleitung') < reportFields.indexOf('Einsatzleitung der Einheit'));
assert.equal((reportFields.match(/class="form-section" open/g) ?? []).length, 3);
assert.match(reportDetailsFields('new', {foreign_id: '', started_at: ''}), /DIVERA-Einsatznummer<input value="Nicht vorhanden" readonly>/);

const reportTimesSource = html.match(/function reportTimes[^\n]+/)?.[0];
assert(reportTimesSource, 'reportTimes fehlt');
const reportTimes = new Function(
  'formatDateTime', 'durationText',
  `${reportTimesSource}; return reportTimes;`
)(value => value || '–', () => '1 Std. 0 Min.');
const times = reportTimes({alarmed_at: 'a', departed_at: 'b', arrived_at: 'c', ended_at: 'd'});
assert.deepEqual([...times.matchAll(/<dt>([^<]+)<\/dt>/g)].map(match => match[1]), ['Alarmiert', 'Ausgerückt', 'Eingetroffen', 'Beendet', 'Dauer']);

const restoreFocusSource = html.match(/function restoreDialogFocus[^\n]+/)?.[0];
assert(restoreFocusSource, 'restoreDialogFocus fehlt');
let closeHandler;
let focusCount = 0;
const restoreDialogFocus = new Function('dialog', `${restoreFocusSource}; return restoreDialogFocus;`)({
  addEventListener: (event, handler, options) => {
    assert.equal(event, 'close');
    assert.deepEqual(options, {once: true});
    closeHandler = handler;
  }
});
restoreDialogFocus({isConnected: true, focus: () => focusCount++});
closeHandler();
assert.equal(focusCount, 1);

const editReportSource = html.match(/async function editReport[^\n]+/)?.[0];
assert(editReportSource, 'editReport fehlt');
assert.match(editReportSource, /<button type="submit" disabled>Speichern<\/button>/);
assert(editReportSource.indexOf("bindForm('#edit'") < editReportSource.indexOf("await loadReportCrew(form,'#editCrew'"));

const loadCrewSource = html.match(/async function loadReportCrew[^\n]+/)?.[0];
assert(loadCrewSource, 'loadReportCrew fehlt');
assert.match(loadCrewSource, /unitSelect\.disabled=true/);
assert.match(loadCrewSource, /form\.closest\('dialog'\)&&!dialog\.open/);
assert.match(loadCrewSource, /root\.dataset\.crewRequest!==request/);
assert.match(loadCrewSource, /unitSelect\?\.value\|\|unitId/);
assert.match(loadCrewSource, /Erneut laden/);

const initialViewSource = html.match(/async function initialView[\s\S]*?(?=\nasync function start)/)?.[0];
assert(initialViewSource, 'initialView fehlt');

let opened = 0;
let homeOpened = false;
const location = {search: '?incident=42'};
const initialView = new Function(
  'location', 'incidents', 'incident', 'home',
  `${initialViewSource}; return initialView;`
)(
  location,
  [{id: 42}],
  async id => { opened = id; },
  () => { homeOpened = true; }
);
await initialView();
assert.equal(opened, 42);
assert.equal(homeOpened, false);

location.search = '?incident=43';
await initialView();
assert.equal(opened, 42);
assert.equal(homeOpened, true);
