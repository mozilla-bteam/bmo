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
 * The Initial Developer of the Original Code is Netscape Communications
 * Corporation. Portions created by Netscape are
 * Copyright (C) 1998 Netscape Communications Corporation. All
 * Rights Reserved.
 *
 * Contributor(s): Dennis Melentyev <dennis.melentyev@infopulse.com.ua>
 *                 Max Kanat-Alexander <mkanat@bugzilla.org>
 */

/* This file provides JavaScript functions to be included when one wishes
 * to show/hide certain UI elements, and have the state of them being
 * shown/hidden stored in a cookie.
 *
 * TUI stands for Tweak UI.
 *
 * Requires js/util.js.
 *
 * See template/en/default/bug/create/create.html.tmpl for a usage example.
 */

var TUI_HIDDEN_CLASS = 'bz_tui_hidden';
var TUI_STORAGE_KEY  = 'TUI';

var TUI_alternates = new Array();

/**
 * Migrate the legacy cookie to local storage.
 */
const _TUI_migrate_cookie = () => {
    const cookie = document.cookie
        .split('; ')
        .find((c) => c.startsWith(`${TUI_STORAGE_KEY}=`))
        ?.substring(TUI_STORAGE_KEY.length + 1);

    const prefs = cookie ? Object.fromEntries(
        cookie.split('&').map((p) => {
            const [key, value] = p.split('=');
            return [key, Number(value)];
        })
    ) : {};

    Bugzilla.Storage.set(TUI_STORAGE_KEY, prefs);
};

/**
 * Hides a particular class of elements if they are shown,
 * or shows them if they are hidden. Then it stores whether that
 * class is now hidden or shown.
 *
 * @param className   The name of the CSS class to hide.
 */
function TUI_toggle_class(className) {
    var elements = [...document.querySelectorAll(`.${className}`)];
    for (var i = 0; i < elements.length; i++) {
        bz_toggleClass(elements[i], TUI_HIDDEN_CLASS);
    }
    _TUI_save_class_state(elements, className);
    _TUI_toggle_control_link(className);
}


/**
 * Specifies that a certain class of items should be hidden by default,
 * if the user doesn't have a TUI cookie.
 *
 * @param className   The class to hide by default.
 */
function TUI_hide_default(className) {
    const _hide = () => {
        if (!Bugzilla.Storage.get(TUI_STORAGE_KEY)?.[className]) {
            let restored = false;
            document.querySelectorAll(`.${className}`).forEach(($item) => {
                if (!$item.classList.contains(TUI_HIDDEN_CLASS)) {
                    $item.classList.add(TUI_HIDDEN_CLASS);
                    restored = true;
                }
            });
            if (restored) {
                _TUI_toggle_control_link(className);
            }
        }
    };

    if (document.readyState === 'complete') {
        _hide();
    } else {
        window.addEventListener('DOMContentLoaded', () => {
            _hide();
        });
    }
}

function _TUI_toggle_control_link(className) {
    var link = document.getElementById(className + "_controller");
    if (!link) return;
    var original_text;
    if (link.nodeName == 'INPUT') {
      original_text = link.value;
      link.value = TUI_alternates[className];
    } else {
      original_text = link.innerHTML;
      link.innerHTML = TUI_alternates[className];
    }
    TUI_alternates[className] = original_text;
}

function _TUI_save_class_state(elements, aClass) {
    // We just check the first element to see if it's hidden or not, and
    // consider that all elements are the same.
    _TUI_store(aClass, elements[0].classList.contains(TUI_HIDDEN_CLASS) ? 0 : 1);
}

function _TUI_store(aClass, state) {
    Bugzilla.Storage.update(TUI_STORAGE_KEY, { [aClass]: state });
}

function _TUI_restore() {
    Object.entries(Bugzilla.Storage.get(TUI_STORAGE_KEY, true)).forEach(([className]) => {
        TUI_hide_default(className);
    });
}

window.addEventListener('DOMContentLoaded', () => {
    if (!Bugzilla.Storage.get(TUI_STORAGE_KEY)) {
        _TUI_migrate_cookie();
    }

    _TUI_restore();
});
