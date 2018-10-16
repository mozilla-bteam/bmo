/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

function add_bounty_attachment(bug_id) {
    var nodes = YAHOO.util.Selector.query('#attachment_table tr.bz_attach_footer td');
    if (nodes) {
        var existing = document.getElementById('bounty_attachment');
        var td = nodes[0];
        var a  = document.createElement('a');
        a.href = `${BUGZILLA.config.basepath}page.cgi?id=attachment_bounty_form.html&bug_id=${bug_id}`;
        a.appendChild(document.createTextNode(existing
            ? 'Edit bounty tracking attachment'
            : 'Add bounty tracking attachment'));
        td.appendChild(document.createElement('br'));
        td.appendChild(a);

        if (existing) {
            var tr = existing.parentNode.parentNode;
            if (tr.nodeName != 'TR')
                return;
            nodes = tr.getElementsByTagName('a');
            for (var i = 0, il = nodes.length; i < il; i++) {
                if (nodes[i].href.match(/attachment\.cgi\?id=\d+$/)) {
                    nodes[i].href = a.href;
                    return;
                }
            }
        }
    }
}
