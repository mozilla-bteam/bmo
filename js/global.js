/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

function show_mini_login_form( suffix ) {
    $('#login_link' + suffix).addClass('bz_default_hidden');
    $('#mini_login' + suffix).removeClass('bz_default_hidden');
    $('#new_account_container' + suffix).addClass('bz_default_hidden');
    return false;
}

function hide_mini_login_form( suffix ) {
    $('#login_link' + suffix).removeClass('bz_default_hidden');
    $('#mini_login' + suffix).addClass('bz_default_hidden');
    $('#new_account_container' + suffix).removeClass('bz_default_hidden');
    return false;
}

function show_forgot_form( suffix ) {
    $('#forgot_link' + suffix).addClass('bz_default_hidden');
    $('#forgot_form' + suffix).removeClass('bz_default_hidden');
    $('#login_container' + suffix).addClass('bz_default_hidden');
    return false;
}

function hide_forgot_form( suffix ) {
    $('#forgot_link' + suffix).removeClass('bz_default_hidden');
    $('#forgot_form' + suffix).addClass('bz_default_hidden');
    $('#login_container' + suffix).removeClass('bz_default_hidden');
    return false;
}

function init_mini_login_form( suffix ) {
    var mini_login = document.getElementById('Bugzilla_login' +  suffix );
    var mini_password = document.getElementById('Bugzilla_password' +  suffix );
    var mini_dummy = document.getElementById('Bugzilla_password_dummy' + suffix);
    // If the login and password are blank when the page loads, we display
    // "login" and "password" in the boxes by default.
    if (mini_login.value == "" && mini_password.value == "") {
        YAHOO.util.Dom.addClass(mini_password, 'bz_default_hidden');
        YAHOO.util.Dom.removeClass(mini_dummy, 'bz_default_hidden');
    }
    else {
        show_mini_login_form(suffix);
    }
}

function check_mini_login_fields( suffix ) {
    var mini_login = document.getElementById('Bugzilla_login' +  suffix );
    var mini_password = document.getElementById('Bugzilla_password' +  suffix );
    if (mini_login.value != "" && mini_password.value != "") {
        return true;
    } else {
        window.alert("You must provide the email address and password before logging in.");
        return false;
    }
}

function set_language( value ) {
    $.cookie('LANG', value, {
        expires: new Date('January 1, 2038'),
        path: BUGZILLA.param.cookie_path
    });
    window.location.reload()
}

// This basically duplicates Bugzilla::Util::display_value for code that
// can't go through the template and has to be in JS.
function display_value(field, value) {
    var field_trans = BUGZILLA.value_descs[field];
    if (!field_trans) return value;
    var translated = field_trans[value];
    if (translated) return translated;
    return value;
}

// polyfill .trim
if (!String.prototype.trim) {
    (function() {
        // Make sure we trim BOM and NBSP
        var rtrim = /^[\s\uFEFF\xA0]+|[\s\uFEFF\xA0]+$/g;
        String.prototype.trim = function() {
            return this.replace(rtrim, '');
        };
    })();
}

// html encoding
if (!String.prototype.htmlEncode) {
    (function() {
        String.prototype.htmlEncode = function() {
            return this.replace(/&/g, '&amp;')
                       .replace(/</g, '&lt;')
                       .replace(/>/g, '&gt;')
                       .replace(/"/g, '&quot;');
        };
    })();
}

// jQuery auto-completion disables browser native autocompletion, however this
// excludes it from being restored by bfcache. Trick the browser into restoring
// it by changing the autocomplete attribute when a page is hidden and shown.
$().ready(function() {
  $(window).on('pagehide', function() {
    $('.bz_autocomplete').attr('autocomplete', 'on');
  });
  $(window).on('pageshow', function() {
    $('.bz_autocomplete').attr('autocomplete', 'off');
  });
});
