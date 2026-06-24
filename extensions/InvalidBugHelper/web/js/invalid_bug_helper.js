/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

'use strict';

function showCloseDialog(bugId) {
  return new Promise((resolve) => {
    const dialog = document.createElement('dialog');
    dialog.id = 'close-invalid-dialog';
    dialog.innerHTML = `
      <form method="dialog">
        <h3>Close Bug ${bugId} as Invalid</h3>
        <p>This will:</p>
        <ul>
          <li>Move the bug to Invalid Bugs :: General</li>
          <li>Resolve it as INVALID</li>
          <li>Clear needinfo flags</li>
          <li>Post a warning comment</li>
        </ul>
        <p><strong>This cannot be undone easily.</strong></p>
        <hr>
        <label>
          <input type="checkbox" id="close-invalid-mark-spam">
          Also mark the reporter's comments as spam
        </label>
        <p class="warning">
          <span class="warning-icon">&#x26A0;&#xFE0F;</span> May trigger automatic account disabling via AntiSpam.
          Only check if the reporter is actually a spammer.
        </p>
        <div class="actions">
          <button type="submit" value="cancel">Cancel</button>
          <button type="submit" value="confirm">Close as Invalid</button>
        </div>
      </form>`;
    dialog.addEventListener('close', () => {
      const spam = dialog.querySelector('#close-invalid-mark-spam').checked;
      dialog.remove();
      resolve(dialog.returnValue === 'confirm' ? { confirmed: true, markAsSpam: spam } : { confirmed: false });
    });
    document.body.appendChild(dialog);
    dialog.showModal();
  });
}

document.addEventListener('DOMContentLoaded', () => {
  const btn = document.getElementById('close-as-invalid-btn');
  if (!btn) return;

  btn.addEventListener('click', async () => {
    const bugId = BUGZILLA.bug_id;
    const { confirmed, markAsSpam } = await showCloseDialog(bugId);
    if (!confirmed) return;

    btn.disabled = true;
    btn.textContent = 'Closing…';

    try {
      await Bugzilla.API.post(
        `invalid_bug_helper/close/${bugId}`,
        { mark_as_spam: markAsSpam ? 1 : 0 }
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
}, { once: true });
