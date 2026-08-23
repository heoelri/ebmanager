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
