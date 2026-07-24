#!/usr/bin/env node
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Regenerates the third-party front-end libraries served by BMO from the
// versions pinned in package.json / package-lock.json.
//
//   npm run build      regenerate the committed files under js/
//   npm run verify     rebuild in memory and fail if the committed files are
//                      stale (used by CI to guard against drift)
//
// Only third-party libraries live here. First-party BMO JavaScript stays in
// the repository as-is. bpopup is not published to npm and remains vendored
// under js/jquery/plugins/bPopup/.

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative } from 'node:path';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const root = join(scriptDir, '..');
const nm = join(root, 'node_modules');

const check = process.argv.includes('--check');

// Prism: concatenate the core runtime with exactly the language grammars BMO
// uses. No plugins — in particular NOT the autolinker plugin, whose unsanitised
// href handling was the DOM-XSS in bug 2055861.
const PRISM_LANGS = [
  'core', 'markup', 'css', 'clike', 'javascript', 'c', 'cpp',
  'diff', 'http', 'json', 'markdown', 'perl', 'python', 'rust', 'yaml',
];

function prismBundle() {
  const version = JSON.parse(
    readFileSync(join(nm, 'prismjs/package.json'), 'utf8'),
  ).version;
  const header =
    `/* PrismJS ${version}\n` +
    `https://prismjs.com/download.html#themes=prism&languages=` +
    `${PRISM_LANGS.filter((l) => l !== 'core').join('+')} */\n`;
  const body = PRISM_LANGS
    .map((l) => readFileSync(join(nm, `prismjs/components/prism-${l}.min.js`), 'utf8').trimEnd())
    .join('\n');
  return header + body + '\n';
}

// dest (repo-relative) -> function returning the file contents to write.
const TARGETS = {
  'js/lib/prism.js': prismBundle,
  'js/lib/mermaid.min.js': () => read('mermaid/dist/mermaid.min.js'),
  'js/lib/md5.min.js': () => read('blueimp-md5/js/md5.min.js'),
  'js/jquery/jquery-min.js': () => read('jquery/dist/jquery.min.js'),
  'js/jquery/ui/jquery-ui-min.js': () => read('jquery-ui-dist/jquery-ui.min.js'),
  'js/jquery/plugins/contextMenu/contextMenu-min.js':
    () => read('jquery-contextmenu/dist/jquery.contextMenu.min.js'),
  'js/jquery/plugins/datetimepicker/datetimepicker-min.js':
    () => read('jquery-datetimepicker/build/jquery.datetimepicker.full.min.js'),
  'js/jquery/plugins/devbridgeAutocomplete/devbridgeAutocomplete-min.js':
    () => read('devbridge-autocomplete/dist/jquery.autocomplete.min.js'),
  'js/duo-min.js': () => read('duo_web/js/Duo-Web-v2.min.js'),
};

function read(rel) {
  return readFileSync(join(nm, rel), 'utf8');
}

let stale = 0;
for (const [dest, produce] of Object.entries(TARGETS)) {
  const wanted = produce();
  const path = join(root, dest);
  let current = null;
  try {
    current = readFileSync(path, 'utf8');
  } catch {
    /* file may not exist yet */
  }
  const same = current === wanted;
  if (check) {
    if (!same) {
      stale++;
      console.error(`STALE  ${dest}`);
    } else {
      console.log(`ok     ${dest}`);
    }
  } else {
    if (!same) {
      writeFileSync(path, wanted);
      console.log(`wrote  ${dest} (${wanted.length} bytes)`);
    } else {
      console.log(`same   ${dest}`);
    }
  }
}

if (check && stale) {
  console.error(
    `\n${stale} generated file(s) are out of date. Run \`npm run build\` and commit the result.`,
  );
  process.exit(1);
}
