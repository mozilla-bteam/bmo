(function(){
'use strict';

YUI.add('bz-review-history', function (Y) {
  var flagDS = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
  flagDS.plug(Y.Plugin.DataSourceJSONSchema, {
    schema: {
      resultListLocator: 'result',
      resultFields: [
        { key: 'requestee' },
        { key: 'setter' },
        { key: 'flag_id' },
        { key: 'creation_time' },
        { key: 'status' },
        { key: 'bug_id' },
        { key: 'type' }
      ]
    }
  });
  var historyTable = new Y.DataTable({
    columns: [
      { key: "setter",   label: "Setter" },
      { key: "bug_id",   label: "Bug #", sortable: true, allowHTML: true,
        formatter: '<a href="show_bug.cgi?id={value}" target="_blank">{value}</a>' },
      { key: "duration", label: "Duration", sortable: true, formatter: format_duration },
      { key: 'result',   label: "Result" },
    ],
  });

  Y.ReviewHistory = {};

  Y.ReviewHistory.render = function(sel) {
    historyTable.render(sel);
    historyTable.setAttrs({ width: "100%" }, true);
  };

  Y.ReviewHistory.refresh = function(user) {
    historyTable.setAttrs({caption: "Review History for " + user}, true);
    fetch_flag_ids(user)
      .then(fetch_flags)
      .then(generate_history)
      .then(function (history) { historyTable.set('data', history) });
  };

  function fetch_flag_ids(user) {
    return new Y.Promise(function (resolve, reject) {
      var flagIdCallback = {
        success: function(e) {
          var flags = e.response.results;
          resolve(flags.filter(function (flag) { return flag.status == '?' })
                       .map(function (flag) { return flag.flag_id; }));
        },
        failure: reject,
      };

      flagDS.sendRequest({
        request: Y.JSON.stringify({
          version: '1.1',
          method: 'Review.flag_activity',
          params: {
            type_name:  'review',
            requestee: user,
          }
        }),
        cfg: { method: "POST", headers: { 'Content-Type': 'application/json'} },
        callback: flagIdCallback
      });
    });
  }

  function fetch_flags(flag_ids) {
    return new Y.Promise(function (resolve, reject) {
      flagDS.sendRequest({
        request: Y.JSON.stringify({
          version: '1.1',
          method: 'Review.flag_activity',
          params: { flag_ids: flag_ids },
        }),
        cfg: { method: 'POST', headers: { 'Content-Type': 'application/json' } },
        callback: {
          success: function (e) { resolve(e.response.results); },
          failure: reject
        },
      });
    });
  }

  function generate_history(flags) {
    var history = [];
    var stash   = {};
    var i       = 1;

    flags.forEach(function (flag) {
      var flag_id = flag.flag_id;

      switch (flag.status) {
        case '?':
          if (stash[flag_id]) {
            stash["#" + i++] = stash[flag_id];
          }

          stash[flag_id] = {
            setter: flag.setter.name,
            bug_id: flag.bug_id,
            start: parse_date(flag.creation_time),
          };
          break;
        case '+':
        case '-':
          if (stash[flag_id]) {
            history.push({
              setter: stash[flag_id].setter,
              bug_id: stash[flag_id].bug_id,
              result: flag.status,
              duration: parse_date(flag.creation_time) - stash[flag_id].start,
            });
            stash[flag_id] = null;
          }
          break;
      }
    });
    for (var flag_id in stash) {
      if (stash[flag_id]) {
        history.push({
          setter: stash[flag_id].setter,
          bug_id: stash[flag_id].bug_id,
          result: ' ',
          duration: null,
        });
      }
    }

    return history;
  }

  function format_duration(row) {
    var secs = row.value;
    if (secs === null) {
      return 'Pending';
    }

    var result = "";
    var periods = [
      { unit: "y", value: 31556926 * 1000 },
      { unit: "w", value: 604800   * 1000 },
      { unit: "d", value: 86400    * 1000 },
      { unit: "h", value: 3600     * 1000 },
      { unit: "m", value: 60       * 1000 },
      { unit: "s", value: 1        * 1000 },
    ];

    periods.forEach(function (period) {
      var value = Math.floor(secs / period.value);
      secs %= period.value;
      if (value) {
        if (result) {
          result += " " + value + period.unit;
        }
        else {
          result += value + period.unit;
        }
      }
    });

    return result;
  }

  function parse_date(str) {
    var parts = str.split(/\D/);
    return new Date(parts[0], parts[1]-1, parts[2], parts[3], parts[4], parts[5]);
  }
}, '0.0.1', {
  requires: [ "node", "datatable", "datatable-sort", "datatable-message", "json-stringify",
              "datatable-datasource", "datasource-io", "datasource-jsonschema", "cookie",
              "gallery-datatable-row-expansion-bmo", "handlebars", "escape", "promise" ] })
})();
