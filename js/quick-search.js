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
 * Enhance the quick search bar on the global header so the user can search/filter their recent bugs, saved searches,
 * components, keywords and more.
 */
Bugzilla.QuickSearch = class QuickSearch {
  /**
   * Initialize a new QuickSearch instance.
   */
  constructor() {
    this.$form = document.querySelector('#header-search');
    this.$searchbox = document.querySelector('#quicksearch_top');
    this.$dropdown = document.querySelector('#header-search-dropdown');
    this.sections = {};
    this.data = { recent: [], shortcuts: [], saved: [], products: [], keywords: [] };
    this.initialized = false;
    this.alt_pressed = false;

    this.$dropdown.querySelectorAll('section').forEach($section => this.sections[$section.dataset.type] = $section);

    this.$form.addEventListener('submit', () => this.form_onsubmit());
    this.$searchbox.addEventListener('focus', () => this.searchbox_onfocus());
    this.$searchbox.addEventListener('keydown', event => this.searchbox_onkeydown(event));
    this.$searchbox.addEventListener('keyup', event => this.searchbox_onkeydown(event));
    this.$searchbox.addEventListener('input', () => this.searchbox_oninput());
  }

  /**
   * Get the current search terms entered in the search box.
   * @type {String}
   */
  get input() {
    return this.$searchbox.value.trim();
  }

  /**
   * Show search results in the dropdown menu's specific section.
   * @param {HTMLElement} $section A section in the dropdown menu.
   * @param {String} input Search terms.
   * @param {Object[]} results Search results.
   * @param {String} results.label Link text.
   * @param {Boolean} [results.label_encoded] Whether the label can be safely inserted to HTML.
   * @param {String} results.link Link URL.
   * @param {String} [results.type] Bug type.
   * @param {Boolean} [highlight] `true` to highlight search terms, `false` to use the provided label as is, without
   * escaping any contained HTML tags.
   */
  show_results($section, input, results, highlight = true) {
    const $results = $section.querySelector('ul');
    const $fragment = document.createDocumentFragment();

    for (const { label, label_encoded = false, link, type } of results) {
      const $placeholder = document.createElement('ul');

      $placeholder.innerHTML = `
        <li role="none">
          <a role="option" href="${BUGZILLA.config.basepath}${link.htmlEncode()}">
            ${type ? `
              <span class="bug-type-label iconic" title="${type}" aria-label="${type}" data-type="${type}">
                <span class="icon" aria-hidden="true"></span>
              </span>
            ` : ''}
            ${highlight ? Bugzilla.String.highlight(label, input) : label_encoded ? label : label.htmlEncode()}
          </a>
        </li>
      `;

      const $a = $fragment.appendChild($placeholder.firstElementChild).querySelector('a');

      // Allow Alt+click on the link to search all bugs matching the criteria (see `searchbox_onkeydown()` below)
      $a.addEventListener('click', event => {
        if (this.alt_pressed) {
          event.preventDefault();
          location.href = $a.href;
        }
      });

      // Activate dropdown menu item effects (see dropdown.js)
      $a.addEventListener('mouseover', () => $a.classList.add('active'));
      $a.addEventListener('mouseout', () => $a.classList.remove('active'));
    }

    $results.innerHTML = '';
    $results.appendChild($fragment);
    $section.hidden = !results.length;
  }

  /**
   * Show the current search terms on the dropdown list.
   * @param {String} [input] Search terms.
   */
  show_search_terms(input = this.input.trim()) {
    this.show_results(this.sections.terms, input, input ? [{
      label: Bugzilla.L10n.get(`search_terms_in_${this.alt_pressed ? 'all' : 'open'}_bugs`, input.htmlEncode()),
      link: `buglist.cgi?quicksearch=${encodeURIComponent(input)}`,
      label_encoded: true,
    }] : [], false);
  }

  /**
   * Show filtered recent bugs on the dropdown list.
   * @param {String} [input] Search terms.
   */
  show_recent_bugs(input = this.input.trim()) {
    let results = this.data.recent;

    if (input && results.length) {
      results = results
        .filter(({ id, alias, summary }) => Bugzilla.String.find(`${id} ${alias || ''} ${summary}`, input));
    }

    this.show_results(this.sections.recent, input, results.slice(0, 5).map(({ id, alias, summary, type }) => ({
      label: `${id}${alias ? ` (${alias})` : ''} - ${summary}`,
      link: `show_bug.cgi?id=${id}`,
      type
    })));
  }

  /**
   * Search bugs from the remote Bugzilla instance. Search for a matching bug ID and aliases if the input is numeric.
   * Search only for aliases if the input is not numeric.
   * @param {String} [input] Search terms.
   * @returns {Promise.<Object[]>} List of bugs.
   */
  async fetch_shortcut_bugs(input = this.input.trim()) {
    if (!input) {
      return Promise.resolve([]);
    }

    try {
      let { bugs } = await Bugzilla.API.get('bug', Object.assign(isNaN(input) ? {
        f1: 'alias', o1: 'anywordssubstr', v1: input,
        f2: 'resolution', o2: 'isempty',
      } : {
        j_top: 'OR',
        f1: 'bug_id', o1: 'equals', v1: input,
        f2: 'OP',
        f3: 'alias', o3: 'anywordssubstr', v3: input,
        f4: 'resolution', o4: 'isempty',
        f5: 'CP',
      }, {
        include_fields: 'id,alias,summary,type,last_change_time',
      }));

      // Sort by last modified date
      bugs = bugs.sort((a, b) => new Date(a.last_change_time) < new Date(b.last_change_time));

      if (!isNaN(input)) {
        // Move the bug with the matched ID to first
        bugs = [bugs.find(bug => bug.id === Number(input)), ...bugs.filter(bug => bug.id !== Number(input))];
      }

      return Promise.resolve(bugs);
    } catch (ex) {
      return Promise.resolve([]);
    }
  }

  /**
   * Show filtered shortcuts bugs, excluding recent bugs, on the dropdown list.
   * @param {String} [input] Search terms.
   */
  show_shortcut_bugs(input = this.input.trim()) {
    let results = this.data.shortcuts;

    if (input && results.length) {
      results = results
        .filter(({ id }) => !this.data.recent.find(bug => bug.id === id))
        .filter(({ id, alias, summary }) => Bugzilla.String.find(`${id} ${alias || ''} ${summary}`, input));
    }

    this.show_results(this.sections.shortcuts, input, results.slice(0, 5).map(({ id, alias, summary, type }) => ({
      label: `${id}${alias ? ` (${alias})` : ''} - ${summary}`,
      link: `show_bug.cgi?id=${id}`,
      type
    })));
  }

  /**
   * Show filtered saved search items on the dropdown list.
   * @param {String} [input] Search terms.
   */
  show_saved_searches(input = this.input.trim()) {
    if (!this.sections.saved) {
      return;
    }

    let results = this.data.saved;

    if (input && results.length) {
      results = results.filter(({ name }) => Bugzilla.String.find(name, input));
    }

    // If no search terms are provided, show all saved searches as rendered in HTML by default
    this.show_results(this.sections.saved, input, results.slice(0, input ? 5 : undefined).map(({ name, link }) => ({
      label: name,
      link,
    })));
  }

  /**
   * Show filtered products/components on the dropdown list.
   * @param {String} [input] Search terms.
   */
  show_products(input = this.input.trim()) {
    const results = [];

    if (input) {
      // Find components by name
      for (const { name: product, components } of this.data.products) {
        for (const { name: component } of components) {
          if (Bugzilla.String.find(`${product} ${component}`, input)) {
            results.push({ product, component });
          }
        }
      }
    }

    this.show_results(this.sections.products, input, results.slice(0, 5).map(({ product, component }) => ({
      label: `${product} :: ${component}`,
      link: `buglist.cgi?quicksearch=${encodeURIComponent(`product:"${product}" component:"${component}"`)}`,
    })));
  }

  /**
   * Show filtered bug keywords on the dropdown list.
   * @param {String} [input] Search terms.
   */
  show_keywords(input = this.input.trim()) {
    const results = input ? this.data.keywords.filter(({ name }) => Bugzilla.String.find(name, input)) : [];

    this.show_results(this.sections.keywords, input, results.slice(0, 5).map(({ name }) => ({
      label: name,
      link: `buglist.cgi?quicksearch=${encodeURIComponent(`keywords:${name}`)}`,
    })));
  }

  /**
   * When Alt key is pressed, change all the quick search links to allow searching all bugs instead of only open bugs.
   * This is done by prepending "ALL" to search queries.
   * @see https://bugzilla.mozilla.org/page.cgi?id=quicksearch.html
   */
  toggle_all_bugs_search() {
    const $search_link = this.sections.terms.querySelector(`a[href^="${BUGZILLA.config.basepath}buglist.cgi"]`);
    const link_open = `${BUGZILLA.config.basepath}buglist.cgi?quicksearch=`;
    const link_all = `${link_open}ALL+`;

    // Replace the link label for the current search terms
    if ($search_link) {
      $search_link.innerHTML =
        Bugzilla.L10n.get(`search_terms_in_${this.alt_pressed ? 'all' : 'open'}_bugs`, this.input.htmlEncode());
    }

    // Replace all the quicksearch URLs
    for (const $link of this.$dropdown.querySelectorAll(`a[href^="${BUGZILLA.config.basepath}buglist.cgi"]`)) {
      const href = $link.getAttribute('href');
      const has_all = href.startsWith(link_all);

      if (this.alt_pressed) {
        if (!has_all) {
          $link.setAttribute('href', href.replace(link_open, link_all));
        }
      } else {
        if (has_all) {
          $link.setAttribute('href', href.replace(link_all, link_open));
        }
      }
    }
  }

  /**
   * Called whenever the search form is submitted. If Alt key is pressed, make it an all-bugs quick search.
   * @returns {Boolean} `true` to allow submitting the form, `false` otherwise.
   */
  form_onsubmit() {
    if (!this.input) {
      return false;
    }

    if (this.alt_pressed && !this.input.match(/^ALL\s/)) {
      this.$searchbox.value = `ALL ${this.input}`;
    }

    return true;
  }

  /**
   * Called whenever the quick search bar gets user focus. Fetch required data to get prepared.
   */
  searchbox_onfocus() {
    if (this.initialized) {
      return;
    }

    this.initialized = true;

    Bugzilla.User.fetch_recent_bugs().then(bugs => this.data.recent = bugs).then(() => this.show_recent_bugs());
    Bugzilla.User.fetch_saved_searches().then(searches => this.data.saved = searches);
    Bugzilla.BugFields.fetch_products().then(products => this.data.products = products);
    Bugzilla.BugFields.fetch_keywords().then(keywords => this.data.keywords = keywords);
  }

  /**
   * Called whenever any key is pressed on the search bar. Handle Alt key as a trigger like menus in macOS.
   * @param {KeyboardEvent} event A `keydown` or `keyup` event.
   */
  searchbox_onkeydown(event) {
    if (event.key === 'Alt') {
      this.alt_pressed = event.type === 'keydown';
      this.toggle_all_bugs_search();
    }
  }

  /**
   * Called whenever the search terms are updated by the user. Perform searches and show the results.
   */
  searchbox_oninput() {
    // Show local search results immediately
    this.show_search_terms();
    this.show_recent_bugs();
    this.show_saved_searches();
    this.show_products();
    this.show_keywords();

    window.clearTimeout(this.timer);

    // Hide the Shortcuts section first
    this.data.shortcuts = [];
    this.show_shortcut_bugs();

    // Retrieve remote search results
    this.timer = window.setTimeout(() => {
      this.fetch_shortcut_bugs().then(bugs => this.data.shortcuts = bugs).then(() => this.show_shortcut_bugs());
    }, 200);
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.QuickSearch(), { once: true });
