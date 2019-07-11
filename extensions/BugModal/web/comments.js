/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
    'use strict';

    // comment collapse/expand

    const update_spinner = (spinner, expanded) => {
        const str = BUGZILLA.string;

        spinner.attr({
            'aria-label': expanded ? str.collapse : str.expand,
            'aria-expanded': expanded,
        });
    };

    function toggleChange(spinner, forced) {
        var spinnerID = spinner.attr('id');
        var id = spinnerID.substring(spinnerID.indexOf('-') + 1);

        // non-comment toggle
        if (spinnerID.substr(0, 1) == 'a') {
            var changeSet = spinner.parents('.change-set');
            if (forced == 'hide') {
                changeSet.attr('aria-expanded', false).find('.activity, .attachment, footer').hide();
                update_spinner(spinner, false);
            }
            else if (forced == 'show' || forced == 'reset') {
                changeSet.attr('aria-expanded', true).find('.activity, .attachment, footer').show();
                update_spinner(spinner, true);
            }
            else {
                changeSet.find('.activity, .attachment, footer').toggle('fast', function() {
                    const show = !!changeSet.find('.activity:visible').length;
                    changeSet.attr('aria-expanded', show);
                    update_spinner(spinner, show);
                });
            }
            return;
        }

        const defaultCollapsed = document.querySelector(`#c${id}`).matches('.default-collapsed');

        if (forced === 'reset') {
            forced = defaultCollapsed ? 'hide' : 'show';
        }

        // comment toggle
        if (forced === 'hide') {
            if (defaultCollapsed) {
                $('#cc-' + id).show();
            }
            $('#ct-' + id).hide();
            $('#c' + id).attr('aria-expanded', false).find('.activity, .attachment, footer').hide();
            update_spinner(spinner, false);
        }
        else if (forced == 'show') {
            if (defaultCollapsed) {
                $('#cc-' + id).hide();
            }
            $('#ct-' + id).show();
            $('#c' + id).attr('aria-expanded', true).find('.activity, .attachment, footer').show();
            update_spinner(spinner, true);
        }
        else {
            $('#ct-' + id).slideToggle('fast', function() {
                $('#c' + id).find('.activity, .attachment, footer').toggle();
                if ($('#ct-' + id + ':visible').length) {
                    update_spinner(spinner, true);
                    $('#c' + id).attr('aria-expanded', true);
                    if (defaultCollapsed) {
                        $('#cc-' + id).hide();
                    }
                }
                else {
                    update_spinner(spinner, false);
                    $('#c' + id).attr('aria-expanded', false);
                    if (defaultCollapsed) {
                        $('#cc-' + id).show();
                    }
                }
            });
        }
    }

    $('.change-spinner')
        .click(function(event) {
            event.preventDefault();
            toggleChange($(this));
        });

    // view and tag menus

    $('#view-reset')
        .click(function() {
            $('.change-spinner:visible').each(function() {
                toggleChange($(this), 'reset');
            });
        });

    $('#view-collapse-all')
        .click(function() {
            $('.change-spinner:visible').each(function() {
                toggleChange($(this), 'hide');
            });
        });

    $('#view-expand-all')
        .click(function() {
            $('.change-spinner:visible').each(function() {
                toggleChange($(this), 'show');
            });
        });

    $('#view-comments-only')
        .click(function() {
            $('.change-spinner:visible').each(function() {
                toggleChange($(this), this.id.substr(0, 3) === 'cs-' ? 'show' : 'hide');
            });
        });

    $('#view-toggle-treeherder')
        .click(function() {
            var that = $(this);
            var userids = that.data('userids');
            if (that.data('hidden') === '0') {
                that.data('hidden', '1');
                that.text('Show Treeherder Comments');
                userids.forEach((id) => {
                    $('.ca-' + id).each(function() {
                        toggleChange($(this).find('.default-collapsed .change-spinner').first(), 'hide');
                    });
                });
            }
            else {
                that.data('hidden', '0');
                that.text('Hide Treeherder Comments');
                userids.forEach((id) => {
                    $('.ca-' + id).each(function() {
                        toggleChange($(this).find('.default-collapsed .change-spinner').first(), 'show');
                    });
                });
            }
        });

    function updateTagsMenu() {
        var tags = [];
        $('.comment-tags .tag').each(function() {
            $.each(tagsFromDom($(this)), function() {
                var tag = this.toLowerCase();
                if (tag in tags) {
                    tags[tag]++;
                }
                else {
                    tags[tag] = 1;
                }
            });
        });
        var tagNames = Object.keys(tags);
        tagNames.sort();

        var btn = $('#comment-tags-btn');
        if (tagNames.length === 0) {
            btn.hide();
            return;
        }
        btn.show();

        // clear out old li items. Always leave the first one (Reset)
        var $li = $('#comment-tags-menu li');
        for (var i = 1, l = $li.length; i < l; i++) {
            $li.eq(i).remove();
        }

        // add new li items
        $.each(tagNames, function(key, value) {
            $('#comment-tags-menu')
                .append($('<li role="presentation">')
                    .append($('<a role="menuitem" tabindex="-1" data-comment-tag="' + value + '">')
                        .append(value + ' (' + tags[value] + ')')));
        });

        $('a[data-comment-tag]').each(function() {
            $(this).click(function() {
                var $that = $(this);
                var tag = $that.data('comment-tag');
                if (tag === '') {
                    $('.change-spinner:visible').each(function() {
                        toggleChange($(this), 'reset');
                    });
                    return;
                }
                var firstComment = false;
                $('.change-spinner:visible').each(function() {
                    var $that = $(this);
                    var commentTags = tagsFromDom($that.parents('.comment').find('.comment-tags'));
                    var hasTag = $.inArrayIn(tag, commentTags) >= 0;
                    toggleChange($that, hasTag ? 'show' : 'hide');
                    if (hasTag && !firstComment) {
                        firstComment = $that;
                    }
                });
                if (firstComment)
                    $.scrollTo(firstComment);
            });
        });
    }

    //
    // anything after this point is only executed for logged in users
    //

    if (BUGZILLA.user.id === 0) return;

    // comment tagging

    function taggingError(commentNo, message) {
        $('#ctag-' + commentNo + ' .comment-tags').append($('#ctag-error'));
        $('#ctag-error-message').text(message);
        $('#ctag-error').show();
    }

    async function deleteTag(event) {
        event.preventDefault();
        $('#ctag-error').hide();

        var that = $(this);
        var comment = that.parents('.comment');
        var commentNo = comment.data('no');
        var commentID = comment.data('id');
        var tag = that.parent('.tag').contents().filter(function() {
            return this.nodeType === 3;
        }).text();
        var container = that.parents('.list');

        // update ui
        that.parent('.tag').remove();
        renderTags(commentNo, tagsFromDom(container));
        updateTagsMenu();

        // update bugzilla
        try {
            renderTags(commentNo, await Bugzilla.API.put(`bug/comment/${commentID}/tags`, { remove: [tag] }));
            updateTagsMenu();
        } catch ({ message }) {
            taggingError(commentNo, message);
        }
    }
    $('.comment-tags .tag a').click(deleteTag);

    function tagsFromDom(commentTagsDiv) {
        return commentTagsDiv
            .find('.tag')
            .contents()
            .filter(function() { return this.nodeType === 3; })
            .map(function() { return $(this).text(); })
            .toArray();
    }

    function renderTags(commentNo, tags) {
        cancelRefresh();
        var root = $('#ctag-' + commentNo + ' .list');
        root.find('.tag').remove();
        $.each(tags, function() {
            var span = $('<span itemprop="keywords" />').addClass('tag').text(this);
            if (BUGZILLA.user.can_tag) {
                span.prepend($('<a role="button" aria-label="Remove">x</a>').click(deleteTag));
            }
            root.append(span);
        });
        $('#ctag-' + commentNo).append($('#ctag-error'));
        $(`.comment[data-no="${commentNo}"]`).attr('data-tags', tags.join(' '));
    }

    let abort_controller;

    const refreshTags = async (commentNo, commentID) => {
        cancelRefresh();

        try {
            abort_controller = new AbortController();

            const { signal } = abort_controller;
            const { comments } = await Bugzilla.API.get(`bug/comment/${commentID}`, {
              include_fields: ['tags'],
            }, { signal });

            renderTags(commentNo, comments[commentID].tags);
        } catch ({ name, message }) {
            if (name !== 'AbortError') {
                taggingError(commentNo, message);
            }
        } finally {
            abort_controller = undefined;
        }
    }

    function cancelRefresh() {
        if (abort_controller) {
            abort_controller.abort();
            abort_controller = undefined;
        }
    }

    $('#ctag-add')
        .devbridgeAutocomplete({
            appendTo: $('#main-inner'),
            forceFixPosition: true,
            deferRequestBy: 250,
            minChars: 3,
            tabDisabled: true,
            autoSelectFirst: true,
            triggerSelectOnValidInput: false,
            lookup: (query, done) => {
                // Note: `async` doesn't work for this `lookup` function, so use a `Promise` chain instead
                Bugzilla.API.get(`bug/comment/tags/${encodeURIComponent(query)}`)
                    .then(data => data.map(tag => ({ value: tag })))
                    .catch(() => [])
                    .then(suggestions => done({ suggestions }));
            },
            formatResult: function(suggestion, currentValue) {
                // disable <b> wrapping of matched substring
                return suggestion.value.htmlEncode();
            }
        })
        .keydown(async event => {
            if (event.which === 27) {
                event.preventDefault();
                $('#ctag-close').click();
            }
            else if (event.which === 13) {
                event.preventDefault();
                $('#ctag-error').hide();

                var ctag = $('#ctag');
                var newTags = $('#ctag-add').val().trim().split(/[ ,]/);
                var commentNo = ctag.data('commentNo');
                var commentID = ctag.data('commentID');

                $('#ctag-close').click();

                // update ui
                var tags = tagsFromDom($(this).parents('.list'));
                var dirty = false;
                var addTags = [];
                $.each(newTags, function(index, value) {
                    if ($.inArrayIn(value, tags) == -1)
                        addTags.push(value);
                });
                if (addTags.length === 0)
                    return;

                // validate
                try {
                    $.each(addTags, function(index, value) {
                        if (value.length < BUGZILLA.constant.min_comment_tag_length) {
                            throw 'Comment tags must be at least ' +
                                BUGZILLA.constant.min_comment_tag_length + ' characters.';
                        }
                        if (value.length > BUGZILLA.constant.max_comment_tag_length) {
                            throw 'Comment tags cannot be longer than ' +
                                BUGZILLA.constant.min_comment_tag_length + ' characters.';
                        }
                    });
                } catch(ex) {
                    taggingError(commentNo, ex);
                    return;
                }

                Array.prototype.push.apply(tags, addTags);
                tags.sort();
                renderTags(commentNo, tags);

                // update bugzilla
                try {
                    renderTags(commentNo, await Bugzilla.API.put(`bug/comment/${commentID}/tags`, { add: addTags }));
                    updateTagsMenu();
                } catch ({ message }) {
                    taggingError(commentNo, message);
                    refreshTags(commentNo, commentID);
                }
            }
        });

    $('#ctag-close')
        .click(function(event) {
            event.preventDefault();
            $('#ctag').hide().data('commentNo', '');
            if (!$('#ctag').closest('.comment-tags').find('.tag').length) {
                $('#ctag').closest('footer').attr('hidden', '');
            }
        });

    $('.tag-btn')
        .click(function(event) {
            event.preventDefault();
            var that = $(this);
            var commentNo = that.data('no');
            var commentID = that.data('id');
            var ctag = $('#ctag');
            $('#ctag-error').hide();

            // toggle -> hide
            if (ctag.data('commentNo') === commentNo) {
                ctag.hide().data('commentNo', '');
                if (!ctag.closest('.comment-tags').find('.tag').length) {
                    ctag.closest('footer').attr('hidden', '');
                }
                window.focus();
                return;
            }
            ctag.data('commentNo', commentNo);
            ctag.data('commentID', commentID);

            // kick off a refresh of the tags
            refreshTags(commentNo, commentID);

            // expand collapsed comments
            if ($('#ct-' + commentNo + ':visible').length === 0) {
                $('#cs-' + commentNo).click();
            }

            // move, show, and focus tagging ui
            $('#ctag-' + commentNo + ' .list').after(ctag);
            ctag.show();
            ctag.closest('footer').removeAttr('hidden');
            $('#ctag-add').val('').focus();
        });

    $('.close-btn')
        .click(function(event) {
            event.preventDefault();
            $('#' + $(this).data('for')).hide();
            if (!$(this).closest('.comment-tags').find('.tag').length) {
                $(this).closest('footer').attr('hidden', '');
            }
        });

    updateTagsMenu();
});

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {};

/**
 * Reference or define the Review namespace.
 * @namespace
 */
Bugzilla.BugModal = Bugzilla.BugModal || {};

/**
 * Implement the modal bug view's comment-related functionality.
 */
Bugzilla.BugModal.Comments = class Comments {
  /**
   * Initiate a new Comments instance.
   */
  constructor() {
    this.prepare_inline_attachments();
  }

  /**
   * Prepare to show image, media and text attachments inline if possible. For a better performance, this functionality
   * uses the Intersection Observer API to show attachments when the associated comment goes into the viewport, when the
   * page is scrolled down or the collapsed comment is expanded. This also utilizes the Network Information API to save
   * @see https://developer.mozilla.org/en-US/docs/Web/API/Intersection_Observer_API
   * @see https://developer.mozilla.org/en-US/docs/Web/API/Network_Information_API
   */
  prepare_inline_attachments() {
    // Check the connectivity, API support, user setting, bug security and sensitive keywords
    if ((navigator.connection && navigator.connection.type === 'cellular') ||
        typeof IntersectionObserver !== 'function' || !BUGZILLA.user.settings.inline_attachments ||
        BUGZILLA.bug_secure ||
        BUGZILLA.bug_keywords.split(', ').find(keyword => keyword.match(/^(hang|assertion|crash)$/))) {
      return;
    }

    const observer = new IntersectionObserver(entries => entries.forEach(entry => {
      const $att = entry.target;

      if (entry.intersectionRatio > 0) {
        observer.unobserve($att);
        this.show_attachment($att);
      }
    }), { root: document.querySelector('#bugzilla-body') });

    document.querySelectorAll('.change-set').forEach($set => {
      // Skip if the comment has the `hide-attachment` tag
      const $comment = $set.querySelector('.comment:not([data-tags~="hide-attachment"])');
      // Skip if the attachment is obsolete or deleted
      const $attachment = $set.querySelector('.attachment:not(.obsolete):not(.deleted)');

      if ($comment && $attachment) {
        observer.observe($attachment);
      }
    });
  }

  /**
   * Load and show an image, audio, video or text attachment.
   * @param {HTMLElement} $att An attachment wrapper element.
   */
  async show_attachment($att) {
    const id = Number($att.dataset.id);
    const link = $att.querySelector('.link').href;
    const name = $att.querySelector('[itemprop="name"]').content;
    const type = $att.querySelector('[itemprop="encodingFormat"]').content;
    const size = Number($att.querySelector('[itemprop="contentSize"]').content);

    // Skip if the attachment is marked as binary
    if (type.match(/^application\/(?:octet-stream|binary)$/)) {
      return;
    }

    // Show image smaller than 2 MB, excluding SVG and non-standard formats
    if (type.match(/^image\/(?!vnd|svg).+$/) && size < 2000000) {
      $att.insertAdjacentHTML('beforeend', `
        <a href="${link}" class="outer lightbox"><img src="${link}" alt="${name.htmlEncode()}" itemprop="image"></a>`);

      // Add lightbox support
      $att.querySelector('.outer.lightbox').addEventListener('click', event => {
        if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) {
          return;
        }

        event.preventDefault();
        lb_show(event.target);
      });
    }

    // Show audio and video
    if (type.match(/^(?:audio|video)\/(?!vnd).+$/)) {
      const media = type.split('/')[0];

      if (document.createElement(media).canPlayType(type)) {
        $att.insertAdjacentHTML('beforeend', `
          <span class="outer"><${media} src="${link}" controls itemprop="${media}"></span>`);
      }
    }

    // Detect text (code from attachment.js)
    const is_patch = $att.matches('.patch');
    const is_markdown = !!name.match(/\.(?:md|mkdn?|mdown|markdown)$/);
    const is_source = !!name.match(/\.(?:cpp|es|h|js|json|rs|rst|sh|toml|ts|tsx|xml|yaml|yml)$/);
    const is_text = type.match(/^text\/(?!x-).+$/) || is_patch || is_markdown || is_source;

    // Show text smaller than 50 KB
    if (is_text && size < 50000) {
      // Load text body
      try {
        const { attachments } = await Bugzilla.API.get(`bug/attachment/${id}`, { include_fields: 'data' });
        const text = decodeURIComponent(escape(atob(attachments[id].data)));
        const lang = is_patch ? 'diff' : type.match(/\w+$/)[0];

        $att.insertAdjacentHTML('beforeend', `
          <button type="button" role="link" title="${name.htmlEncode()}" class="outer">
          <pre class="language-${lang}" role="img" itemprop="text">${text.htmlEncode()}</pre></button>`);

        // Make the button work as a link. It cannot be `<a>` because Prism Autolinker plugin may add links to `<pre>`
        $att.querySelector('[role="link"]').addEventListener('click', () => location.href = link);

        if (Prism) {
          Prism.highlightElement($att.querySelector('pre'));
          $att.querySelectorAll('pre a').forEach($a => $a.tabIndex = -1);
        }
      } catch (ex) {}
    }
  }
};

document.addEventListener('DOMContentLoaded', () => new Bugzilla.BugModal.Comments(), { once: true });
