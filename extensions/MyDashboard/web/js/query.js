/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

if (typeof(MyDashboard) == 'undefined') {
    var MyDashboard = {};
}

// Main query code
$(function() {
    YUI({
        base: 'js/yui3/',
        combine: false,
        groups: {
            gallery: {
                combine: false,
                base: 'js/yui3/',
                patterns: { 'gallery-': {} }
            }
        }
    }).use("node", "datatable", "datatable-sort", "datatable-message",
        "datatable-datasource", "datasource-io", "datasource-jsonschema", "cookie",
        "gallery-datatable-row-expansion-bmo", "handlebars", function(Y) {
        var counter          = 0,
            bugQueryTable    = null,
            bugQuery         = null,
            lastChangesQuery = null,
            lastChangesCache = {},
            default_query    = "assignedbugs";

        // Grab last used query name from cookie or use default
        var query_cookie = Y.Cookie.get("my_dashboard_query");
        if (query_cookie) {
            var cookie_value_found = 0;
            Y.one("#query").get("options").each( function() {
                if (this.get("value") == query_cookie) {
                    this.set('selected', true);
                    default_query = query_cookie;
                    cookie_value_found = 1;
                }
            });
            if (!cookie_value_found) {
                Y.Cookie.set("my_dashboard_query", "");
            }
        }

        var bugQuery = new Y.DataSource.IO({ source: `${BUGZILLA.config.basepath}jsonrpc.cgi` });

        bugQuery.plug(Y.Plugin.DataSourceJSONSchema, {
            schema: {
                resultListLocator: "result.result.bugs",
                resultFields: ["bug_id", "bug_type", "changeddate", "changeddate_fancy",
                            "bug_status", "short_desc", "changeddate_api" ],
                metaFields: {
                    description: "result.result.description",
                    heading:     "result.result.heading",
                    buffer:      "result.result.buffer",
                    mark_read:   "result.result.mark_read"
                }
            }
        });

        bugQuery.on('error', function(e) {
            try {
                var response = JSON.parse(e.data.responseText);
                if (response.error)
                    e.error.message = response.error.message;
            } catch(ex) {
                // ignore
            }
        });

        var bugQueryCallback = {
            success: function(e) {
                if (e.response) {
                    Y.one('#query_loading').addClass('bz_default_hidden');
                    Y.one('#query_count_refresh').removeClass('bz_default_hidden');
                    Y.one("#query_container .query_description").setHTML(e.response.meta.description);
                    Y.one("#query_container .query_heading").setHTML(e.response.meta.heading);
                    Y.one("#query_bugs_found").setHTML(
                        `<a href="${BUGZILLA.config.basepath}buglist.cgi?${e.response.meta.buffer}" target="_blank">` +
                        `${e.response.results.length} bugs found</a>`);
                    bugQueryTable.set('data', e.response.results);

                    var mark_read = e.response.meta.mark_read;
                    if (mark_read) {
                        Y.one('#query_markread').setHTML( mark_read );
                        Y.one('#bar_markread').removeClass('bz_default_hidden');
                        Y.one('#query_markread_text').setHTML( mark_read );
                        Y.one('#query_markread').removeClass('bz_default_hidden');
                    }
                    else {
                        Y.one('#bar_markread').addClass('bz_default_hidden');
                        Y.one('#query_markread').addClass('bz_default_hidden');
                    }
                    Y.one('#query_markread_text').addClass('bz_default_hidden');
                }
            },
            failure: function(o) {
                Y.one('#query_loading').addClass('bz_default_hidden');
                Y.one('#query_count_refresh').removeClass('bz_default_hidden');
                if (o.error) {
                    alert("Failed to load bug list from Bugzilla:\n\n" + o.error.message);
                } else {
                    alert("Failed to load bug list from Bugzilla.");
                }
            }
        };

        var updateQueryTable = function(query_name) {
            if (!query_name) return;

            counter = counter + 1;
            lastChangesCache = {};

            Y.one('#query_loading').removeClass('bz_default_hidden');
            Y.one('#query_count_refresh').addClass('bz_default_hidden');
            bugQueryTable.set('data', []);
            bugQueryTable.render("#query_table");
            bugQueryTable.showMessage('loadingMessage');

            var bugQueryParams = {
                version: "1.1",
                method:  "MyDashboard.run_bug_query",
                id:      counter,
                params:  { query : query_name,
                        Bugzilla_api_token : (BUGZILLA.api_token ? BUGZILLA.api_token : '')
                }
            };

            bugQuery.sendRequest({
                request: JSON.stringify(bugQueryParams),
                cfg: {
                    method:  "POST",
                    headers: { 'Content-Type': 'application/json' }
                },
                callback: bugQueryCallback
            });
        };

        var updatedFormatter = function(o) {
            return '<span title="' + o.value.htmlEncode() + '">' +
                o.data.changeddate_fancy.htmlEncode() + '</span>';
        };

        const link_formatter = ({ data, value }) =>
          `<a href="${BUGZILLA.config.basepath}show_bug.cgi?id=${data.bug_id}" target="_blank">
          ${String(value).htmlEncode()}</a>`;

        lastChangesQuery = new Y.DataSource.IO({ source: `${BUGZILLA.config.basepath}jsonrpc.cgi` });

        lastChangesQuery.plug(Y.Plugin.DataSourceJSONSchema, {
            schema: {
                resultListLocator: "result.results",
                resultFields: ["last_changes"],
            }
        });

        lastChangesQuery.on('error', function(e) {
            try {
                var response = JSON.parse(e.data.responseText);
                if (response.error)
                    e.error.message = response.error.message;
            } catch(ex) {
                // ignore
            }
        });

        bugQueryTable = new Y.DataTable({
            columns: [
                { key: Y.Plugin.DataTableRowExpansion.column_key, label: ' ', sortable: false },
                { key: "bug_type", label: "T", allowHTML: true, sortable: true,
                formatter: '<span class="bug-type-label iconic" title="{value}" aria-label="{value}" ' +
                           'data-type="{value}"><span class="icon" aria-hidden="true"></span></span>' },
                { key: "bug_id", label: "Bug", sortable: true, allowHTML: true, formatter: link_formatter },
                { key: "changeddate", label: "Updated", formatter: updatedFormatter,
                allowHTML: true, sortable: true },
                { key: "bug_status", label: "Status", sortable: true },
                { key: "short_desc", label: "Summary", sortable: true, allowHTML: true, formatter: link_formatter },
            ],
            strings: {
                emptyMessage: 'Zarro Boogs found'
            }
        });

        var last_changes_source   = Y.one('#last-changes-template').getHTML(),
            last_changes_template = Y.Handlebars.compile(last_changes_source);

        var stub_source           = Y.one('#last-changes-stub').getHTML(),
            stub_template         = Y.Handlebars.compile(stub_source);


        bugQueryTable.plug(Y.Plugin.DataTableRowExpansion, {
            uniqueIdKey: 'bug_id',
            template: function(data) {
                var bug_id = data.bug_id;

                var lastChangesCallback = {
                    success: function(e) {
                        if (e.response) {
                            var last_changes = e.response.results[0].last_changes;
                            last_changes['bug_id'] = bug_id;
                            lastChangesCache[bug_id] = last_changes;
                            Y.one('#last_changes_stub_' + bug_id).setHTML(last_changes_template(last_changes));
                        }
                    },
                    failure: function(o) {
                        if (o.error) {
                            alert("Failed to load last changes from Bugzilla:\n\n" + o.error.message);
                        } else {
                            alert("Failed to load last changes from Bugzilla.");
                        }
                    }
                };

                if (!lastChangesCache[bug_id]) {
                    var lastChangesParams = {
                        version: "1.1",
                        method:  "MyDashboard.run_last_changes",
                        params:  {
                            bug_id: data.bug_id,
                            changeddate_api: data.changeddate_api,
                            Bugzilla_api_token : (BUGZILLA.api_token ? BUGZILLA.api_token : '')
                        }
                    };

                    lastChangesQuery.sendRequest({
                        request: JSON.stringify(lastChangesParams),
                        cfg: {
                            method:  "POST",
                            headers: { 'Content-Type': 'application/json' }
                        },
                        callback: lastChangesCallback
                    });

                    return stub_template({bug_id: bug_id});
                }
                else {
                    return last_changes_template(lastChangesCache[bug_id]);
                }

            }
        });

        bugQueryTable.plug(Y.Plugin.DataTableSort);

        bugQueryTable.plug(Y.Plugin.DataTableDataSource, {
            datasource: bugQuery
        });

        // Initial load
        Y.on("contentready", function (e) {
            updateQueryTable(default_query);
        }, "#query_table");

        Y.one('#query').on('change', function(e) {
            var index = e.target.get('selectedIndex');
            var selected_value = e.target.get("options").item(index).getAttribute('value');
            updateQueryTable(selected_value);
            Y.Cookie.set("my_dashboard_query", selected_value, { expires: new Date("January 12, 2025") });
        });

        Y.one('#query_refresh').on('click', function(e) {
            var query_select = Y.one('#query');
            var index = query_select.get('selectedIndex');
            var selected_value = query_select.get("options").item(index).getAttribute('value');
            updateQueryTable(selected_value);
        });

        Y.one('#query_markread').on('click', function(e) {
            var data = bugQueryTable.data;
            var bug_ids = [];

            Y.one('#query_markread').addClass('bz_default_hidden');
            Y.one('#query_markread_text').removeClass('bz_default_hidden');

            for (var i = 0, l = data.size(); i < l; i++) {
                bug_ids.push(data.item(i).get('bug_id'));
            }
            YAHOO.bugzilla.bugUserLastVisit.update(bug_ids);
            YAHOO.bugzilla.bugInterest.unmark(bug_ids);
        });

        Y.one('#query_buglist').on('click', function(e) {
            var data = bugQueryTable.data;
            var ids = [];
            for (var i = 0, l = data.size(); i < l; i++) {
                ids.push(data.item(i).get('bug_id'));
            }
            var url = `${BUGZILLA.config.basepath}buglist.cgi?bug_id=${ids.join('%2C')}`;
            window.open(url, '_blank');
        });
    });
});
