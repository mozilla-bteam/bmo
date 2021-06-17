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
 * Provide the ability to insert a comment template when the severity field is changed.
 */
Bugzilla.CommentOnSeverity = class CommentOnSeverity {
  /**
   * Initialize a new CommentOnSeverity instance.
   */
  constructor() {
    this.comment = document.querySelector("#comment");
    this.severity = document.querySelector("#bug_severity");
    this.comment_text = "Changing severity to S? because of <rationale>.";

    if (this.severity && this.comment) {
      this.severity_comment_required = this.severity.parentElement.appendChild(
        document.createElement("span")
      );
      this.curr_severity = this.severity.value;
      this.severity.addEventListener("change", () => this.severity_onselect());
    }
  }

  /**
   * Called when severity select is changed. Insert or remove the comment text
   */
  severity_onselect() {
    // Set comment required warning
    if (this.severity.value != this.curr_severity) {
      this.severity_comment_required.innerHTML =
        ' <a href="https://firefox-source-docs.mozilla.org/bug-mgmt/guides/severity.html" target="_blank">Comment Required</a>';
    } else {
      this.severity_comment_required.innerHTML = "";
    }

    // Set comment text to the template if severity has changed.
    if (this.severity.value != this.curr_severity && this.comment.value == "") {
      this.comment.value = this.comment_text;
    }
    if (
      this.severity.value == this.curr_severity &&
      this.comment.value == this.comment_text
    ) {
      this.comment.value = "";
    }
  }
};

window.addEventListener(
  "DOMContentLoaded",
  () => new Bugzilla.CommentOnSeverity()
);
