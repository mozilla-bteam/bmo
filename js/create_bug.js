/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

/**
 * Implement features on the New Bug page.
 */
Bugzilla.CreateBug = class CreateBug {
  /**
   * Initialize a new CreateBug instance.
   */
  constructor() {
    this.init_expander();
  }

  /**
   * Activate expanders on each section.
   */
  init_expander() {
    const $controller = document.querySelector('#expert_fields_controller');

    new Bugzilla.Expander($controller);

    $controller.addEventListener('Expander#toggle', event => {
      if (event.detail.hidden) {
        handleWantsBugFlags(false);
      }
    });
  }
};

window.addEventListener('DOMContentLoaded', () => {
  new Bugzilla.CreateBug();
}, { once: true });

function handleWantsBugFlags(wants) {
  if (wants) {
    hideElementById('bug_flags_false');
    showElementById('bug_flags_true');
  }
  else {
    showElementById('bug_flags_false');
    hideElementById('bug_flags_true');
    clearBugFlagFields();
  }
}

function clearBugFlagFields() {
  var flags_table;
  flags_table = document.getElementById('bug_flags');
  if (flags_table) {
    var selects = flags_table.getElementsByTagName('select');
    for (var i = 0, il = selects.length; i < il; i++) {
      if (selects[i].value != 'X') {
        selects[i].value = 'X';
        toggleRequesteeField(selects[i]);
      }
    }
  }
  flags_table = document.getElementById('bug_tracking_flags');
  if (flags_table) {
    var selects = flags_table.getElementsByTagName('select');
    for (var i = 0, il = selects.length; i < il; i++) {
      selects[i].value = '---';
    }
  }
}

YAHOO.util.Event.onDOMReady(function() {
  function set_width(id, width) {
    var el = document.getElementById(id);
    if (!el) return;
    el.style.width = width + 'px';
  }

  // force field widths

  var width = document.getElementById('short_desc').clientWidth + 'px';
  var el;

  el = document.getElementById('comment');
  el.style.width = width;

  el = document.getElementById('cf_crash_signature');
  if (el) el.style.width = width;

  // show the bug flags if a flag is set

  var flag_set = false;
  var flags_table;
  flags_table = document.getElementById('bug_flags');
  if (flags_table) {
    var selects = flags_table.getElementsByTagName('select');
    for (var i = 0, il = selects.length; i < il; i++) {
      if (selects[i].value != 'X') {
        flag_set = true;
        break;
      }
    }
  }
  if (!flag_set) {
    flags_table = document.getElementById('bug_tracking_flags');
    if (flags_table) {
      var selects = flags_table.getElementsByTagName('select');
      for (var i = 0, il = selects.length; i < il; i++) {
        if (selects[i].value != '---') {
          flag_set = true;
          break;
        }
      }
    }
  }

  if (flag_set) {
    hideElementById('bug_flags_false');
    showElementById('bug_flags_true');
  } else {
    hideElementById('bug_flags_true');
    showElementById('bug_flags_false');
  }
  showElementById('btn_no_bug_flags')
});

function take_bug(user) {
  var el = Dom.get('assigned_to');
  el.value = user;
  el.focus();
  el.select();
  assignee_change(user);
  return false;
}

function assignee_change(user) {
  var el = Dom.get('take_bug');
  if (!el) return;
  el.style.display = Dom.get('assigned_to').value == user ? 'none' : '';
}

function init_take_handler(user) {
  YAHOO.util.Event.addListener(
    'assigned_to', 'change', function() { assignee_change(user); });
  assignee_change(user);
}
