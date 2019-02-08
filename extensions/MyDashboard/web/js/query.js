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
    }).use("node", "datatable", "datatable-sort", "datatable-message", "cookie",
        "gallery-datatable-row-expansion-bmo", "handlebars", function(Y) {
        var bugQueryTable    = null,
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

        var updateQueryTable = function(query_name) {
            if (!query_name) return;

            lastChangesCache = {};

            Y.one('#query_loading').removeClass('bz_default_hidden');
            Y.one('#query_count_refresh').addClass('bz_default_hidden');
            bugQueryTable.set('data', []);
            bugQueryTable.render("#query_table");
            bugQueryTable.showMessage('loadingMessage');

            Bugzilla.API.get('mydashboard/run_bug_query', { query: query_name }).then(data => {
                const { buffer, bugs, description, heading, mark_read } = data.result;

                Y.one('#query_loading').addClass('bz_default_hidden');
                Y.one('#query_count_refresh').removeClass('bz_default_hidden');
                Y.one("#query_container .query_description").setHTML(description);
                Y.one("#query_container .query_heading").setHTML(heading);
                Y.one("#query_bugs_found").setHTML(`<a href="${BUGZILLA.config.basepath}buglist.cgi?${buffer}" ` +
                    `target="_blank">${bugs.length} bugs found</a>`);

                bugQueryTable.set('data', bugs);
                bugQueryTable.render("#query_table");

                if (mark_read) {
                    Y.one('#query_markread').setHTML(mark_read);
                    Y.one('#bar_markread').removeClass('bz_default_hidden');
                    Y.one('#query_markread_text').setHTML(mark_read);
                    Y.one('#query_markread').removeClass('bz_default_hidden');
                } else {
                    Y.one('#bar_markread').addClass('bz_default_hidden');
                    Y.one('#query_markread').addClass('bz_default_hidden');
                }

                Y.one('#query_markread_text').addClass('bz_default_hidden');
            }).catch(error => {
                Y.one('#query_loading').addClass('bz_default_hidden');
                Y.one('#query_count_refresh').removeClass('bz_default_hidden');

                alert(`Failed to load bug list from Bugzilla:\n\n${error.message}`);
            });
        };

        var updatedFormatter = function(o) {
            return '<span title="' + o.value.htmlEncode() + '">' +
                o.data.changeddate_fancy.htmlEncode() + '</span>';
        };

        bugQueryTable = new Y.DataTable({
            columns: [
                { key: Y.Plugin.DataTableRowExpansion.column_key, label: ' ', sortable: false },
                { key: "bug_id", label: "Bug", allowHTML: true, sortable: true,
                formatter: `<a href="${BUGZILLA.config.basepath}show_bug.cgi?id={value}" target="_blank">{value}</a>` },
                { key: "changeddate", label: "Updated", formatter: updatedFormatter,
                allowHTML: true, sortable: true },
                { key: "bug_status", label: "Status", sortable: true },
                { key: "short_desc", label: "Summary", sortable: true },
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
                const { bug_id, changeddate_api } = data;

                if (!lastChangesCache[bug_id]) {
                    Bugzilla.API.get('mydashboard/run_last_changes', { bug_id, changeddate_api }).then(data => {
                        const { last_changes } = data.results[0];

                        last_changes['bug_id'] = bug_id;
                        lastChangesCache[bug_id] = last_changes;
                        Y.one('#last_changes_stub_' + bug_id).setHTML(last_changes_template(last_changes));
                    }).catch(error => {
                        alert(`Failed to load last changes from Bugzilla:\n\n${error.message}`);
                    });

                    return stub_template({bug_id: bug_id});
                }
                else {
                    return last_changes_template(lastChangesCache[bug_id]);
                }

            }
        });

        bugQueryTable.plug(Y.Plugin.DataTableSort);

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
            Bugzilla.API.post('bug_user_last_visit', { ids: bug_ids });
            Bugzilla.API.put('mydashboard/bug_interest_unmark', { bug_ids });
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
