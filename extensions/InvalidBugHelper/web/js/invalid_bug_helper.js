/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

'use strict';

(() => {
  const btn = document.getElementById('close-as-invalid-btn');
  if (!btn) return;

  btn.addEventListener('click', async () => {
    const bugId = BUGZILLA.bug_id;
    const confirmed = window.confirm(
      `Close Bug ${bugId} as an invalid test/spam submission?\n\n` +
      'This will:\n' +
      '  • Move the bug to Invalid Bugs :: General\n' +
      '  • Resolve it as INVALID\n' +
      '  • Clear needinfo flags\n' +
      '  • Mark the reporter\'s comments as spam\n' +
      '  • Post a warning comment\n\n' +
      'This cannot be undone easily. Continue?'
    );
    if (!confirmed) return;

    btn.disabled = true;
    btn.textContent = 'Closing…';

    try {
      await Bugzilla.API.post(
        `invalid_bug_helper/close/${bugId}`,
        {}
      );
      window.location.replace(
        `${BUGZILLA.config.basepath}show_bug.cgi?id=${bugId}`
      );
    } catch (err) {
      const message = (err && err.message) ? err.message : String(err);
      window.alert(`Failed to close bug: ${message}`);
      btn.disabled = false;
      btn.textContent = 'Close as Invalid';
    }
  });
})();
