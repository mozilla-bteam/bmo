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

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

/**
 * Enable easier access to the Bugzilla REST API.
 * @hideconstructor
 * @see https://bugzilla.readthedocs.io/en/latest/api/
 */
Bugzilla.API = class API {
  /**
   * Initialize the request settings for `fetch()` or `XMLHttpRequest`.
   * @private
   * @param {String} endpoint See the {@link Bugzilla.API.fetch} method.
   * @param {String} [method='GET'] See the {@link Bugzilla.API.fetch} method.
   * @param {Object} [params={}] See the {@link Bugzilla.API.fetch} method.
   * @returns {Request} Request settings including the complete URL, HTTP method, headers and body.
   */
  static _init(endpoint, method = 'GET', params = {}) {
    const url = new URL(`${BUGZILLA.config.basepath}rest/${endpoint}`, location.origin);

    if (method === 'GET') {
      for (const [key, value] of Object.entries(params)) {
        if (Array.isArray(value)) {
          if (['include_fields', 'exclude_fields'].includes(key)) {
            url.searchParams.set(key, value.join(','));
          } else {
            // Because the REST API v1 doesn't support comma-separated values for certain params, array values have to
            // be appended as duplicated params, so the query string will look like `attachment_ids=1&attachment_ids=2`
            // instead of `attachment_ids=1,2`.
            value.forEach(val => url.searchParams.append(key, val));
          }
        } else {
          url.searchParams.set(key, value);
        }
      }
    }

    /** @todo Remove this once Bug 1477163 is solved */
    url.searchParams.set('Bugzilla_api_token', BUGZILLA.api_token);

    return new Request(url, {
      method,
      body: method !== 'GET' ? JSON.stringify(params) : null,
      credentials: 'same-origin',
      cache: 'no-cache',
    });
  }

  /**
   * Send a `fetch()` request to a Bugzilla REST API endpoint and return results.
   * @param {String} endpoint URL path excluding the `/rest/` prefix; may also contain query parameters.
   * @param {Object} [options] Request options.
   * @param {String} [options.method='GET'] HTTP request method. POST, GET, PUT, etc.
   * @param {Object} [options.params={}] Request parameters. For a GET request, it will be sent as the URL query params.
   * The values will be automatically URL-encoded, so don't use `encodeURIComponent()` for each. For a non-GET request,
   * this will be part of the request body. The params can be included in `endpoint` if those are simple (no encoding
   * required) or if the request is not GET but URL query params are required.
   * @returns {Promise.<(Object|Array.<Object>|Error)>} Response data for a valid response, or an `Error` object for an
   * error returned from the REST API as well as any other exception including an aborted or failed HTTP request.
   */
  static async fetch(endpoint, { method = 'GET', params = {} } = {}) {
    const request = this._init(endpoint, method, params);

    if (!navigator.onLine) {
      return Promise.reject(new Bugzilla.Error({ name: 'OfflineError', message: 'You are currently offline.' }));
    }

    return new Promise(async (resolve, reject) => {
      const timer = window.setTimeout(() => {
        reject(new Bugzilla.Error({ name: 'TimeoutError', message: 'Request Timeout' }));
      }, 30000);

      try {
        /** @throws {AbortError} */
        const response = await fetch(request);
        /** @throws {SyntaxError} */
        const result = await response.json();
        const { error, code, message } = result;

        if (!response.ok || error) {
          reject(new Bugzilla.Error({ name: 'APIError', code, message }));
        } else {
          resolve(result);
        }
      } catch ({ name, code, message }) {
        reject(new Bugzilla.Error({ name, code, detail: message }));
      }

      window.clearTimeout(timer);
    });
  }

  /**
   * Shorthand for a GET request with the {@link Bugzilla.API.fetch} method.
   * @param {String} endpoint See the {@link Bugzilla.API.fetch} method.
   * @param {Object} [params={}] See the {@link Bugzilla.API.fetch} method.
   * @returns {Promise.<(Object|Array.<Object>|Error)>} See the {@link Bugzilla.API.fetch} method.
   */
  static async get(endpoint, params = {}) {
    return this.fetch(endpoint, { method: 'GET', params });
  }

  /**
   * Shorthand for a POST request with the {@link Bugzilla.API.fetch} method.
   * @param {String} endpoint See the {@link Bugzilla.API.fetch} method.
   * @param {Object} [params={}] See the {@link Bugzilla.API.fetch} method.
   * @returns {Promise.<(Object|Array.<Object>|Error)>} See the {@link Bugzilla.API.fetch} method.
   */
  static async post(endpoint, params = {}) {
    return this.fetch(endpoint, { method: 'POST', params });
  }

  /**
   * Shorthand for a PUT request with the {@link Bugzilla.API.fetch} method.
   * @param {String} endpoint See the {@link Bugzilla.API.fetch} method.
   * @param {Object} [params={}] See the {@link Bugzilla.API.fetch} method.
   * @returns {Promise.<(Object|Array.<Object>|Error)>} See the {@link Bugzilla.API.fetch} method.
   */
  static async put(endpoint, params = {}) {
    return this.fetch(endpoint, { method: 'PUT', params });
  }

  /**
   * Shorthand for a PATCH request with the {@link Bugzilla.API.fetch} method.
   * @param {String} endpoint See the {@link Bugzilla.API.fetch} method.
   * @param {Object} [params={}] See the {@link Bugzilla.API.fetch} method.
   * @returns {Promise.<(Object|Array.<Object>|Error)>} See the {@link Bugzilla.API.fetch} method.
   */
  static async patch(endpoint, params = {}) {
    return this.fetch(endpoint, { method: 'PATCH', params });
  }

  /**
   * Shorthand for a DELETE request with the {@link Bugzilla.API.fetch} method.
   * @param {String} endpoint See the {@link Bugzilla.API.fetch} method.
   * @param {Object} [params={}] See the {@link Bugzilla.API.fetch} method.
   * @returns {Promise.<(Object|Array.<Object>|Error)>} See the {@link Bugzilla.API.fetch} method.
   */
  static async delete(endpoint, params = {}) {
    return this.fetch(endpoint, { method: 'DELETE', params });
  }

  /**
   * Success callback function for the {@link Bugzilla.API.xhr} method.
   * @callback Bugzilla.API~resolve
   * @param {Object|Array.<Object>} data Response data for a valid response.
   */

  /**
   * Error callback function for the {@link Bugzilla.API.xhr} method.
   * @callback Bugzilla.API~reject
   * @param {Error} error `Error` object providing a reason. See the {@link Bugzilla.Error} for details.
   */

  /**
   * Make an `XMLHttpRequest` to a Bugzilla REST API endpoint and return results. This is useful when you need more
   * control than `fetch()`, for example, to upload a file while monitoring the progress or to abort the request in a
   * particular condition.
   * @param {String} endpoint See the {@link Bugzilla.API.fetch} method.
   * @param {Object} [options] Request options.
   * @param {String} [options.method='GET'] See the {@link Bugzilla.API.fetch} method.
   * @param {Object} [options.params={}] See the {@link Bugzilla.API.fetch} method.
   * @param {Bugzilla.API~resolve} [options.resolve] Callback function for a valid response.
   * @param {Bugzilla.API~reject} [options.reject] Callback function for an error returned from the REST API as well as
   * any other exception including an aborted or failed HTTP request.
   * @param {Object.<String, Function>} [options.download] Raw event listeners for download; the key is an event type
   * such as `load` or `error`, the value is an event listener.
   * @param {Object.<String, Function>} [options.upload] Raw event listeners for upload; the key is an event type such
   * as `progress` or `error`, the value is an event listener.
   * @returns {XMLHttpRequest} Request.
   * @see https://developer.mozilla.org/en-US/docs/Web/API/XMLHttpRequest/Using_XMLHttpRequest#Monitoring_progress
   */
  static xhr(endpoint, { method = 'GET', params = {}, resolve, reject, download, upload } = {}) {
    const xhr = new XMLHttpRequest();
    const { url, headers, body } = this._init(endpoint, method, params);

    resolve = typeof resolve === 'function' ? resolve : () => {};
    reject = typeof reject === 'function' ? reject : () => {};

    if (!navigator.onLine) {
      reject(new Bugzilla.Error({ name: 'OfflineError', message: 'You are currently offline.' }));

      return xhr;
    }

    xhr.addEventListener('load', () => {
      try {
        /** @throws {SyntaxError} */
        const result = JSON.parse(xhr.responseText);
        const { error, code, message } = result;

        if (parseInt(xhr.status / 100) !== 2 || error) {
          reject(new Bugzilla.Error({ name: 'APIError', code, message }));
        } else {
          resolve(result);
        }
      } catch ({ name, code, message }) {
        reject(new Bugzilla.Error({ name, code, detail: message }));
      }
    });

    xhr.addEventListener('abort', () => {
      reject(new Bugzilla.Error({ name: 'AbortError' }));
    });

    xhr.addEventListener('error', () => {
      reject(new Bugzilla.Error({ name: 'NetworkError' }));
    });

    xhr.addEventListener('timeout', () => {
      reject(new Bugzilla.Error({ name: 'TimeoutError', message: 'Request Timeout' }));
    });

    for (const [type, handler] of Object.entries(download || {})) {
      xhr.addEventListener(type, event => handler(event));
    }

    for (const [type, handler] of Object.entries(upload || {})) {
      xhr.upload.addEventListener(type, event => handler(event));
    }

    xhr.open(method, url);

    for (const [key, value] of headers) {
      xhr.setRequestHeader(key, value);
    }

    // Set timeout in 30 seconds given some large results
    xhr.timeout = 30000;

    xhr.send(body);

    return xhr;
  }
};

/**
 * Extend the generic `Error` class so it can contain a custom name and other data if needed. This allows to gracefully
 * handle an error from either the REST API or the browser.
 */
Bugzilla.Error = class CustomError extends Error {
  /**
   * Initialize the `CustomError` object.
   * @param {Object} [options] Error options.
   * @param {String} [options.name='Error'] Distinguishable error name that can be taken from an original `DOMException`
   * object if any, e.g. `AbortError` or `SyntaxError`.
   * @param {String} [options.message='Unexpected Error'] Localizable, user-friendly message probably from the REST API.
   * @param {Number} [options.code=0] Custom error code from the REST API or `DOMException` code.
   * @param {String} [options.detail] Detailed, technical message probably from an original `DOMException` that end
   * users don't have to see.
   */
  constructor({ name = 'Error', message = 'Unexpected Error', code = 0, detail } = {}) {
    super(message);
    this.name = name;
    this.code = code;
    this.detail = detail;

    console.error(this.toString());
  }

  /**
   * Define the string representation of the error object.
   * @override
   * @returns {String} Custom string representation.
   */
  toString() {
    return `${this.name}: "${this.message}" (code: ${this.code}${this.detail ? `, detail: ${this.detail}` : ''})`;
  }
};

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
    Cookies.set('LANG', value, {
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
 * If the current URL contains a hash like `#c10`, adjust the scroll position to
 * make some room above the focused element.
 */
const adjust_scroll_onload = () => {
    if (location.hash) {
        const $target = document.querySelector(CSS.escape(location.hash));

        if ($target) {
            window.setTimeout(() => scroll_element_into_view($target), 50);
        }
    }
}

/**
 * Bring an element into the visible area of the browser window. Unlike the
 * native `Element.scrollIntoView()` function, this adds some extra room above
 * the target element. Smooth scroll can be done using CSS.
 * @param {Element} $target - An element to be brought.
 * @param {Function} [complete] - An optional callback function to be executed
 *  once the scroll is complete.
 */
const scroll_element_into_view = ($target, complete) => {
    let top = 0;
    let $element = $target;

    // Traverse up in the DOM tree to the scroll container of the
    // focused element, either `<main>` or `<div role="feed">`.
    do {
        top += ($element.offsetTop || 0);
        $element = $element.offsetParent;
    } while ($element && !$element.matches('main, [role="feed"]'))

    if (!$element) {
        return;
    }

    if (typeof complete === 'function') {
        const callback = () => {
            $element.removeEventListener('scroll', listener);
            complete();
        };

        // Emulate the `scrollend` event
        const listener = () => {
            window.clearTimeout(timer);
            timer = window.setTimeout(callback, 100);
        };

        // Make sure the callback is always fired even if no scroll happened
        let timer = window.setTimeout(callback, 100);

        $element.addEventListener('scroll', listener);
    }

    $element.scrollTop = top - 20;
}

window.addEventListener('DOMContentLoaded', focus_main_content, { once: true });
window.addEventListener('load', detect_blocked_gravatars, { once: true });
window.addEventListener('load', adjust_scroll_onload, { once: true });
window.addEventListener('hashchange', adjust_scroll_onload);

window.addEventListener('DOMContentLoaded', () => {
  const announcement = document.getElementById('new_announcement');
  if (announcement) {
    const hide_announcement = () => {
      const checksum = announcement.dataset.checksum;
      const url = `${BUGZILLA.config.basepath}announcement/hide/${checksum}`;
      fetch(url, { method: "POST" }).then(
        response => announcement.style.display = "none"
      );
      localStorage.setItem("announcement_checksum", checksum);
    }
    announcement.addEventListener('click', hide_announcement);
    window.addEventListener('visibilitychange', () => {
      if (!window.hidden) {
        const hidden_checksum = localStorage.getItem("announcement_checksum");
        if (hidden_checksum && hidden_checksum == announcement.dataset.checksum) {
          announcement.style.display = "none";
        }
      }
    });
  }
}, { once: true });
