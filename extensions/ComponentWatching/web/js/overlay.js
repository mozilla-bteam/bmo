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
var Bugzilla = Bugzilla || {};

/**
 * Implement the basic One-Click Component Watching functionality.
 * @abstract
 */
Bugzilla.ComponentWatching = class ComponentWatching {
  /**
   * Initialize a new ComponentWatching instance.
   */
  constructor() {
    this.api_endpoint = '/rest/component_watching';
    this.tracking_category = 'Component Watching';
  }

  /**
   * Send a REST API request, and return the results in a Promise.
   * @param {Object} [request] Request data. If omitted, the current watch list will be returned.
   * @returns {Promise<Object|String>} Response data or error message.
   */
  async fetch(request = {}) {
    request.url = this.api_endpoint + (request.path || '');
    delete request.path;

    return new Promise((resolve, reject) => bugzilla_ajax(request, data => resolve(data), error => reject(error)));
  }

  /**
   * Start watching the current product or component.
   * @param {String} product Product name.
   * @param {String} [component] Component name. If omitted, all components in the product will be watched.
   * @returns {Promise<Object|String>} Response data or error message.
   */
  async watch(product, component = '') {
    return this.fetch({ type: 'POST', data: { product, component } });
  }

  /**
   * Stop watching the current product or component.
   * @param {Number} id Watching ID.
   * @returns {Promise<Object|String>} Response data or error message.
   */
  async unwatch(id) {
    return this.fetch({ type: 'DELETE', path: `/${id}` });
  }

  /**
   * Log an event with Google Analytics if possible. For privacy reasons, we don't send any specific product or
   * component name.
   * @param {String} action `watch` or `unwatch`.
   * @param {String} type `product` or `component`.
   * @param {Number} code `0` for a successful change, `1` otherwise.
   * @see https://developers.google.com/analytics/devguides/collection/analyticsjs/events
   */
  track_event(action, type, code) {
    if ('ga' in window) {
      ga('send', 'event', this.tracking_category, action, type, code);
    }
  }
};

/**
 * Implement the One-Click Component Watching buttons on the modal-style bug page. One button is for watching all
 * components in the current product, and another one is for watching just the current product.
 */
Bugzilla.ComponentWatching.BugModalOverlay = class BugModalOverlay extends Bugzilla.ComponentWatching {
  /**
   * Initialize a new BugModalOverlay instance.
   */
  constructor() {
    super();

    this.tracking_category = 'BugModal: Component Watching';

    this.$product_select = document.querySelector('#product');
    this.$product_watch = document.querySelector('#product-watch-btn');
    this.$component_select = document.querySelector('#component');
    this.$component_watch = document.querySelector('#component-watch-btn');

    this.product = this.$product_select.value;
    this.component = this.$component_select.value;
    this.watching_product = this.watching_component = false;
    this.watching_id = undefined;

    this.init();
  }

  /**
   * Show a short floating message on the page. This code is from bug_modal.js, requiring jQuery.
   * @param {String} message Message text.
   */
  show_message(message) {
    $('#floating-message-text').text(message);
    $('#floating-message').fadeIn(250).delay(2500).fadeOut();
  }

  /**
   * Update the UI of the buttons depending on the current watch status.
   */
  update_buttons() {
    this.$product_watch.disabled = false;
    this.$product_watch.dataset.action = this.watching_product ? 'unwatch' : 'watch';
    this.$product_watch.textContent = this.watching_product ? 'Unwatch' : 'Watch';
    this.$product_watch.title = this.watching_product ?
      `Stop watching all components in the ${this.product} product` :
      `Start watching all components in the ${this.product} product`;

    this.$component_watch.disabled = this.watching_product;
    this.$component_watch.dataset.action = this.watching_component ? 'unwatch' : 'watch';
    this.$component_watch.textContent = this.watching_component ? 'Unwatch' : 'Watch';
    this.$component_watch.title = this.watching_component ?
      `Stop watching the ${this.component} component` :
      `Start watching the ${this.component} component`;
  }

  /**
   * Retrieve the current watch list, and initialize the status and UI.
   */
  async init() {
    try {
      const watches = await this.fetch();

      // Check if the current product is being watched
      let watch = watches.find(watch => this.product === watch.product_name && !watch.component_name);

      if (watch) {
        this.watching_product = this.watching_component = true;
        this.watching_id = watch.id;
      } else {
        // Check if the current component is being watched
        watch = watches.find(watch => this.product === watch.product_name && this.component === watch.component_name);

        if (watch) {
          this.watching_component = true;
          this.watching_id = watch.id;
        }
      }

      this.$product_watch.addEventListener('click', () => this.button_onclick('product'));
      this.$component_watch.addEventListener('click', () => this.button_onclick('component'));

      this.update_buttons();
    } catch (ex) {
      // Remove the buttons as no actions can be done
      this.$product_watch.remove();
      this.$component_watch.remove();
    }
  }

  /**
   * Called whenever the product or component's Watch/Unwatch button is clicked. Send a request and update the watch
   * status accordingly.
   * @param {String} type `product` or `component`.
   */
  async button_onclick(type) {
    const is_product = type === 'product';
    const $button = is_product ? this.$product_watch : this.$component_watch;
    const { action } = $button.dataset;
    const to_watch = action === 'watch';
    let message = '';
    let code = 0;

    // Disable the button until the request is complete
    $button.disabled = true;

    try {
      if (to_watch) {
        await this.watch(this.product, is_product ? '' : this.component).then(watch => this.watching_id = watch.id);

        message = is_product ?
          `You are now watching all components in the ${this.product} product` :
          `You are now watching the ${this.component} component`;
      } else {
        await this.unwatch(this.watching_id).then(() => this.watching_id = undefined);

        message = is_product ?
          `You are no longer watching all components in the ${this.product} product` :
          `You are no longer watching the ${this.component} component`;
      }

      this.watching_product = to_watch && is_product;
      this.watching_component = to_watch;
    } catch (ex) {
      message = 'Your watch list could not be updated. Please try again later.';
      code = 1;
    }

    this.show_message(message);
    this.update_buttons();
    this.track_event(action, type, code);
  }
};
