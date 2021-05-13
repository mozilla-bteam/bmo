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
      this.severity_current_value = this.severity.value;
      this.priority_current_value = this.priority.value;
      this.severity.addEventListener("change", () => this.severity_onselect());
    }
  }

  /**
   * Called when severity select is changed. Updated priority field options appropriately
   */
  severity_onselect() {
    let options = this.priority.getElementsByTagName("option");
    if (this.severity.value == 'S1') {
      for (var i = 0; i < options.length; i++) {
        if (options[i].value == 'P1') {
          options[i].selected = true;
          options[i].disabled = false;
        }
        else {
          options[i].disabled = true;
        }
      }
    }
    else {
      for (var i = 0; i < options.length; i++) {
        options[i].disabled = false;
      }
    }
  };
};

window.addEventListener(
  "DOMContentLoaded",
  () => new Bugzilla.SeverityS1PriorityP1()
);
