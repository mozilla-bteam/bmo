/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

function SetCheckboxes(value) {
  let elements = document.querySelectorAll("input[type='checkbox'][name^='id_']");
  for (let item of elements) {
    item.checked = value;
  }
}

document.addEventListener("DOMContentLoaded", () => {
  let check_all = document.getElementById("check_all");
  let uncheck_all = document.getElementById("uncheck_all");
  if (check_all) {
    check_all.addEventListener("click", event => {
      SetCheckboxes(true);
      event.preventDefault();
    });
  }
  if (uncheck_all) {
    uncheck_all.addEventListener("click", event => {
      SetCheckboxes(false);
      event.preventDefault();
    });
  }
});

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

/**
 * Implement the features on the search results page.
 */
Bugzilla.SearchResults = class SearchResults {
  /**
   * Initialize a new `SearchResults` instance.
   */
  constructor() {
    const { name, query, bugs, sort } = document.querySelector('meta[name="search-results"]').dataset;
    const $table = document.querySelector('.bz_buglist');

    this.url = new URL(location);
    this.results = { id: Date.now(), name, query, bugs: JSON.parse(`[${bugs}]`), sort };

    // Rewrite the URL if this is not a Quick Search
    if (!this.url.searchParams.has('quicksearch')) {
      this.url.search = `?${query}`;
    }

    this.update_url();

    // Stop here if no bugs found, the bug list is in the bulk edit mode, or the data could not be cached
    if (!$table || this.url.searchParams.has('tweak') || !this.cache_results()) {
      return this;
    }

    $table.addEventListener('click', event => this.table_onclick(event));
    $table.addEventListener('sorted', event => this.table_onsorted(event));
  }

  /**
   * Override the URL if the query is not too big.
   */
  update_url() {
    const url = this.url.toString();

    if (url.length > 8000) {
      return;
    }

    history.replaceState(history.state, document.title, url);
  }

  /**
   * Cache the current search results in the local storage. Given that multiple search results can be opened at the same
   * time in browser tabs, the storage is accessed every time the data is saved.
   * @returns {Boolean} `true` if data could be successfully saved, `false` otherwise.
   */
  cache_results() {
    try {
      /** @throws {SecurityError} */
      const cache = JSON.parse(localStorage.getItem('search-results') || '[]');
      const index = cache.findIndex(({ id, query }) => id === this.results.id || query === this.results.query);

      // Remove duplicated or old results (max 10) and prepend new results
      cache.splice(index > -1 ? index : 9, 1);
      cache.unshift(this.results);

      localStorage.setItem('search-results', JSON.stringify(cache));

      return true;
    } catch (ex) {
      return false;
    }
  }

  /**
   * Called whenever the bug table is clicked. If the event target is a bug link, cache the current list ID temporarily
   * in the local storage so it will be passed to the linked bug page.
   * @param {MouseEvent} event `click` event.
   * @returns {Boolean} Always `true` so the link will be followed.
   */
  table_onclick(event) {
    const bug_id = Number(event.target.dataset.bugId || 0) || undefined;

    if (bug_id) {
      localStorage.setItem('search-nav-list-id', JSON.stringify({ list_id: this.results.id, bug_id }));
    }

    return true;
  }

  /**
   * Called whenever the bug table is sorted. Cache the sorted bug list and new sort condition, and update URL params.
   * @param {CustomEvent} event `sorted` event fired on the table.
   */
  table_onsorted(event) {
    const { bugs, sort } = event.detail;

    this.results.bugs = bugs;
    this.results.sort = sort;

    this.cache_results();
    this.update_url();
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.SearchResults(), { once: true });
