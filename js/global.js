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
* Contributor(s):
*   Guy Pyrzak <guy.pyrzak@gmail.com>
*   Max Kanat-Alexander <mkanat@bugzilla.org>
*
*/

var BUGZILLA = $("#bugzilla-global").data("bugzilla");

$(function () {
  $('body').addClass("platform-" + navigator.platform);
  $('.show_mini_login_form').on("click", function (event) {
    return show_mini_login_form($(this).data('qs-suffix'));
  });
  $('.hide_mini_login_form').on("click", function (event) {
    return hide_mini_login_form($(this).data('qs-suffix'));
  });
  $('.show_forgot_form').on("click", function (event) {
    return show_forgot_form($(this).data('qs-suffix'));
  });
  $('.hide_forgot_form').on("click", function (event) {
    return hide_forgot_form($(this).data('qs-suffix'));
  });
  $('.check_mini_login_fields').on("click", function (event) {
    return check_mini_login_fields($(this).data('qs-suffix'));
  });
  $('.quicksearch_check_empty').on("submit", function (event) {
      if (this.quicksearch.value == '') {
          alert('Please enter one or more search terms first.');
          event.preventDefault();
      }
  });

  unhide_language_selector();
  $("#lob_action").on("change", update_text);
  $("#lob_newqueryname").on("keyup", manage_old_lists);
});

function unhide_language_selector() {
    $('#lang_links_container').removeClass('bz_default_hidden');
}

function update_text() {
    // 'lob' means list_of_bugs.
    var lob_action = document.getElementById('lob_action');
    var action = lob_action.options[lob_action.selectedIndex].value;
    var text = document.getElementById('lob_direction');
    var new_query_text = document.getElementById('lob_new_query_text');

    if (action == "add") {
        text.innerHTML = "to";
        new_query_text.style.display = 'inline';
    }
    else {
        text.innerHTML = "from";
        new_query_text.style.display = 'none';
    }
}

function manage_old_lists() {
    var old_lists = document.getElementById('lob_oldqueryname');
    // If there is no saved searches available, returns.
    if (!old_lists) return;

    var new_query = document.getElementById('lob_newqueryname').value;

    if (new_query != "") {
        old_lists.disabled = true;
    }
    else {
        old_lists.disabled = false;
    }
}


function show_mini_login_form( suffix ) {
    hide_forgot_form(suffix);
    $('#mini_login' + suffix).removeClass('bz_default_hidden').find('input[required]:first').focus();
    $('#new_account_container' + suffix).addClass('bz_default_hidden');
    return false;
}

function hide_mini_login_form( suffix ) {
    $('#mini_login' + suffix).addClass('bz_default_hidden');
    $('#new_account_container' + suffix).removeClass('bz_default_hidden');
    return false;
}

function show_forgot_form( suffix ) {
    hide_mini_login_form(suffix);
    $('#forgot_form' + suffix).removeClass('bz_default_hidden').find('input[required]:first').focus();
    $('#login_container' + suffix).addClass('bz_default_hidden');
    return false;
}


function hide_forgot_form( suffix ) {
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
        mini_password.classList.add('bz_default_hidden');
        mini_dummy.classList.remove('bz_default_hidden');
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

// This basically duplicates Bugzilla::Util::display_value for code that
// can't go through the template and has to be in JS.
function display_value(field, value) {
    var field_trans = BUGZILLA.value_descs[field];
    if (!field_trans) return value;
    var translated = field_trans[value];
    if (translated) return translated;
    return value;
}

// HTML encoding
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

// Insert `<wbr>` HTML tags to camel and snake case words as well as
// words containing dots in the given string so a long bug summary,
// for example, will be wrapped in a preferred manner rather than
// overflowing or expanding the parent element. This conversion
// should exclude existing HTML tags such as links. Examples:
// * `test<wbr>_switch<wbr>_window<wbr>_content<wbr>.py`
// * `Test<wbr>Switch<wbr>To<wbr>Window<wbr>Content`
// * `<a href="https://www.mozilla.org/">mozilla<wbr>.org</a>`
// * `MOZILLA<wbr>_PKIX<wbr>_ERROR<wbr>_MITM<wbr>_DETECTED`
// This is the JavaScript version of `wbr` in Bugzilla/Template.pm.
if (!String.prototype.wbr) {
    (function() {
        String.prototype.wbr = function() {
            return this.replace(/([a-z])([A-Z])(?![^<]*>)/g, '$1<wbr>$2')
                       .replace(/([A-Za-z0-9])([\._])(?![^<]*>)/g, '$1<wbr>$2');
        };
    })();
}

// our auto-completion disables browser native autocompletion, however this
// excludes it from being restored by bf-cache.  trick the browser into
// restoring by changing the autocomplete attribute when a page is hidden and
// shown.
$().ready(function() {
    $(window).on('pagehide', function() {
        $('.bz_autocomplete').attr('autocomplete', 'on');
    });
    $(window).on('pageshow', function(event) {
        $('.bz_autocomplete').attr('autocomplete', 'off');
    });
});

/**
 * Focus the main content when the page is loaded and there is no autofocus
 * element, so the user can immediately scroll down the page using keyboard.
 */
const focus_main_content = () => {
    if (!document.querySelector('[autofocus]')) {
        document.querySelector('main').focus();
    }
}

/**
 * Check if Gravatar images on the page are successfully loaded, and if blocked
 * (by any content blocker), replace them with the default/fallback image.
 */
const detect_blocked_gravatars = () => {
    document.querySelectorAll('img[src^="https://secure.gravatar.com/avatar/"]').forEach($img => {
        if (!$img.complete || !$img.naturalHeight) {
            $img.src = `${BUGZILLA.config.basepath}extensions/Gravatar/web/default.jpg`;
        }
    });
}

/**
 * Bring an element into the visible area of the browser window. Smooth scroll
 * can be done using CSS, and an extra space can also be added to the top using
 * CSS `scroll-padding-top`.
 * @param {Element} $target - An element to be brought.
 * @param {Function} [complete] - An optional callback function to be executed
 *  once the scroll is complete.
 */
const scroll_element_into_view = ($target, complete) => {
    if (typeof complete === 'function') {
        const callback = () => {
            document.documentElement.removeEventListener('scroll', listener);
            complete();
        };

        // Emulate the `scrollend` event
        const listener = () => {
            window.clearTimeout(timer);
            timer = window.setTimeout(callback, 100);
        };

        // Make sure the callback is always fired even if no scroll happened
        let timer = window.setTimeout(callback, 100);

        document.documentElement.addEventListener('scroll', listener);
    }

    $target.scrollIntoViewIfNeeded?.() ?? $target.scrollIntoView();
}

const openBanner = () => {
  // Bind click event listeners for banner buttons
  document
    .getElementById("moz-consent-banner-button-accept")
    .addEventListener("click", MozConsentBanner.onAcceptClick, false);
  document
    .getElementById("moz-consent-banner-button-reject")
    .addEventListener("click", MozConsentBanner.onRejectClick, false);

  // Show the banner
  document.getElementById("moz-consent-banner").classList.add("is-visible");
};

const closeBanner = () => {
  // Unbind click event listeners
  document
    .getElementById("moz-consent-banner-button-accept")
    .removeEventListener("click", MozConsentBanner.onAcceptClick, false);
  document
    .getElementById("moz-consent-banner-button-reject")
    .removeEventListener("click", MozConsentBanner.onRejectClick, false);

  // Hide the banner
  document.getElementById("moz-consent-banner").classList.remove("is-visible");
};

window.addEventListener('DOMContentLoaded', focus_main_content, { once: true });
window.addEventListener('load', detect_blocked_gravatars, { once: true });

window.addEventListener('DOMContentLoaded', () => {
  const announcement = document.getElementById('new_announcement');
  if (announcement) {
    const hide_announcement = () => {
      const checksum = announcement.dataset.checksum;
      const url = `${BUGZILLA.config.basepath}announcement/hide/${checksum}`;
      fetch(url, { method: "POST" }).then(
        response => announcement.style.display = "none"
      );
      Bugzilla.Storage.set("announcement_checksum", checksum);
    }
    announcement.addEventListener('click', hide_announcement);
    window.addEventListener('visibilitychange', () => {
      if (!window.hidden) {
        const hidden_checksum = Bugzilla.Storage.get("announcement_checksum");
        if (hidden_checksum && hidden_checksum == announcement.dataset.checksum) {
          announcement.style.display = "none";
        }
      }
    });
  }

  // Mozilla Consent Banner
  // Bind open and close events before calling init().
  if (BUGZILLA.config.cookie_consent_enabled) {
    window.addEventListener('mozConsentOpen', openBanner, false);
    window.addEventListener('mozConsentReset', openBanner, false);
    window.addEventListener('mozConsentClose', closeBanner, false);
    window.addEventListener('mozConsentStatus', (e) => {
        console.log(e.detail); // eslint-disable-line no-console
    });
    MozConsentBanner.init({
      helper: CookieHelper,
    });

    // Listen for click to reset cookie preference
    let $reset_cookie_consent = document.getElementById('reset_cookie_consent');
    if ($reset_cookie_consent) {
      $reset_cookie_consent.addEventListener('click', MozConsentBanner.onClearClick);
    }
  }
}, { once: true });

// Global header
window.addEventListener('DOMContentLoaded', () => {
  /** @type {HTMLButtonElement} */
  const $openDrawerButton = document.querySelector('#open-menu-drawer');
  /** @type {HTMLButtonElement} */
  const $closeDrawerButton = document.querySelector('#close-menu-drawer');
  /** @type {HTMLDialogElement} */
  const $drawer = document.querySelector('#menu-drawer');
  /** @type {HTMLElement} */
  const $headerWrapper = document.querySelector('#header');
  /** @type {HTMLElement} */
  const $searchBoxOuter = document.querySelector('#header-search .searchbox-outer');
  /** @type {HTMLInputElement} */
  const $searchBox = document.querySelector('#quicksearch_top');
  /** @type {HTMLButtonElement} */
  const $showSearchBoxButton = document.querySelector('#show-searchbox');
  /** @type {HTMLElement} */
  const $searchBoxDropdown = document.querySelector('#header-search-dropdown');

  $openDrawerButton.addEventListener('click', () => {
    $drawer.inert = false;
    $drawer.showModal();
  });

  $closeDrawerButton.addEventListener('click', () => {
    $drawer.close();
    $drawer.inert = true;
  });

  $drawer.addEventListener('click', ({ clientX, clientY }) => {
    // Close the drawer when the backdrop is clicked
    if (document.elementFromPoint(clientX, clientY) === $drawer) {
      $drawer.close();
      $drawer.inert = true;
    }
  });

  $searchBox.addEventListener('focusin', () => {
    $headerWrapper.classList.add('searching');
  });

  $searchBoxOuter.addEventListener('focusout', () => {
    if (!$searchBoxOuter.matches(':focus-within')) {
      $searchBoxDropdown.style.display = 'none';
      $headerWrapper.classList.remove('searching');
    }
  });

  $showSearchBoxButton.addEventListener('click', () => {
    $headerWrapper.classList.add('searching');
    $searchBox.focus();

    // Show the dropdown
    window.requestAnimationFrame(() => {
      $searchBox.click();
    });
  });
}, { once: true });
