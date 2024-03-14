/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

// Flag tables
window.addEventListener('DOMContentLoaded', () => {
  // Common
  const dataTable = {
    requestee: null,
    requester: null,
  };

  let button_state = false;
  let refresh_interval = null;

  // Grab last used auto-refresh configuration from storage or use default
  if (Bugzilla.Storage.get('my_dashboard')?.autoRefresh) {
    button_state = true;
  }

  const updateFlagTable = async (type) => {
    if (!type) return;

    const $count_refresh = document.querySelector(`#${type}_count_refresh`);

    $count_refresh.classList.add('bz_default_hidden');
    dataTable[type].render([]);
    dataTable[type].setMessage('LOADING');

    try {
      const { result } = await Bugzilla.API.get('mydashboard/run_flag_query', { type });
      const results = result[type];

      $count_refresh.classList.remove('bz_default_hidden');
      document.querySelector(`#${type}_flags_found`).textContent = `${results.length} ${
        results.length === 1 ? 'request' : 'requests'
      } found`;
      dataTable[type].render(results);
    } catch {
      $count_refresh.classList.remove('bz_default_hidden');
      dataTable[type].setMessage(`Failed to load requests.`);
    }
  };

  const loadBugList = (type) => {
    if (!type) return;

    const ids = dataTable[type].data.map(({ data }) => data.bug_id);
    const url = `${BUGZILLA.config.basepath}buglist.cgi?bug_id=${ids.join('%2C')}`;

    window.open(url, '_blank');
  };

  const bugLinkFormatter = ({ data: { bug_id, bug_status, bug_summary } }) => {
    if (!bug_id) {
      return '-';
    }

    let bug_closed = '';

    if (bug_status === 'RESOLVED' || bug_status === 'VERIFIED') {
      bug_closed = 'bz_closed';
    }

    return (
      `<a href="${BUGZILLA.config.basepath}show_bug.cgi?id=${encodeURIComponent(bug_id)}" ` +
      `target="_blank" title="${bug_status.htmlEncode()} - ${bug_summary.htmlEncode()}" ` +
      `class="${bug_closed}">${bug_id}</a>`
    );
  };

  const updatedFormatter = ({ value, data: { updated_fancy } }) =>
    `<span title="${value.htmlEncode()}">${updated_fancy.htmlEncode()}</span>`;

  const requesteeFormatter = ({ value }) => value.htmlEncode();

  const flagNameFormatter = ({ value, data: { bug_id, attach_id, is_patch } }) => {
    if (parseInt(attach_id) && parseInt(is_patch) && MyDashboard.splinter_base) {
      const url = new URL(MyDashboard.splinter_base);

      url.searchParams.set('bug', bug_id);
      url.searchParams.set('attachment', attach_id);

      return `<a href="${url.toString()}" target="_blank" title="Review this patch">${value.htmlEncode()}</a>`;
    } else {
      return value.htmlEncode();
    }
  };

  const autoUpdateFlagTable = () => {
    if (button_state === true) {
      refresh_interval = setInterval(() => {
        updateFlagTable('requestee');
        updateFlagTable('requester');
      }, 1000 * 60 * 10);
    } else {
      clearInterval(refresh_interval);
    }
  };

  // Requestee
  dataTable.requestee = new Bugzilla.DataTable({
    container: '#requestee_table',
    columns: [
      { key: 'requester', label: 'Requester' },
      { key: 'type', label: 'Type', formatter: flagNameFormatter, allowHTML: true },
      { key: 'bug_id', label: 'Bug', formatter: bugLinkFormatter, allowHTML: true },
      { key: 'updated', label: 'Updated', formatter: updatedFormatter, allowHTML: true },
    ],
    strings: {
      EMPTY: 'No requests found.',
    },
  });

  document.querySelector('#requestee_refresh').addEventListener('click', () => {
    updateFlagTable('requestee');
  });

  document.querySelector('#requestee_buglist').addEventListener('click', () => {
    loadBugList('requestee');
  });

  // Requester
  dataTable.requester = new Bugzilla.DataTable({
    container: '#requester_table',
    columns: [
      { key: 'requestee', label: 'Requestee', formatter: requesteeFormatter, allowHTML: true },
      { key: 'type', label: 'Type', formatter: flagNameFormatter, allowHTML: true },
      { key: 'bug_id', label: 'Bug', formatter: bugLinkFormatter, allowHTML: true },
      { key: 'updated', label: 'Updated', formatter: updatedFormatter, allowHTML: true },
    ],
    strings: {
      EMPTY: 'No requests found.',
    },
  });

  document.querySelector('#requester_refresh').addEventListener('click', () => {
    updateFlagTable('requester');
  });

  document.querySelector('#requester_buglist').addEventListener('click', () => {
    loadBugList('requester');
  });

  document.querySelector('#auto_refresh').addEventListener('click', (e) => {
    button_state = e.target.checked;
    autoUpdateFlagTable();
  });

  // Initial load
  updateFlagTable('requestee');
  updateFlagTable('requester');
  autoUpdateFlagTable();
});
