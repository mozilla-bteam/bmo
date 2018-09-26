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
    this.templates = [...document.querySelectorAll('template.approval-request')];
    this.$flags = document.querySelector('#flags');
    this.$comment = document.querySelector('#comment');

    if (this.$flags && this.$comment) {
      this.selects = [...this.$flags.querySelectorAll('.flag_select')];
      this.selects.forEach($select => $select.addEventListener('change', () => this.flag_onselect($select)));
      this.$comment.form.addEventListener('submit', () => this.form_onsubmit());
    }
  }

  /**
   * Check if a `<fieldset>` is compatible with the given flag. For example, `approval‑mozilla‑beta` matches
   * `<fieldset data-flags="approval‑mozilla‑beta approval‑mozilla‑release">` while `approval‑mozilla‑esr60`
   * matches `<fieldset data-flags="approval‑mozilla‑esr*">`.
   * @param {String} name Flag name, such as `approval‑mozilla‑beta`.
   * @param {(HTMLFieldSetElement|HTMLTemplateElement)} $element `<fieldset>` or `<template>` element with the
   * `data-flags` attribute which is a space-separated list of flag names (wildcard chars can be used).
   * @returns {Boolean} Whether the `<fieldset>` is compatible.
   */
  check_compatibility(name, $element) {
    return !!$element.dataset.flags.split(' ')
      .find(_name => !!name.match(new RegExp(`^${_name.replace('*', '.+')}$`, 'i')));
  }

  /**
   * Return a list of temporary `<fieldset>`s already inserted to the current page.
   * @type {Array<HTMLFieldSetElement>}
   */
  get inserted_fieldsets() {
    return [...this.$flags.parentElement.querySelectorAll('fieldset.approval-request')];
  }

  /**
   * Find a temporary `<fieldset>` already inserted to the current page by a flag name.
   * @param {String} name Flag name, such as `approval‑mozilla‑beta`.
   * @returns {HTMLFieldSetElement} Any `<fieldset>` element.
   */
  find_inserted_fieldset(name) {
    return this.inserted_fieldsets.find($fieldset => this.check_compatibility(name, $fieldset));
  }

  /**
   * Find an available `<fieldset>` embedded in HTML by a flag name.
   * @param {String} name Flag name, such as `approval‑mozilla‑beta`.
   * @returns {HTMLFieldSetElement} Any `<fieldset>` element.
   */
  find_available_fieldset(name) {
    for (const $template of this.templates) {
      if (this.check_compatibility(name, $template)) {
        const $fieldset = $template.content.cloneNode(true).querySelector('fieldset');

        $fieldset.className = 'approval-request';
        $fieldset.dataset.flags = $template.dataset.flags;

        return $fieldset;
      }
    }

    return null;
  }

  /**
   * Find a `<select>` element for a requested flag that matches the given `<fieldset>`.
   * @param {HTMLFieldSetElement} $fieldset `<fieldset>` element with the `data-flags` attribute.
   * @returns {HTMLSelectElement} Any `<select>` element.
   */
  find_select($fieldset) {
    return this.selects
      .find($_select => $_select.value === '?' && this.check_compatibility($_select.dataset.name, $fieldset));
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
  flag_onselect($select) {
    const id = Number($select.dataset.id);
    const { name } = $select.dataset;
    const state = $select.value;
    let $fieldset = this.find_inserted_fieldset(name);

    // Remove the temporary `<fieldset>` if not required. One `<fieldset>` can support multiple flags, so, for example,
    // if `approval‑mozilla‑release` is unselected but `approval‑mozilla‑beta` is still selected, keep it
    if (state !== '?' && $fieldset && !this.find_select($fieldset)) {
      $fieldset.remove();
    }

    // Insert a temporary `<fieldset>` if available
    if (state === '?' && !$fieldset) {
      $fieldset = this.find_available_fieldset(name);

      if ($fieldset) {
        this.$flags.parentElement.appendChild($fieldset);
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
  }

  /**
   * Convert the input values into comment text and remove the temporary `<fieldset>` before submitting the form.
   * @returns {Boolean} Always `true` to allow submitting the form.
   */
  form_onsubmit() {
    for (const $fieldset of this.inserted_fieldsets) {
      const text = [
        `[${$fieldset.querySelector('legend').innerText}]`,
        ...[...$fieldset.querySelectorAll('tr')].map($tr => {
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

          return `${label}: ${value}`;
        }),
      ].join('\n\n');

      this.add_comment(text);
      $fieldset.remove();
    }

    return true;
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.FlagTypeComment());
