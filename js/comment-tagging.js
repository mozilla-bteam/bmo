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

Bugzilla.CommentTagging = {
    ctag_div  : false,
    ctag_add  : false,
    counter   : 0,
    min_len   : 3,
    max_len   : 24,
    tags_by_no: {},
    nos_by_tag: {},
    current_id: 0,
    current_no: -1,
    can_edit  : false,
    pending   : {},

    label        : '',
    min_len_error: '',
    max_len_error: '',

    init : function(can_edit) {
        this.can_edit = can_edit;
        this.ctag_div = document.getElementById('bz_ctag_div');
        this.ctag_add = document.getElementById('bz_ctag_add');
        this.ctag_add.addEventListener('keypress', this.onKeyPress);
        window.addEventListener('DOMContentLoaded', () => {
            Bugzilla.CommentTagging.updateCollapseControls();
        });
        if (!can_edit) return;

        $('#bz_ctag_add').devbridgeAutocomplete({
            appendTo: $('#main-inner'),
            forceFixPosition: true,
            deferRequestBy: 250,
            minChars: 1,
            tabDisabled: true,
            lookup: (query, done) => {
                // Note: `async` doesn't work for this `lookup` function, so use a `Promise` chain instead
                Bugzilla.API.get(`bug/comment/tags/${encodeURIComponent(query)}`)
                    .then(data => data.map(tag => ({ value: tag })))
                    .catch(() => [])
                    .then(suggestions => done({ suggestions }));
            }
        });
    },

    toggle : function(comment_id, comment_no) {
        if (!this.ctag_div) return;
        var tags_container = document.getElementById(`ct_${comment_no}`);

        if (this.current_id == comment_id) {
            // hide
            this.current_id = 0;
            this.current_no = -1;
            this.ctag_div.classList.add('bz_default_hidden');
            this.hideError();
            window.focus();

        } else {
            // show or move
            this.fetchRefresh(comment_id, comment_no);
            this.current_id = comment_id;
            this.current_no = comment_no;
            this.ctag_add.value = '';
            tags_container.parentElement.insertBefore(this.ctag_div, tags_container);
            this.ctag_div.classList.remove('bz_default_hidden');
            tags_container.parentElement.classList.remove('bz_default_hidden');
            var comment = document.getElementById(`comment_text_${comment_no}`);
            if (comment.matches('.collapsed')) {
                var link = document.getElementById(`comment_link_${comment_no}`);
                expand_comment(link, comment, comment_no);
            }
            window.setTimeout(function() {
                Bugzilla.CommentTagging.ctag_add.focus();
            }, 50);
        }
    },

    hideInput : function() {
        if (this.current_id != 0) {
            var comment_no = this.current_no;
            this.toggle(this.current_id, this.current_no);
            this.hideEmpty(comment_no);
        }
        this.hideError();
    },

    hideEmpty : function(comment_no) {
        if (document.getElementById(`ct_${comment_no}`).children.length == 0) {
            document.getElementById(`comment_tag_${comment_no}`).classList.add('bz_default_hidden');
        }
    },

    showError : function(comment_id, comment_no, error) {
        var bz_ctag_error = document.getElementById('bz_ctag_error');
        var tags_container = document.getElementById(`ct_${comment_no}`);
        tags_container.parentNode.appendChild(bz_ctag_error);
        document.getElementById('bz_ctag_error_msg').innerHTML = error.htmlEncode();
        bz_ctag_error.classList.remove('bz_default_hidden');
    },

    hideError : function() {
        document.getElementById('bz_ctag_error').classList.add('bz_default_hidden');
    },

    onKeyPress : function(evt) {
        evt = evt || window.event;
        var charCode = evt.charCode || evt.keyCode;
        if (evt.keyCode == 27) {
            // escape
            evt.preventDefault();
            evt.stopPropagation();
            Bugzilla.CommentTagging.hideInput();
        } else if (evt.keyCode == 13) {
            // return
            evt.preventDefault();
            evt.stopPropagation();
            var tags = Bugzilla.CommentTagging.ctag_add.value.split(/[ ,]/);
            var { current_id: comment_id, current_no: comment_no } = Bugzilla.CommentTagging;
            try {
                Bugzilla.CommentTagging.add(comment_id, comment_no, tags);
                Bugzilla.CommentTagging.hideInput();
            } catch(e) {
                Bugzilla.CommentTagging.showError(comment_id, comment_no, e.message);
            }
        }
    },

    showTags : function(comment_id, comment_no, tags) {
        // remove existing tags
        var tags_container = document.getElementById(`ct_${comment_no}`);
        while (tags_container.hasChildNodes()) {
            tags_container.removeChild(tags_container.lastChild);
        }
        // add tags
        if (tags != '') {
            if (typeof(tags) == 'string') {
                tags = tags.split(',');
            }
            for (var i = 0, l = tags.length; i < l; i++) {
                tags_container.appendChild(this.buildTagHtml(comment_id, comment_no, tags[i]));
            }
        }
        // update tracking array
        this.tags_by_no['c' + comment_no] = tags;
        this.updateCollapseControls();
    },

    updateCollapseControls : function() {
        var container = document.getElementById('comment_tags_collapse_expand_container');
        if (!container) return;
        // build list of tags
        this.nos_by_tag = {};
        for (var id in this.tags_by_no) {
            if (this.tags_by_no.hasOwnProperty(id)) {
                for (var i = 0, l = this.tags_by_no[id].length; i < l; i++) {
                    var tag = this.tags_by_no[id][i].toLowerCase();
                    if (!this.nos_by_tag.hasOwnProperty(tag)) {
                        this.nos_by_tag[tag] = [];
                    }
                    this.nos_by_tag[tag].push(id);
                }
            }
        }
        var tags = [];
        for (var tag in this.nos_by_tag) {
            if (this.nos_by_tag.hasOwnProperty(tag)) {
                tags.push(tag);
            }
        }
        tags.sort();
        if (tags.length) {
            var div = document.createElement('div');
            div.appendChild(document.createTextNode(this.label));
            var ul = document.createElement('ul');
            ul.id = 'comment_tags_collapse_expand';
            div.appendChild(ul);
            tags.forEach((tag) => {
                var li = document.createElement('li');
                ul.appendChild(li);
                var a = document.createElement('a');
                li.appendChild(a);
                a.setAttribute('href', '#');
                a.addEventListener('click', (event) => {
                    Bugzilla.CommentTagging.toggleCollapse(tag);
                    event.preventDefault();
                    event.stopPropagation();
                });
                li.appendChild(document.createTextNode(' (' + this.nos_by_tag[tag].length + ')'));
                a.innerHTML = tag;
            });
            while (container.hasChildNodes()) {
                container.removeChild(container.lastChild);
            }
            container.appendChild(div);
        } else {
            while (container.hasChildNodes()) {
                container.removeChild(container.lastChild);
            }
        }
    },

    toggleCollapse : function(tag) {
        var nos = this.nos_by_tag[tag];
        if (!nos) return;
        toggle_all_comments('collapse');
        for (var i = 0, l = nos.length; i < l; i++) {
            var comment_no = nos[i].match(/\d+$/)[0];
            var comment = document.getElementById(`comment_text_${comment_no}`);
            var link = document.getElementById(`comment_link_${comment_no}`);
            expand_comment(link, comment, comment_no);
        }
    },

    buildTagHtml : function(comment_id, comment_no, tag) {
        var el = document.createElement('span');
        el.setAttribute('id', `ct_${comment_no}_${tag}`);
        el.classList.add('bz_comment_tag');
        if (this.can_edit) {
            var a = document.createElement('a');
            a.setAttribute('href', '#');
            a.addEventListener('click', (event) => {
                Bugzilla.CommentTagging.remove(comment_id, comment_no, tag);
                event.preventDefault();
                event.stopPropagation();
            });
            a.appendChild(document.createTextNode('x'));
            el.appendChild(a);
            el.appendChild(document.createTextNode("\u00a0"));
        }
        el.appendChild(document.createTextNode(tag));
        return el;
    },

    add : function(comment_id, comment_no, add_tags) {
        // build list of current tags from HTML
        var tags = [...document.querySelectorAll(`#ct_${comment_no} .bz_comment_tag`)]
            .map((span) => span.textContent.substr(2));
        // add new tags
        var new_tags = new Array();
        for (var i = 0, l = add_tags.length; i < l; i++) {
            var tag = add_tags[i].trim();
            // validation
            if (tag == '')
                continue;
            if (tag.length < Bugzilla.CommentTagging.min_len)
                throw new Error(this.min_len_error)
            if (tag.length > Bugzilla.CommentTagging.max_len)
                throw new Error(this.max_len_error)
            // append new tag
            if (bz_isValueInArrayIgnoreCase(tags, tag))
                continue;
            new_tags.push(tag);
            tags.push(tag);
        }
        tags.sort();
        // update
        this.showTags(comment_id, comment_no, tags);
        this.fetchUpdate(comment_id, comment_no, new_tags, undefined);
    },

    remove : function(comment_id, comment_no, tag) {
        var el = document.getElementById(`ct_${comment_no}_${tag}`);
        if (el) {
            el.parentNode.removeChild(el);
            this.fetchUpdate(comment_id, comment_no, undefined, [ tag ]);
            this.hideEmpty(comment_no);
        }
    },

    // If multiple updates are triggered quickly, overlapping refresh events
    // are generated. We ignore all events except the last one.
    incPending : function(comment_id) {
        if (this.pending['c' + comment_id] == undefined) {
            this.pending['c' + comment_id] = 1;
        } else {
            this.pending['c' + comment_id]++;
        }
    },

    decPending : function(comment_id) {
        if (this.pending['c' + comment_id] != undefined)
            this.pending['c' + comment_id]--;
    },

    hasPending : function(comment_id) {
        return this.pending['c' + comment_id] != undefined
               && this.pending['c' + comment_id] > 0;
    },

    fetchRefresh : async (comment_id, comment_no, noRefreshOnError) => {
        const self = Bugzilla.CommentTagging;

        self.incPending(comment_id);

        try {
            const { comments } = await Bugzilla.API.get(`bug/comment/${comment_id}?include_fields=tags`);

            self.decPending(comment_id);

            if (!self.hasPending(comment_id)) {
                self.showTags(comment_id, comment_no, comments[comment_id].tags);
            }
        } catch ({ message }) {
            self.decPending(comment_id);
            self.handleFetchError(comment_id, comment_no, message, noRefreshOnError);
        }
    },

    fetchUpdate : async (comment_id, comment_no, add, remove) => {
        const self = Bugzilla.CommentTagging;

        self.incPending(comment_id);

        try {
            const data = await Bugzilla.API.put(`bug/comment/${comment_id}/tags`, { comment_id, add, remove });

            if (!self.hasPending(comment_id)) {
                self.showTags(comment_id, comment_no, data);
            }
        } catch ({ message }) {
            self.decPending(comment_id);
            self.handleFetchError(comment_id, comment_no, message);
        }
    },

    handleFetchError : (comment_id, comment_no, message, noRefreshOnError) => {
        const self = Bugzilla.CommentTagging;

        self.showError(comment_id, comment_no, message);

        if (!noRefreshOnError) {
            self.fetchRefresh(comment_id, comment_no, true);
        }
    }
}
