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
 * Provide the ability to insert a comment template when a patch's approval flag is selected.
 */
Bugzilla.FlagTypeComment = class FlagTypeComment {
  /**
   * Initialize a new FlagTypeComment instance.
   */
  constructor() {
    const root = document.querySelector('#att-overlay') ?? document;

    this.templates = [...document.querySelectorAll('template.approval-request')];
    this.$flags = root.querySelector('.flag-table');
    this.$comment = root.querySelector('#comment');

    if (this.$flags && this.$comment) {
      const $extra_patch_types = root.querySelector('meta[name="extra-patch-types"]');
      const $wrapper_parent = root.querySelector('.comment-pane') ?? this.$flags.parentElement;

      /** @type {HTMLFormElement} */
      this.$form = this.$comment.form;

      this.bug_id = Number(this.$form.bugid.value);
      this.extra_patch_types = $extra_patch_types ? $extra_patch_types.content.split(' ') : [];
      this.selects = [...this.$flags.querySelectorAll('.flag_select')];
      this.$fieldset_wrapper = $wrapper_parent.appendChild(document.createElement('div'));
      this.$fieldset_wrapper.id = 'approval-request-fieldset-wrapper';
      this.$comment_wrapper =
        root.querySelector('.comment-wrapper') ??
        root.querySelector('#smallCommentFrame') ??
        this.$comment.parentElement;
      this.$submit = this.$form.querySelector('input[type="submit"]');
      this.$status =
        this.$form.querySelector('.footer [role="status"]') ??
        this.$form.querySelector('#update_container [role="status"]');

      this.$form.addEventListener('submit', event => this.form_onsubmit(event));
      this.selects.forEach($select => $select.addEventListener('change', () => this.flag_onselect($select)));
    }
  }

  /**
   * Check if a fieldset is compatible with the given flag. For example, `approval‑mozilla‑beta` matches
   * `<section data-flags="approval‑mozilla‑beta approval‑mozilla‑release">` while `approval‑mozilla‑esr60` matches
   * `<section data-flags="approval‑mozilla‑esr*">`.
   * @param {String} name Flag name, such as `approval‑mozilla‑beta`.
   * @param {HTMLElement} $element `<section>` or `<template>` element with the `data-flags` attribute which is a
   * space-separated list of flag names (wildcard chars can be used).
   * @returns {Boolean} Whether the fieldset is compatible.
   */
  check_compatibility(name, $element) {
    return !!$element.dataset.flags.split(' ')
      .find(_name => !!name.match(new RegExp(`^${_name.replace('*', '.+')}$`, 'i')));
  }

  /**
   * Return a list of temporary fieldsets already inserted to the current page.
   * @type {Array.<HTMLElement>}
   */
  get inserted_fieldsets() {
    return [...this.$fieldset_wrapper.querySelectorAll('section.approval-request')];
  }

  /**
   * Find a temporary fieldset already inserted to the current page by a flag name.
   * @param {String} name Flag name, such as `approval‑mozilla‑beta`.
   * @returns {HTMLElement} Any `<section>` element.
   */
  find_inserted_fieldset(name) {
    return this.inserted_fieldsets.find($fieldset => this.check_compatibility(name, $fieldset));
  }

  /**
   * Find an available fieldset embedded in HTML by a flag name.
   * @param {String} name Flag name, such as `approval‑mozilla‑beta`.
   * @returns {HTMLElement} Any `<section>` element.
   */
  find_available_fieldset(name) {
    for (const $template of this.templates) {
      if (this.check_compatibility(name, $template)) {
        const $fieldset = $template.content.cloneNode(true).querySelector('section');

        $fieldset.className = 'approval-request';
        $fieldset.dataset.flags = $template.dataset.flags;

        // Make the request form dismissible
        $fieldset.querySelector('header').insertAdjacentHTML('beforeend',
          '<button type="button" class="dismiss" title="Dismiss" aria-label="Dismiss">' +
          '<span class="icon" aria-hidden="true"></span></button>');
        $fieldset.querySelector('button.dismiss').addEventListener('click', () => this.dismiss_onclick($fieldset));

        return $fieldset;
      }
    }

    return null;
  }

  /**
   * Find one or more `<select>` elements that match the requested flag(s) of the given fieldset.
   * @param {HTMLElement} $fieldset `<section>` element with the `data-flags` attribute.
   * @returns {Array.<HTMLSelectElement>} Any `<select>` element(s).
   */
  find_selectors($fieldset) {
    return this.selects
      .filter($_select => $_select.value === '?' && this.check_compatibility($_select.dataset.name, $fieldset));
  }

  /**
   * Hide the original comment box when one or more fieldsets are inserted.
   */
  toggle_comment_box() {
    this.$comment_wrapper.hidden = this.inserted_fieldsets.length > 0;
  }

  /**
   * Parse a fieldset to convert the form values to comment text.
   * @param {HTMLElement} $fieldset `<section>` element with the `data-flags` attribute.
   * @returns {String} Comment text formatted in the Markdown syntax.
   */
  create_comment($fieldset) {
    return [
      `### ${$fieldset.querySelector('h3').innerText}`,
      ...[...$fieldset.querySelectorAll('tr:not(.other-patches)')].map($tr => {
        const checkboxes = [...$tr.querySelectorAll('input[type="checkbox"]:checked')];
        const $radio = $tr.querySelector('input[type="radio"]:checked');
        const $input = $tr.querySelector('textarea,select,input');
        const label = $tr.querySelector('th').innerText.replace(/\n/g, ' ');
        let value = '';

        if (checkboxes.length) {
          value = checkboxes.map($checkbox => $checkbox.value.trim()).join(', ');
        } else if ($radio) {
          value = $radio.value.trim();
        } else if ($input) {
          value = $input.value.trim();

          if ($input.dataset.type === 'bug') {
            if (!value) {
              value = 'None';
            } else if (!isNaN(value)) {
              value = `Bug ${value}`;
            }
          }

          if ($input.dataset.type === 'bugs') {
            if (!value) {
              value = 'None';
            } else {
              value = value.split(/,\s*/).map(str => (!isNaN(str) ? `Bug ${str}` : str)).join(', ');
            }
          }
        }

        return `* **${label}**: ${value}`;
      }),
    ].join('\n');
  }

  /**
   * Add text to the comment box at the end of any existing comment.
   * @param {String} text Comment text to be added.
   */
  add_comment(text) {
    this.$comment.value = this.$comment.value.match(/\S+/g) ? [this.$comment.value, text].join('\n\n') : text;
  }

  /**
   * Called whenever a flag selection is changed. Insert or remove a comment template.
   * @param {HTMLSelectElement} $select `<select>` element that the `change` event is fired.
   */
  async flag_onselect($select) {
    const id = Number($select.dataset.id);
    const { name } = $select.dataset;
    const state = $select.value;
    let $fieldset = this.find_inserted_fieldset(name);

    // Remove the temporary fieldset if not required. One fieldset can support multiple flags, so, for example,
    // if `approval‑mozilla‑release` is unselected but `approval‑mozilla‑beta` is still selected, keep it
    if (state !== '?' && $fieldset && !this.find_selectors($fieldset).length) {
      $fieldset.remove();
    }

    // Insert a temporary fieldset if available
    if (state === '?' && !$fieldset) {
      $fieldset = this.find_available_fieldset(name);

      if ($fieldset) {
        this.$fieldset_wrapper.appendChild($fieldset);

        // Show any other patches that can be requested for approval
        try {
          const { bugs } = await Bugzilla.API.get(`bug/${this.bug_id}/attachment`, {
            include_fields: ['id', 'summary', 'content_type', 'is_patch', 'is_obsolete'],
          });
          const attachments = bugs ? bugs[this.bug_id] : [];
          const attachment_id = Number(this.$form.id.value); // Updated dynamically on overlay
          const others = attachments.filter(att => att.id !== attachment_id && !att.is_obsolete &&
            (att.is_patch || this.extra_patch_types.includes(att.content_type)));

          if (others.length) {
            $fieldset.querySelector('tbody').insertAdjacentHTML('beforeend', `
              <tr class="other-patches"><th>Do you want to request approval of these patches as well?</th><td>
              ${others.map(patch => `
                <div>
                  <label><input type="checkbox" checked data-id="${patch.id}"> ${patch.summary.htmlEncode()}</label>
                </div>
              `).join('')}
              </td></tr>
            `);
          }
        } catch (ex) {}
      }
    }

    // Insert a traditional plaintext comment template if available
    if (!$fieldset) {
      const $meta = document.querySelector(`meta[name="ftc:${id}:${state}"]`);
      const text = $meta ? $meta.content : '';

      if (text && this.$comment.value !== text) {
        this.add_comment(text);
      }
    }

    this.toggle_comment_box();
  }

  /**
   * Called whenever the Dismiss button on a fieldset is clicked. Remove the fieldset once confirmed.
   * @param {HTMLElement} $fieldset Any `<section>` element.
   */
  dismiss_onclick($fieldset) {
    if (window.confirm(`Do you really want to remove the ${$fieldset.querySelector('h3').innerText} form?`)) {
      $fieldset.remove();
      this.toggle_comment_box();
    }
  }

  /**
   * Called when the user tries to submit the form. Convert the input values to comment text, and send it in background
   * along with other flag updates.
   * @param {Event} event `submit` event.
   * @returns {Boolean} `true` when submitting the form normally if no fieldset has been inserted, `false` otherwise.
   */
  async form_onsubmit(event) {
    if (this.submitting) {
      return false;
    }

    // Submit the form normally if no fieldsets can be found
    if (!this.inserted_fieldsets.length) {
      return true;
    }

    // Prevent auto-submission
    event.preventDefault();

    // Update the button
    this.$submit.disabled = this.submitting = true;
    this.$status.textContent = 'Sending form data…';

    const requests = [];
    const $markdown_off = this.$form.querySelector('input[name="markdown_off"]');

    // Enable Markdown for any regular patches. Phabricator requests don't come with this hidden `<input>`
    if ($markdown_off) {
      $markdown_off.remove();
    }

    // Convert the form values to Markdown comment
    this.inserted_fieldsets.forEach($fieldset => this.add_comment(this.create_comment($fieldset)));

    try {
      // Submit the form data via XHR before API requests to make sure the change is notified via email
      await new Promise((resolve, reject) => {
        const request = new XMLHttpRequest();

        request.open('POST', `${BUGZILLA.config.basepath}attachment.cgi`);
        request.addEventListener('load', () => resolve());
        request.addEventListener('error', () => reject());
        request.send(new FormData(this.$form));
      });
    } catch (ex) {
      alert('The form could not be submitted. Please try again later.');

      // Restore the Submit button
      this.$submit.disabled = this.submitting = false;
      this.$status.textContent = '';

      // Stay on the same page for recovery
      return false;
    }

    this.$status.textContent = 'Updating flags…';

    // Request approval for other patches if any
    for (const $fieldset of this.inserted_fieldsets) {
      const ids = [...$fieldset.querySelectorAll('tr.other-patches input:checked')]
        .map($input => Number($input.dataset.id));
      const flags = this.find_selectors($fieldset).map($select => ({ name: $select.dataset.name, status: '?' }));

      if (ids.length && flags.length) {
        requests.push(Bugzilla.API.put(`bug/attachment/${ids[0]}`, { ids, flags }));
      }
    }

    // Collect bug flags from checkboxes
    const flags = [...this.$fieldset_wrapper.querySelectorAll('input[data-bug-flag]:checked')]
      .map($input => ({ name: $input.getAttribute('data-bug-flag'), status: '+' }));

    // Update bug flags if needed
    if (flags.length) {
      requests.push(Bugzilla.API.put(`bug/${this.bug_id}`, { flags }));
    }

    try {
      // Send all the API requests
      await Promise.all(requests);
    } catch (ex) {
      // Just show an alert, because it's hard to only recover specific flags
      alert('One or more flags could not be updated. Please try again later.');
    }

    this.$status.textContent = 'Redirecting to the bug…';

    // Redirect to the bug once everything is done
    location.href = `${BUGZILLA.config.basepath}show_bug.cgi?id=${this.bug_id}`;

    return false;
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.FlagTypeComment());
