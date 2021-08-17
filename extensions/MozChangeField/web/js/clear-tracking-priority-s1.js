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
Bugzilla.ClearTrackingPriorityS1 = class ClearTrackingPriorityS1 {
  /**
   * Initialize a new ClearTrackingPriorityS1 instance.
   */
  constructor() {
    this.priority = document.querySelector("#priority");
    this.severity = document.querySelector("#bug_severity");
    this.flags = document.querySelector("div.edit-show table.tracking-flags");

    if (this.severity && this.priority && this.flags) {
      this.sev_curr_value = this.severity.value;
      this.severity.addEventListener("change", () => this.severity_onselect());

      // Find cf_tracking_ specific flags and
      // store current values to reset them if needed
      this.flag_selects = [];
      this.flag_curr_values = [];
      this.flag_curr_titles = [];
      this.flags.querySelectorAll("select").forEach((flag) => {
        if (flag.name.indexOf("cf_tracking_") !== -1) {
          this.flag_selects.push(flag);
          this.flag_curr_values[flag.name] = flag.value;
          this.flag_curr_titles[flag.name] = flag.title;
        }
      });
    }
  }

  /**
   * Called when severity select is changed. If severity if changed away from S1
   * then reset priority to '--' and clear any tracking flags set to '?'.
   */
  severity_onselect() {
    const s1_not_selected =
      this.sev_curr_value === "S1" && this.severity.value !== "S1";

    if (s1_not_selected) {
      this.priority.value = "--";
      this.priority.title = "Priority cleared due to Severity change from S1";
    }

    this.flag_selects.forEach((flag) => {
      const options = flag.querySelectorAll("option");
      options.forEach((opt) => (opt.disabled = s1_not_selected));
      if (s1_not_selected && flag.value === "?") {
        const request_opt = Array.from(options).filter(
          (opt) => opt.value === "---"
        )[0];
        request_opt.disabled = false;
        request_opt.selected = true;
        flag.title = "Flag is locked since Severity was moved from S1";
      } else if (
        flag.value !== this.flag_curr_values[flag.name] &&
        flag.value === "---"
      ) {
        const request_opt = Array.from(options).filter(
          (opt) => opt.value === this.flag_curr_values[flag.name]
        )[0];
        request_opt.disabled = false;
        request_opt.selected = true;
        flag.title = this.flag_curr_titles[flag.name];
      }
    });
  }
};

window.addEventListener(
  "DOMContentLoaded",
  () => new Bugzilla.ClearTrackingPriorityS1()
);
