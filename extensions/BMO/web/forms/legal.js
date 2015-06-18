/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
    'use strict';

    // navigation

    function navigateFromHash() {
        navigateTo(location.hash.substring(3));
    }

    function navigateTo(panel) {
        if (panel === '')
            panel = 'start';
        if ($('.panel:visible').attr('id') === panel)
            return;
        $('.panel').hide();
        $('.panel').find('select, input[type=text], textarea').removeAttr('required');
        if (panel === 'start') {
            $('#start').show();
            location.hash = '';
            if (history && 'pushState' in history)
                history.pushState('', document.title, window.location.pathname + window.location.search);
        }
        else {
            $('#' + panel).find('select, input[type=text], textarea').each(function() {
                var that = $(this);
                if (that.data('required'))
                    that.attr('required', 'required');
            });
            $('#' + panel).show();
            location.hash = 'p-' + panel;
        }
    }

    if ('onhashchange' in window) {
        window.onhashchange = navigateFromHash;
    }
    navigateFromHash();

    // all panels

    $('.return-to-start')
        .click(function(event) {
            event.preventDefault();
            navigateTo('');
        });

    // start

    $('#contract-yes-rb, #contract-no-rb')
        .click(function() {
            if ($('#contract-yes-rb').is(':checked')) {
                $('#contract-yes').show();
                $('#contract-no').hide();
            }
            else {
                $('#contract-yes').hide();
                $('#contract-no').show();
            }
        });
        $('#contract-yes-rb:checked, #contract-no-rb:checked')
            .click();

    $('.start-option .q')
        .click(function(event) {
            event.preventDefault();
            navigateTo($(this).data('for'));
            $('#contract-yes-rb:checked, #contract-no-rb:checked')
                .click();
        });

    // 'other'

    $('.panel select')
        .change(function(event) {
            var that = $(this);
            var other = $('#' + that.attr('id') + '-other');
            if (!other) return;
            if (that.val() === 'Other') {
                other.removeAttr('disabled').show();
            }
            else {
                other.hide().attr('disabled', 'disabled');
            }
        })
        .change();

    // submit

    $('#legalForm')
        .submit(function(event) {
            var panel = $('.panel:visible');
            var prefix = panel.data('prefix');
            var fields = $.grep($('#all_fields').val().split(' '), function(field) {
                return field.substring(0, prefix.length + 1) === prefix + '-';
            });
            $('#fields').val(fields.join(' '));

            // component
            $('#component').val(panel.data('component'));

            // short_desc
            $('#short_desc').val($('#' + panel.data('prefix') + '-summary').val());

            // assignee
            var assignee = '';
            $('select:visible option:selected').each(function() {
                var a = $(this).data('assignee');
                if (!a) return;
                assignee = a;
                return false;
            });
            if (assignee === '')
                assignee = panel.data('assignee');
            if (assignee === '')
                assignee = 'nobody@mozilla.org';
            $('#assigned_to').val(assignee);

            // cc
            var cc = panel.data('cc');
            $('select:visible option:selected').each(function() {
                var cc = $(this).data('cc');
                if (!cc) return;
                cc += ', ' + cc;
                return false;
            });
            $('#cc').val(cc.replace(/^,\s*/, ''));

            // keywords
            var keywords = [];
            $('select:visible option:selected').each(function() {
                var keyword = $(this).data('keyword');
                if (keyword)
                    keywords.push(keyword);
            });
            $('#keywords').val(keywords.join(','));
        });
});
