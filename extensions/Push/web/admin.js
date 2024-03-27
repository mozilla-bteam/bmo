/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

function toggle_options(visible, name) {
  document.querySelectorAll(`.${name}_tr`).forEach(($row) => {
    $row.classList.toggle('hidden', !visible);
  });
}

function reset_to_defaults() {
  if (!push_defaults) return;
  for (var id in push_defaults) {
    var el = document.getElementById(id);
    if (!el) continue;
    if (el.nodeName == 'INPUT') {
      el.value = push_defaults[id];
    } else if (el.nodeName == 'SELECT') {
      for (var i = 0, l = el.options.length; i < l; i++) {
        if (el.options[i].value == push_defaults[id]) {
          el.options[i].selected = true;
          break;
        }
      }
    }
  }
}

$(function() {
    $('#deleteMessage input[type=submit]')
        .click(function(event) {
            return confirm('Are you sure you want to delete this message forever (a long time)?');
        });
});
