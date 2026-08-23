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
