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
 * Implement features in the "Change Several Bugs at Once" bulk editor.
 */
Bugzilla.BulkEditor = class BulkEditor {
  /**
   * Initialize a new BulkEditor instance.
   */
  constructor() {
    this.$form = document.querySelector('form[name="changeform"]');
    this.multi_product = this.$form.matches('[data-one-product="false"]');
    this.product_data = {};

    this.checkboxes = [...document.querySelectorAll('input[type="checkbox"][name^="id_"]')];

    document.querySelector('#check_all').addEventListener('click', event => this.set_checkboxes(event));
    document.querySelector('#uncheck_all').addEventListener('click', event => this.set_checkboxes(event));

    if (this.multi_product) {
      document.querySelector('#product').addEventListener('change', event => this.on_product_selected(event));
      this.checkboxes.forEach($checkbox => $checkbox.addEventListener('change', () => this.on_bug_selected()));
    }
  }

  /**
   * Change the checkbox status when the Check All or Uncheck All button is clicked.
   * @param {MouseEvent} event `click` event.
   */
  set_checkboxes(event) {
    event.preventDefault();

    const checked = event.target.id === 'check_all';

    for (const $checkbox of this.checkboxes) {
      $checkbox.checked = checked;
    }

    if (this.multi_product) {
      this.on_bug_selected();
    }
  }

  /**
   * Called whenever a bug is selected or unselected. Provide options in the Component, Version and Target Milestone
   * fields if the selected bugs are in the same product.
   */
  async on_bug_selected() {
    const checked = this.checkboxes.filter(({ checked }) => checked);
    const products = [...(new Set(checked.map(({ dataset }) => dataset.product)))];
    const one_product = products.length === 1;
    const product = one_product ? products[0] : undefined;

    if (this.manually_selected_product || this.automatically_selected_product === product) {
      return;
    }

    this.automatically_selected_product = product;
    this.update_product_fields(product, false);
  }

  /**
   * Called whenever the Product field is changed. Provide options in the Component, Version and Target Milestone fields
   * if a valid product is selected. This prevent the "Verify Version, Component, Target Milestone" intermediate page
   * from being displayed after submitting the changes.
   * @param {Event} event `change` event on the product dropdown list.
   */
  async on_product_selected(event) {
    const { value } = event.target;
    const product = value !== '--do_not_change--' ? value : undefined;

    this.manually_selected_product = product;
    this.update_product_fields(product, !!product);
  }

  /**
   * Update the Component, Version and Target Milestone field values that depend on the product.
   * @param {String} product Selected product.
   * @param {Boolean} required Whether to add options instead of
   */
  async update_product_fields(product, required) {
    let data;

    if (product) {
      data = this.product_data[product];

      if (!data) {
        try {
          data = this.product_data[product]
            = await Bugzilla.API.get(`bug_modal/new_product/${Number(this.checkboxes[0].dataset.id)}`, { product });
        } catch (ex) {
          return;
        }
      }
    }

    for (const key of ['component', 'version', 'target_milestone']) {
      const $select = document.getElementById(key);
      const options = [];

      if (!product || !required) {
        options.push('<option value="--do_not_change--" selected="selected">--do_not_change--</option>');
      }

      if (product) {
        for (const { name, selected } of data[key]) {
          const _value = name.htmlEncode();

          options.push(`<option value="${_value}"${selected && required ? ' selected' : ''}>${_value}</option>`);
        }
      }

      $select.innerHTML = options.join('');
      $select.required = required;
      $select.classList.toggle('attention', required);
    }
  }
};

window.addEventListener('DOMContentLoaded', () => {
  new Bugzilla.BulkEditor();
}, { once: true });
