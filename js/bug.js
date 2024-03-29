/* The contents of this file are subject to the Mozilla Public
 * License Version 1.1 (the "License"); you may not use this file
 * except in compliance with the License. You may obtain a copy of
 * the License at http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS
 * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * rights and limitations under the License.
 *
 * The Original Code is the Bugzilla Bug Tracking System.
 *
 * The Initial Developer of the Original Code is Everything Solved, Inc.
 * Portions created by Everything Solved are Copyright (C) 2010 Everything
 * Solved, Inc. All Rights Reserved.
 *
 * Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>
 */

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

Bugzilla.DupTable = {
    updateTable: async (dataTable, product_name, summary_field) => {
        if (summary_field.value.length < 4) return;

        dataTable.render([]);
        dataTable.setMessage('LOADING');
        document.getElementById('possible_duplicates_container')
            .classList.remove('bz_default_hidden');

        let data = {};

        try {
            const { bugs } = await Bugzilla.API.get('bug/possible_duplicates', {
                product: product_name,
                summary: summary_field.value,
                limit: 7,
                include_fields: ['id', 'summary', 'status', 'resolution', 'update_token'],
            });

            data = { results: bugs };
        } catch (ex) {
            data = { error: true };
        }

        dataTable.update(data);
    },
    // This is the keyup event handler. It calls updateTable with a relatively
    // long delay, to allow additional input. However, the delay is short
    // enough that nobody could get from the summary field to the Submit
    // Bug button before the table is shown (which is important, because
    // the showing of the table causes the Submit Bug button to move, and
    // if the table shows at the exact same time as the button is clicked,
    // the click on the button won't register.)
    doUpdateTable: function(e, args) {
        if (e.isComposing) {
          return;
        }

        var dt = args[0];
        var product_name = args[1];
        var summary = e.target;
        clearTimeout(Bugzilla.DupTable.lastTimeout);
        Bugzilla.DupTable.lastTimeout = setTimeout(function() {
            Bugzilla.DupTable.updateTable(dt, product_name, summary) },
            600);
    },
    formatBugLink({ value }) {
        return `<a href="${BUGZILLA.config.basepath}show_bug.cgi?id=${value}">${value}</a>`;
    },
    formatStatus({ value, data: { resolution }}) {
        const status = display_value('bug_status', value);
        return resolution ? `${status} ${display_value('resolution', resolution)}` : status;
    },
    formatCcButton({ value, data }) {
        var url = `${BUGZILLA.config.basepath}process_bug.cgi?` +
                  `id=${data.id}&addselfcc=1&token=${escape(value)}`;
        return `<a href="${url}"><input type="button" value="Follow"></a>`;
    },
    init(data) {
        const { container, columns, strings, summary_field, product_name } = data;
        const dt = new Bugzilla.DataTable({ container, columns, strings });

        document.getElementById(summary_field).addEventListener('input', (event) => {
            this.doUpdateTable(event, [dt, product_name]);
        });
    }
};
