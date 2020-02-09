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
 * Implement simple expander functionality that shows or hides certain UI elements, saves the current state in local
 * storage, and restores the state when the user revisits the page.
 * @example js/create_bug.js
 * @example js/advanced-search.js
 */
Bugzilla.Expander = class Expander {
  /**
   * Initialize a new Expander instance.
   * @param {HTMLElement} $controller Element that controls other elements.
   */
  constructor($controller) {
    this.$controller = $controller;
    this.target_class = this.$controller.getAttribute('data-expander-target');
    this.cache_key = `expander:${this.target_class}`;

    this.restore();

    this.$controller.tabIndex = 0;
    this.$controller.addEventListener('click', event => this.toggle(event));
    this.$controller.setAttribute('role', 'button');

    // Assign the `aria-controls` attribute, even though we are not using this in Expander
    this.$controller.setAttribute('aria-controls', this.targets.map($element => {
      // If the element doesn’t have an ID, assign a random one first
      if (!$element.id) {
        $element.id = `e${Bugzilla.String.generate_hash()}`;
      }

      return $element.id;
    }).join(' '));
  }

  /**
   * Get a list of one or more target elements.
   * @type {Array.<HTMLElement>}
   */
  get targets() {
    return [...document.querySelectorAll(`.${this.target_class}`)];
  }

  /**
   * Restore the previous state. If state is not found in local storage, check if the `aria-expanded` attribute is set
   * on the controller. Otherwise, hide the target element(s) by default.
   */
  restore() {
    const cache = window.localStorage.getItem(this.cache_key);

    if (cache && cache.match(/^[01]$/)) {
      this.hidden = Number(cache) === 0;
    } else if (this.$controller.hasAttribute('aria-expanded')) {
      this.hidden = this.$controller.matches('[aria-expanded="false"]');
    } else {
      this.hidden = true;
    }

    if (this.hidden) {
      this.targets.forEach($element => {
        $element.classList.add('bz_tui_hidden');
        $element.setAttribute('aria-hidden', 'true');
      });
      this.toggle_controller();
    }

    this.$controller.setAttribute('aria-expanded', this.hidden ? 'false' : 'true');
  }

  /**
   * Hide the target element(s) if they are shown, or show them if they are hidden. Fire an event and save the state.
   * Note: TUI stands for Tweak UI.
   * @param {MouseEvent} event `click` event fired on the controller.
   * @fires Expander#toggle
   */
  toggle(event) {
    event.preventDefault();

    const hidden = this.hidden = !this.hidden;

    this.targets.forEach($element => {
      $element.classList.toggle('bz_tui_hidden', hidden);
      $element.setAttribute('aria-hidden', hidden);
    });

    this.toggle_controller();
    this.$controller.dispatchEvent(new CustomEvent('Expander#toggle', { detail: { hidden } }));
    this.$controller.setAttribute('aria-expanded', hidden ? 'false' : 'true');
    window.localStorage.setItem(this.cache_key, hidden ? 0 : 1);
  }

  /**
   * Toggle the controller’s label. An alternative label can be defined with the `data-expander-alt-text` attribute.
   */
  toggle_controller() {
    const alt_text = this.$controller.getAttribute('data-expander-alt-text');
    let original_text;

    if (!alt_text) {
      return;
    }

    if (this.$controller.matches('input')) {
      original_text = this.$controller.value;
      this.$controller.value = alt_text;
    } else {
      original_text = this.$controller.innerHTML;
      this.$controller.innerHTML = alt_text;
    }

    this.$controller.setAttribute('data-expander-alt-text', original_text);
  }
};
