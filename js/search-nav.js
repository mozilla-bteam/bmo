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
 * Implement the prev/next navigation on the bug page, which shows the user's recent search results.
 */
Bugzilla.SearchNav = class SearchNav {
  /**
   * Initialize a new `SearchNav` instance.
   */
  constructor() {
    this.url = new URL(location);

    // Define keyboard shortcuts including u, j and k that correspond to Gmail
    this.shortcut_keys = { index: ['u'], first: ['{'], prev: ['[', 'j'], next: [']', 'k'], last: ['}'] };

    if (!this.check_data()) {
      return this;
    }

    this.activate();
    this.cache_state();
    this.enable_next_bug_navigation();

    window.addEventListener('keydown', event => this.handle_keydown(event));
  }

  /**
   * Check if the current bug can be found in the recent search results cached in the local storage, and find siblings
   * such as the previous and next bugs.
   * @returns {Boolean} `true` if data could be found, `false` otherwise.
   */
  check_data() {
    let cache = [];

    try {
      cache = JSON.parse(localStorage.getItem('search-results') || '[]');
    } catch (ex) {}

    if (!cache.length) {
      return false;
    }

    const { bug_id } = BUGZILLA;
    const list_id_state = (history.state || {}).list_id;
    const list_id_cache = JSON.parse(localStorage.getItem('search-nav-list-id') || null);
    let results;

    if (list_id_state) {
      // Temporary cache in the history state
      results = cache.find(results => results.id === list_id_state);
    } else if (list_id_cache && list_id_cache.bug_id === bug_id) {
      // Temporary cache in the local storage
      results = cache.find(results => results.id === list_id_cache.list_id);
      localStorage.removeItem('search-nav-list-id');
    } else {
      results = cache.find(results => results.bugs.find(id => id === bug_id));
    }

    if (!results) {
      return false;
    }

    const { bugs } = results;
    const index = this.index = bugs.findIndex(id => id === bug_id);
    const total = this.total = bugs.length;

    if (total === 1) {
      return false;
    }

    this.results = results;
    this.list_id = results.id;
    this.bug_ids = {
      first: index > 1 ? bugs[0] : null,
      prev: index > 0 ? bugs[index - 1] : null,
      next: index < total - 1 ? bugs[index + 1] : null,
      last: index < total - 2 ? bugs[total - 1] : null,
    };

    return true;
  }

  /**
   * Show the current bug's position in the search results, and activate the links for the results page and siblings.
   */
  activate() {
    const { config: { basepath } } = BUGZILLA;

    const activate_link = $link => {
      $link.setAttribute('aria-keyshortcuts', this.shortcut_keys[$link.rel].join(' '));
      $link.removeAttribute('tabindex');
      $link.removeAttribute('aria-disabled');
    };

    this.$nav = document.querySelector('#search-nav');
    this.$nav.removeAttribute('aria-disabled');

    const $position = this.$nav.querySelector('.position');
    const $index = this.$nav.querySelector('[rel="index"]');

    this.params = new URLSearchParams(this.results.query);
    this.params.set('sort', this.results.sort);

    if (this.results.name) {
      this.params.set('title', this.results.name);
      $index.title = this.results.name;
    }

    $position.textContent =
      $position.textContent.replace('{ $position }', this.index + 1).replace('{ $total }', this.total);
    $position.hidden = false;
    $index.href = `${basepath}buglist.cgi?${this.params.toString()}`;
    activate_link($index);

    if ($index.href.length > 8000) {
      $index.addEventListener('click', event => this.submit_form(event));
    }

    for (const [rel, id] of Object.entries(this.bug_ids)) {
      const $link = this.$nav.querySelector(`a[rel="${rel}"]`);

      if (id) {
        $link.href = `${basepath}show_bug.cgi?id=${id}`;
        $link.setAttribute('data-bug-id', id);
        $link.addEventListener('click', event => this.cache_list_id(event));
        $link.addEventListener('mouseover', () => this.add_tooltip());
        activate_link($link);
      }
    }
  }

  /**
   * Add a tooltip to each bug link that shows some basic info of the bug.
   * @deprecated This will be replaced by bug hovercards. (Bug 1146763)
   */
  async add_tooltip() {
    if (this.tooltip_added) {
      return;
    }

    this.tooltip_added = true;

    try {
      const { bugs } = await Bugzilla.API.get('bug', {
        id: Object.values(this.bug_ids).filter(id => id).join(','), // Exclude `null` from bug IDs
        include_fields: ['id', 'summary', 'status', 'resolution']
      });

      for (const { id, summary, status, resolution } of bugs) {
        for (const $link of this.$nav.querySelectorAll(`[data-bug-id="${id}"]`)) {
          $link.title = `${id} - ${status}${resolution ? ` ${resolution}` : ''} - ${summary}`;
        }
      }
    } catch (ex) {}
  }

  /**
   * Cache the current list ID in the history state for later use.
   */
  cache_state() {
    const { list_id } = this;

    history.replaceState(Object.assign(history.state || {}, { list_id }), BUGZILLA.bug_title, this.url);
  }

  /**
   * Allow to navigate to the next bug after the form is submitted, if the user has enabled the option.
   */
  enable_next_bug_navigation() {
    const $form = document.querySelector('#changeform');
    const bug_id = this.bug_ids.next;

    if ($form && bug_id) {
      $form.insertAdjacentHTML('afterbegin', `<input type="hidden" name="next_bug_id" value="${bug_id}">`);
    }
  }

  /**
   * Called whenever a key is pressed on the page. Navigate to other bug if a keyboard shortcut is used.
   * @param {KeyboardEvent} event `keydown` event.
   */
  handle_keydown(event) {
    const { target, isComposing, key } = event;
    let $link;

    // Check if the user is not typing in a form nor doing IME composition
    if ('value' in target || isComposing) {
      return;
    }

    for (const [rel, keys] of Object.entries(this.shortcut_keys)) {
      if (keys.includes(key)) {
        $link = this.$nav.querySelector(`a[rel="${rel}"]`);
        break;
      }
    }

    if (!$link || !$link.href) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();

    // Trigger the `click` event so `cache_list_id()` or `submit_form()` will be called
    $link.click();
  }

  /**
   * Called whenever a navigation link is clicked. Cache the current list ID temporarily in the local storage so it will
   * be passed to the linked bug page.
   * @param {MouseEvent} event `click` event.
   * @returns {Boolean} Always `true` so the link will be followed.
   */
  cache_list_id(event) {
    const { list_id } = this;
    const bug_id = Number(event.target.dataset.bugId);

    localStorage.setItem('search-nav-list-id', JSON.stringify({ list_id, bug_id }));

    return true;
  }

  /**
   * Called whenever the "Back to Search Results" link is clicked. In this case, the URL is too long for a GET request,
   * so create a temporary form and submit it using a POST request.
   * @param {MouseEvent} event `click` event.
   * @returns {Boolean} Always `false` so the link won't be followed.
   */
  submit_form(event) {
    const { ctrlKey, metaKey } = event;
    const accelKey = navigator.platform === 'MacIntel' ? metaKey && !ctrlKey : ctrlKey;
    const params = [...this.params.entries()];

    this.$nav.insertAdjacentHTML('beforeend', `
      <form method="post" action="${event.target.pathname}" target="${accelKey ? '_blank' : '_self'}">
      ${params.map(([name, value]) => `<input type="hidden" name="${name}" value="${value}">`).join('')}</form>`);
    this.$nav.querySelector('form').submit();

    event.preventDefault();
    event.stopPropagation();

    return false;
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.SearchNav(), { once: true });
