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

Bugzilla.InstantSearch = {
  dataTable: null,
  dataTableColumns: null,
  elContent: null,
  elList: null,
  currentSearchQuery: '',
  currentSearchProduct: '',

  onInit: function() {
    this.elContent = document.getElementById('content');
    this.elList = document.getElementById('results');

    this.elContent.addEventListener('keyup', (event) => {
      this.onContentKeyUp(event);
    });
    document.getElementById('product').addEventListener('change', (event) => {
      this.onProductChange(event);
    });
  },

  setLabels: function(labels) {
    this.dataTableColumns = [
      { key: "id", label: labels.id, formatter: this.formatId, allowHTML: true },
      { key: "summary", label: labels.summary },
      { key: "component", label: labels.component },
      { key: "status", label: labels.status, formatter: this.formatStatus },
    ];
  },

  initDataTable: function() {
    this.dataTable = new Bugzilla.DataTable({
      container: '#results',
      columns: this.dataTableColumns,
      strings: {
        EMPTY: 'No matching bugs found.',
        ERROR: 'An error occurred while searching for bugs, please try again.'
      }
    });
  },

  formatId({ value }) {
    return `<a href="${BUGZILLA.config.basepath}show_bug.cgi?id=${value}" target="_blank">${value}</a>`;
  },

  formatStatus({ value, data: { resolution } }) {
    const status = display_value('bug_status', value);
    return resolution ? `${status} ${display_value('resolution', resolution)}` : status;
  },

  reset: function() {
    this.elList.classList.add('hidden');
    this.elList.innerHTML = '';
    this.currentSearchQuery = '';
    this.currentSearchProduct = '';
  },

  onContentKeyUp: function(e) {
    clearTimeout(this.lastTimeout);
    this.lastTimeout = setTimeout(() => {
      this.doSearch(this.getContent()) },
      600);
  },

  onProductChange: function(e) {
    this.doSearch(this.getContent());
  },

  async doSearch(query) {
    if (query.length < 4)
      return;

    // don't query if we already have the results (or they are pending)
    var product = document.getElementById('product').value;
    if (this.currentSearchQuery == query &&
        this.currentSearchProduct == product)
      return;
    this.currentSearchQuery = query;
    this.currentSearchProduct = product;

    // initialize the datatable as late as possible
    this.initDataTable();

    try {
      // run the search
      this.elList.classList.remove('hidden');

      this.dataTable.setMessage(
        'Searching...&nbsp;&nbsp;&nbsp;' +
        `<img src="${BUGZILLA.config.basepath}extensions/GuidedBugEntry/web/images/throbber.gif"` +
        ' width="16" height="11">'
      );

      let data;

      try {
        const { bugs } = await Bugzilla.API.get('bug/possible_duplicates', {
          product: this.getProduct(),
          summary: query,
          limit: 20,
          include_fields: ['id', 'summary', 'status', 'resolution', 'component'],
        });

        data = { results: bugs };
      } catch (ex) {
        this.currentSearchQuery = '';
        data = { error: true };
      }

      this.dataTable.update(data);
    } catch(err) {
      if (console)
        console.error(err.message);
    }
  },

  getContent: function() {
    var content = this.elContent.value.trim();
    // work around chrome bug
    if (content == this.elContent.getAttribute('placeholder')) {
      return '';
    } else {
      return content;
    }
  },

  getProduct: function() {
    var result = [];
    var name = document.getElementById('product').value;
    result.push(name);
    if (products[name] && products[name].related) {
      for (var i = 0, n = products[name].related.length; i < n; i++) {
        result.push(products[name].related[i]);
      }
    }
    return result;
  }

};

window.addEventListener('DOMContentLoaded', () => {
  Bugzilla.InstantSearch.onInit();

  const content = Bugzilla.InstantSearch.getContent();

  if (content.length >= 4) {
    Bugzilla.InstantSearch.doSearch(content);
  } else {
    Bugzilla.InstantSearch.reset();
  }
});
