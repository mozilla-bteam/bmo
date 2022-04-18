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
 * Enforce setting of Priority to P1 when Severity is set to S1
 */
Bugzilla.SeverityS1PriorityP1 = class SeverityS1PriorityP1 {
  /**
   * Initialize a new SeverityS1PriorityP1 instance.
   */
  constructor() {
    this.priority = document.querySelector("#priority");
    this.severity = document.querySelector("#bug_severity");
    if (this.severity && this.priority) {
      this.pri_orig_title = this.priority.title;
      this.severity.addEventListener("change", () => this.severity_onselect());
    }
  }

  /**
   * Called when severity select is changed. Updated priority field options appropriately
   */
  severity_onselect() {
    const s1_selected = this.severity.value === 'S1';
    const options = this.priority.querySelectorAll("option");
    options.forEach(opt => opt.disabled = s1_selected);
    if (s1_selected) {
      const p1_opt = Array.from(options).filter(opt => opt.value === 'P1')[0];
      p1_opt.disabled = false;
      p1_opt.selected = true;
      this.priority.title = 'Priority is locked to P1 since Severity is set to S1';
    } else {
      this.priority.title = this.pri_orig_title;
    }
  };
};

window.addEventListener(
  "DOMContentLoaded",
  () => new Bugzilla.SeverityS1PriorityP1()
);
