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
Bugzilla.SetTrackingSeverityS1 = class SetTrackingSeverityS1 {
  /**
   * Initialize a new SetTrackingSeverityS1 instance.
   */
  constructor() {
    this.priority = document.querySelector("#priority");
    this.severity = document.querySelector("#bug_severity");
    this.flags = document.querySelector("div.edit-show table.tracking-flags");
    this.firefox_versions = document.querySelector(
      'meta[name="firefox-versions"]'
    );

    if (this.severity && this.priority && this.flags && this.firefox_versions) {
      this.sev_curr_value = this.severity.value;
      this.severity.addEventListener("change", () => this.severity_onselect());

      // Find cf_tracking_ specific flags and
      // store current values to reset them if needed
      const product_details = this.getMajors(
        JSON.parse(this.firefox_versions.content)
      );
      const nightly = "cf_tracking_firefox" + product_details.nightly;
      const beta = "cf_tracking_firefox" + product_details.beta;
      this.flag_selects = [];
      this.flag_curr_values = [];
      this.flag_curr_titles = [];
      this.flags
        .querySelectorAll(
          'select[name="' + nightly + '"], select[name="' + beta + '"]'
        )
        .forEach((flag) => {
          this.flag_selects.push(flag);
          this.flag_curr_values[flag.name] = flag.value;
          this.flag_curr_titles[flag.name] = flag.title;
        });
    }
  }

  /**
   * Called when severity select is changed. If severity if changed to S1
   * from something else, set firefox beta and nightly tracking flags to '?'.
   */
  severity_onselect() {
    const s1_selected =
      this.sev_curr_value !== "S1" && this.severity.value === "S1";

    this.flag_selects.forEach((flag) => {
      const options = flag.querySelectorAll("option");
      options.forEach((opt) => (opt.disabled = s1_selected));
      if (s1_selected && flag.value !== "+") {
        const request_opt = Array.from(options).filter(
          (opt) => opt.value === "?"
        )[0];
        request_opt.disabled = false;
        request_opt.selected = true;
        flag.title = "Flag is locked since Severity was moved to S1";
      } else if (
        flag.value !== this.flag_curr_values[flag.name] &&
        flag.value === "?"
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

  getMajor(s) {
    return parseInt(s.split(".")[0], 10);
  }

  getMajors(pd) {
    const res = {};
    res.nightly = this.getMajor(pd.FIREFOX_NIGHTLY);
    res.beta = this.getMajor(pd.LATEST_FIREFOX_RELEASED_DEVEL_VERSION);
    return res;
  }
};

window.addEventListener(
  "DOMContentLoaded",
  () => new Bugzilla.SetTrackingSeverityS1()
);
