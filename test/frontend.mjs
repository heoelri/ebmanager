import assert from 'node:assert/strict';
import fs from 'node:fs';

const html = fs.readFileSync('public/index.html', 'utf8');
const css = fs.readFileSync('public/styles.css', 'utf8');
const deployment = fs.readFileSync('.github/workflows/deploy.yml', 'utf8');
assert.match(html, /<link rel="stylesheet" href="public\/styles\.css">/);
assert.doesNotMatch(html, /<style(?:\s|>)/);
assert.doesNotMatch(html, /\sstyle="/);
assert.match(css, /--control-height:\s*44px/);
assert.match(css, /font-size:\s*1rem/);
assert.match(css, /env\(safe-area-inset-bottom\)/);
assert.match(css, /@media \(forced-colors: active\)/);
assert.match(css, /@media \(forced-colors: active\)[\s\S]*?\.error\s*\{[\s\S]*?border-inline-start-width:\s*4px/);
assert.match(deployment, /put "public\/styles\.css" "public\/styles\.css"/);

const resetPasswordSource = html.match(/async function resetPassword[^\n]+/)?.[0];
assert(resetPasswordSource, 'resetPassword fehlt');
assert.match(resetPasswordSource, /password-reset\/context.*method:'POST'.*JSON\.stringify\(\{token\}\)/);
assert(resetPasswordSource.indexOf('autocomplete="username"') < resetPasswordSource.indexOf('autocomplete="new-password"'));
assert.match(resetPasswordSource, /name="username" type="email" autocomplete="username"[^>]+readonly/);
assert.match(resetPasswordSource, /catch\(error\)\{history\.replaceState\(\{\},'',location\.pathname\)/);
assert.match(resetPasswordSource, /Link nicht mehr gültig/);
assert.match(resetPasswordSource, /onclick="forgotPassword\(\)">Neuen Link anfordern/);
assert.match(html, /fragment\.get\('invite'\)/);
assert.match(html, /fragment\.get\('reset'\)/);

const source = html.match(/function rankOptions[\s\S]*?(?=\nfunction reportDetailsFields)/)?.[0];
assert(source, 'rankOptions fehlt');

const rankOptions = new Function('ranks', 'esc', `${source}; return rankOptions;`)(
  {BM: 'Brandmeister', GBI: 'Gemeindebrandinspektor', SBI: 'Stadtbrandinspektor'},
  value => String(value)
);

assert.match(rankOptions('BM'), /value="BM" selected>BM – Brandmeister/);
assert.match(rankOptions('GBI'), /value="GBI" selected>GBI – Gemeindebrandinspektor/);
assert.match(rankOptions('SBI'), /value="SBI" selected>SBI – Stadtbrandinspektor/);
assert.match(rankOptions(''), /^<option value="">Keine Angabe<\/option>/);
assert.match(rankOptions('ALT'), /value="ALT" selected>ALT/);
assert.equal((rankOptions('ALT').match(/value="ALT"/g) ?? []).length, 1);

const incidentStatusSource = html.match(/function incidentStatus[^\n]+/)?.[0];
assert(incidentStatusSource, 'incidentStatus fehlt');
const incidentStatus = new Function('esc', `${incidentStatusSource}; return incidentStatus;`)(value => String(value));
for (const label of ['Bericht erforderlich', 'Prüfung erforderlich', 'Bereit zur Konsolidierung', 'Abgeschlossen']) {
  assert.match(incidentStatus({reportStatus: {label}}), new RegExp(`<b>Status:</b> ${label}`));
}
assert.match(css, /\.incident-status\s*\{[\s\S]*?border-inline-start:\s*4px solid/);

const filterOptionsSource = html.match(/function incidentFilterOptions[^\n]+/)?.[0];
assert(filterOptionsSource, 'incidentFilterOptions fehlt');
const incidentFilterOptions = new Function('esc', `${filterOptionsSource}; return incidentFilterOptions;`)(value => String(value));
assert.equal(incidentFilterOptions([
  {reportStatus: {key: 'report_required', label: 'Bericht erforderlich: Löschzug'}},
  {reportStatus: {key: 'submitted', label: 'Bericht abgegeben'}},
  {reportStatus: {key: 'report_required', label: 'Bericht erforderlich: Löschgruppe'}}
]), '<option value="report_required">Bericht erforderlich</option><option value="submitted">Bericht abgegeben</option>');

const filterSource = html.match(/function filterIncidents[^\n]+/)?.[0];
assert(filterSource, 'filterIncidents fehlt');
const cards = [
  {dataset: {incidentStatus: 'report_required'}, hidden: false},
  {dataset: {incidentStatus: 'submitted'}, hidden: false}
];
const noFilteredIncidents = {hidden: true};
const filterIncidents = new Function('document', `${filterSource}; return filterIncidents;`)({
  querySelectorAll: () => cards,
  querySelector: () => noFilteredIncidents
});
filterIncidents('submitted');
assert.deepEqual(cards.map(card => card.hidden), [true, false]);
assert.equal(noFilteredIncidents.hidden, true);
filterIncidents('ready');
assert.equal(noFilteredIncidents.hidden, false);
filterIncidents('');
assert.deepEqual(cards.map(card => card.hidden), [false, false]);
assert.match(html, /<label>Status filtern<select id="incidentStatusFilter"/);

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
assert.match(reportFields, /name="commandRank">[\s\S]*?<option value="BI" selected>BI – Brandinspektor/);
assert.match(reportFields, /name="commandName" value="A"/);
assert.match(reportFields, /name="additionalCommandRank">[\s\S]*?<option value="BM" selected>BM – Brandmeister/);
assert.match(reportFields, /name="additionalCommandName" value="B"/);
assert.equal((reportFields.match(/class="form-section" open/g) ?? []).length, 3);
assert.match(reportDetailsFields('new', {foreign_id: '', started_at: ''}), /DIVERA-Einsatznummer<input value="Nicht vorhanden" readonly>/);

const durationSource = html.match(/function durationText[^\n]+/)?.[0];
assert(durationSource, 'durationText fehlt');
const durationText = new Function(`${durationSource}; return durationText;`)();
assert.equal(durationText(null, null), '–');
assert.equal(durationText(null, '2026-08-22T19:00:00Z'), '–');

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
assert.match(css, /\.form-section\s*>\s*summary:focus-visible\s*\{[\s\S]*?outline-offset:\s*-3px/);
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
assert.match(html, /onclick="editReport\(\$\{report\.id\},this\)"/);
assert.match(html, /onclick="editUser\(\$\{u\.id\},this\)"/);
assert.match(html, /author_draft:'Entwurf der Führungskraft'/);
assert.match(html, /unit_review:'Prüfung durch Einheitsführung'/);
assert.match(html, /wehr_review:'Prüfung durch Wehrführung'/);
assert.match(html, /submit-to-unit/);
assert.match(html, /return-to-author/);
assert.match(html, /submit-to-command/);
assert.match(html, /return-to-unit/);
assert.match(html, /name="comment" maxlength="2000" required/);
assert.match(html, /Prüfverlauf \(\$\{report\.history\.length\}\)/);
assert.match(html, /roleLabels=\{fuehrungskraft:'Führungskraft',einheitsleitung:'Einheitsführung',wehrleitung:'Wehrführung'\}/);
assert.match(html, /Abgeschickt\$\{submitted\?` am/);
assert.match(html, /Der Einsatzbericht ist für Sie jetzt nur noch lesbar/);
assert.match(html, /jede alarmierte Einheit einen Bericht an die Wehrführung gesendet hat/);
assert.match(html, /Noch nicht bereit:/);
assert.match(html, /if\(me\.role==='wehrleitung'&&mayConsolidate\)bindForm\('#consolidate'/);
const authorNoticeSource = html.match(/function authorReportNotice[^\n]+/)?.[0];
assert(authorNoticeSource, 'authorReportNotice fehlt');
const authorReportNotice = new Function(
  'me', 'formatDateTime', 'esc',
  `${authorNoticeSource}; return authorReportNotice;`
)(
  {role: 'fuehrungskraft'},
  value => value,
  value => String(value ?? '')
);
assert.match(authorReportNotice({
  status: 'unit_review',
  history: [{from_status: 'author_draft', to_status: 'unit_review', created_at: '2026-08-23T18:00:00Z'}]
}), /Abgeschickt am 2026-08-23T18:00:00Z.*nur noch lesbar/);
assert.equal(authorReportNotice({status: 'author_draft', history: []}), '');
const reportActionsSource = html.match(/function reportActions[^\n]+/)?.[0];
assert(reportActionsSource, 'reportActions fehlt');
for (const me of [
  {id: 1, role: 'fuehrungskraft', unitIds: [1]},
  {id: 2, role: 'einheitsleitung', unitIds: [1]}
]) {
  const reportActions = new Function('me', `${reportActionsSource}; return reportActions;`)(me);
  assert.equal(reportActions({id: 1, unit_id: 1, author_id: 1, status: 'wehr_review', editable: false, history: []}, 1), '');
}
assert.doesNotMatch(html, /\/release/);
assert.match(html, /type="\$\{type\}" name="unitIds"/);
assert.match(html, /role==='einheitsleitung'\?'radio':'checkbox'/);
assert.match(html, /Alles synchronisieren/);
assert.match(html, /Fahrzeuge synchronisieren/);
assert.match(html, /\/resources/);
assert.match(html, /Qualifikationen:/);

const loadCrewSource = html.match(/async function loadReportCrew[^\n]+/)?.[0];
assert(loadCrewSource, 'loadReportCrew fehlt');
assert.doesNotMatch(loadCrewSource, /unitSelect\.disabled=true/);
assert.match(loadCrewSource, /form\.closest\('dialog'\)&&!dialog\.open/);
assert.match(loadCrewSource, /root\.dataset\.crewRequest!==request/);
assert.match(loadCrewSource, /unitSelect\?\.value\|\|unitId/);
assert.match(loadCrewSource, /Erneut laden/);
assert.match(loadCrewSource, /if\(restoreFocus\)retry\.focus\(\)/);

const renderCrewSource = html.match(/async function renderCrew[\s\S]*?(?=\nfunction bindCrewBoard)/)?.[0];
assert(renderCrewSource, 'renderCrew fehlt');
assert.match(renderCrewSource, /if\(!root\.isConnected\|\|/);
assert.match(renderCrewSource, /if\(restoreFocus\)root\.querySelector\('h3'\)\.focus\(\)/);

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
