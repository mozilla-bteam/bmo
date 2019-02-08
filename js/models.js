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
 * Provide functionality related to bug field data.
 * @see https://bugzilla.readthedocs.io/en/latest/api/core/v1/field.html
 */
Bugzilla.BugFields = class BugFields {
  /**
   * Retrieve bug component field values used in the Bugzilla instance.
   * @returns {Promise.<Object[]>} List of products.
   * @see https://bugzilla.readthedocs.io/en/latest/api/core/v1/product.html
   */
  static async fetch_products() {
    const cache_key = 'bug_field_products';
    const products = Bugzilla.Storage.get(cache_key);

    // Use cache if available
    if (products) {
      return Promise.resolve(products);
    }

    try {
      let { products } = await Bugzilla.API.get('product', {
        type: 'accessible',
        include_fields: ['classification', 'name', 'description', 'components.name', 'components.description'],
      });

      // Exclude products moved to Graveyard
      products = products.filter(({ classification }) => classification !== 'Graveyard');

      // Cache in local storage for a day
      Bugzilla.Storage.save(cache_key, products, 24 * 60 * 60 * 1000);

      return Promise.resolve(products);
    } catch (ex) {
      return Promise.resolve([]);
    }
  }

  /**
   * Retrieve bug keyword field values used in the Bugzilla instance.
   * @returns {Promise.<Object[]>} List of keywords.
   */
  static async fetch_keywords() {
    const cache_key = 'bug_field_keywords';
    const keywords = Bugzilla.Storage.get(cache_key);

    // Use cache if available
    if (keywords) {
      return Promise.resolve(keywords);
    }

    try {
      const { fields } = await Bugzilla.API.get('field/bug/keywords', { include_fields: 'values' });
      const keywords = fields[0].values;

      // Cache in local storage for a day
      Bugzilla.Storage.save(cache_key, keywords, 24 * 60 * 60 * 1000);

      return Promise.resolve(keywords);
    } catch (ex) {
      return Promise.resolve([]);
    }
  }
};

/**
 * Provide functionality related to the current user's data.
 * @see https://bugzilla.readthedocs.io/en/latest/api/core/v1/user.html
 */
Bugzilla.User = class User {
  /**
   * Retrieve list of bugs the user has recently accessed.
   * @returns {Promise.<Object[]>} List of recent bugs, which contain the bug ID, summary, alias and last visit date.
   * This can be an empty array if the user is not logged in.
   * @see https://bugzilla.readthedocs.io/en/latest/api/core/v1/bug-user-last-visit.html
   */
  static async fetch_recent_bugs() {
    if (!BUGZILLA.api_token) {
      return Promise.resolve([]);
    }

    const cache_key = 'bug_user_last_visit';
    const bugs = (Bugzilla.data || {})[cache_key];

    // Use cache if available and fresh (retrieved less than a half day ago)
    if (bugs) {
      return Promise.resolve(bugs);
    }

    try {
      const last_visit = await Bugzilla.API.get('bug_user_last_visit');
      const last_visit_map = new Map(last_visit.map(({ id, last_visit_ts }) => ([id, new Date(last_visit_ts)])));

      let { bugs } = await Bugzilla.API.get('bug', {
        id: [...last_visit_map.entries()].sort((a, b) => a[1] < b[1]).map(a => a[0]).slice(0, 800).join(','),
        include_fields: ['id', 'alias', 'summary', 'type'],
      });

      // Combine the bugs and last_visit arrays
      bugs.forEach((bug, i) => bugs[i].last_visit = last_visit_map.get(bug.id));

      // Sort by date in descending order (new to old)
      bugs = Bugzilla.Array.sort(bugs, 'last_visit', { descending: true });

      // Cache in memory
      Bugzilla.data = Bugzilla.data || {};
      Bugzilla.data[cache_key] = bugs;

      return Promise.resolve(bugs);
    } catch (ex) {
      return Promise.resolve([]);
    }
  }

  /**
   * Retrieve the user's saved search items which are currently embedded in HTML.
   * @returns {Promise.<Object[]>} List of saved searches, which contain the name and link. This can be an empty array
   * if the user is not logged in.
   */
  static async fetch_saved_searches() {
    const searches = [...document.querySelectorAll('#header-search-dropdown section[data-type="saved"] a')]
      .map(({ text, href }) => ({ name: text, link: href }));

    return Promise.resolve(searches);
  }
};
