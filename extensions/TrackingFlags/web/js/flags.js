/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

var Dom = YAHOO.util.Dom;

function hide_tracking_flags() {
    for (var i = 0, l = TrackingFlags.types.length; i < l; i++) {
        var flag_type = TrackingFlags.types[i];
        for (var field in TrackingFlags.flags[flag_type]) {
            var el = Dom.get(field);
            var value = el ? el.value : TrackingFlags.flags[flag_type][field];
            if (el && (value != TrackingFlags.flags[flag_type][field])) {
                show_tracking_flags(flag_type);
                return;
            }
            if (value == '---') {
                Dom.addClass('row_' + field, 'bz_default_hidden');
            } else {
                Dom.addClass(field, 'bz_default_hidden');
                Dom.removeClass('ro_' + field, 'bz_default_hidden');
            }
        }
    }
}

function show_tracking_flags(flag_type) {
    Dom.addClass('edit_' + flag_type + '_flags_action', 'bz_default_hidden');
    for (var field in TrackingFlags.flags[flag_type]) {
        if (Dom.get(field).value == '---') {
            Dom.removeClass('row_' + field, 'bz_default_hidden');
        } else {
            Dom.removeClass(field, 'bz_default_hidden');
            Dom.addClass('ro_' + field, 'bz_default_hidden');
        }
    }
}

function tracking_flag_change(e) {
    var value = e.value;
    var prefill;
    if (TrackingFlags.comments[e.name])
        prefill = TrackingFlags.comments[e.name][e.value];
    if (!prefill) {
        var cr = document.getElementById('cr_' + e.id);
        if (cr)
            cr.parentElement.removeChild(cr);
        return;
    }
    if (!document.getElementById('cr_' + e.id)) {
        // create "comment required"
        var span = document.createElement('span');
        span.id = 'cr_' + e.id;
        span.appendChild(document.createTextNode(' ('));
        var a = document.createElement('a');
        a.appendChild(document.createTextNode('comment required'));
        a.href = '#';
        a.onclick = function(event) {
            event.preventDefault();
            var c = document.getElementById('comment');
            c.focus();
            c.select();
            var btn = document.getElementById('add_comment') || document.getElementById('add-comment');
            if (btn)
                btn.scrollIntoView();
        };
        span.appendChild(a);
        span.appendChild(document.createTextNode(')'));
        e.parentNode.appendChild(span);
    }
    // prefill comment
    var commentEl = document.getElementById('comment');
    if (!commentEl)
        return;
    var value = commentEl.value;
    if (value == prefill)
        return;
    if (value == '') {
        commentEl.value = prefill;
        a.innerHTML = 'comment required';
    } else {
        commentEl.value = prefill + "\n\n" + value;
        a.innerHTML = 'comment updated';
    }
}

YAHOO.util.Event.onDOMReady(function() {
    var edit_tracking_links = Dom.getElementsByClassName('edit_tracking_flags_link');
    for (var i = 0, l = edit_tracking_links.length; i < l; i++) {
        YAHOO.util.Event.addListener(edit_tracking_links[i], 'click', function(e) {
            e.preventDefault();
            show_tracking_flags(this.name);
        });
    }
});
