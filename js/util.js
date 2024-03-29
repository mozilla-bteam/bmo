/* ***** BEGIN LICENSE BLOCK *****
 * Version: MPL 1.1
 *
 * The contents of this file are subject to the Mozilla Public License Version
 * 1.1 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
 * for the specific language governing rights and limitations under the
 * License.
 *
 * The Original Code is the Cross Platform JavaScript Utility Library.
 *
 * The Initial Developer of the Original Code is
 * Everything Solved.
 * Portions created by the Initial Developer are Copyright (C) 2007
 * the Initial Developer. All Rights Reserved.
 *
 * Contributor(s):
 *   Max Kanat-Alexander <mkanat@bugzilla.org>
 *   Christopher A. Aillon <christopher@aillon.com>
 *
 * ***** END LICENSE BLOCK ***** */

/**
 * Locate where an element is on the page, x-wise.
 *
 * @param  obj Element of which location to return.
 * @return     Current position of the element relative to the left of the
 *             page window. Measured in pixels.
 */
function bz_findPosX(obj)
{
    var curleft = 0;

    if (obj.offsetParent) {
        while (obj) {
            if (getComputedStyle(obj).position != 'relative')
                curleft += obj.offsetLeft;
            obj = obj.offsetParent;
        }
    }
    else if (obj.x) {
        curleft += obj.x;
    }

    return curleft;
}

/**
 * Locate where an element is on the page, y-wise.
 *
 * @param  obj Element of which location to return.
 * @return     Current position of the element relative to the top of the
 *             page window. Measured in pixels.
 */
function bz_findPosY(obj)
{
    var curtop = 0;

    if (obj.offsetParent) {
        while (obj) {
            if (getComputedStyle(obj).position != 'relative')
                curtop += obj.offsetTop;
            obj = obj.offsetParent;
        }
    }
    else if (obj.y) {
        curtop += obj.y;
    }

    return curtop;
}

/**
 * Get the full height of an element, even if it's larger than the browser
 * window.
 *
 * @param  fromObj Element of which height to return.
 * @return         Current height of the element. Measured in pixels.
 */
function bz_getFullHeight(fromObj)
{
    var scrollY;

    // All but Mac IE
    if (fromObj.scrollHeight > fromObj.offsetHeight) {
        scrollY = fromObj.scrollHeight;
    // Mac IE
    }  else {
        scrollY = fromObj.offsetHeight;
    }

    return scrollY;
}

/**
 * Get the full width of an element, even if it's larger than the browser
 * window.
 *
 * @param  fromObj Element of which width to return.
 * @return         Current width of the element. Measured in pixels.
 */
function bz_getFullWidth(fromObj)
{
    var scrollX;

    // All but Mac IE
    if (fromObj.scrollWidth > fromObj.offsetWidth) {
        scrollX = fromObj.scrollWidth;
    // Mac IE
    }  else {
        scrollX = fromObj.offsetWidth;
    }

    return scrollX;
}

/**
 * Causes a block to appear directly underneath another block,
 * overlaying anything below it.
 *
 * @param item   The block that you want to move.
 * @param parent The block that it goes on top of.
 * @return nothing
 */
function bz_overlayBelow(item, parent) {
    var elemY = bz_findPosY(parent);
    var elemX = bz_findPosX(parent);
    var elemH = parent.offsetHeight;

    item.style.position = 'absolute';
    item.style.left = elemX + "px";
    item.style.top = elemY + elemH + 1 + "px";
    item.style.zIndex = 999;
}

/**
 * Checks if a specified value is in the specified array.
 *
 * @param  aArray Array to search for the value.
 * @param  aValue Value to search from the array.
 * @return        Boolean; true if value is found in the array and false if not.
 */
function bz_isValueInArray(aArray, aValue)
{
  for (var run = 0, len = aArray.length ; run < len; run++) {
    if (aArray[run] == aValue) {
      return true;
    }
  }

  return false;
}

/**
 * Checks if a specified value is in the specified array by performing a
 * case-insensitive comparison.
 *
 * @param  aArray Array to search for the value.
 * @param  aValue Value to search from the array.
 * @return        Boolean; true if value is found in the array and false if not.
 */
function bz_isValueInArrayIgnoreCase(aArray, aValue)
{
  var re = new RegExp(aValue.replace(/([^A-Za-z0-9])/g, "\\$1"), 'i');
  for (var run = 0, len = aArray.length ; run < len; run++) {
    if (aArray[run].match(re)) {
      return true;
    }
  }

  return false;
}

/**
 * Create wanted options in a select form control.
 *
 * @param  aSelect        Select form control to manipulate.
 * @param  aValue         Value attribute of the new option element.
 * @param  aTextValue     Value of a text node appended to the new option
 *                        element.
 * @return                Created option element.
 */
function bz_createOptionInSelect(aSelect, aTextValue, aValue) {
  var myOption = new Option(aTextValue, aValue);
  aSelect.options[aSelect.length] = myOption;
  return myOption;
}

/**
 * Clears all options from a select form control.
 *
 * @param  aSelect    Select form control of which options to clear.
 */
function bz_clearOptions(aSelect) {

  var length = aSelect.options.length;

  for (var i = 0; i < length; i++) {
    aSelect.removeChild(aSelect.options[0]);
  }
}

/**
 * Takes an array and moves all the values to an select.
 *
 * @param aSelect         Select form control to populate. Will be cleared
 *                        before array values are created in it.
 * @param aArray          Array with values to populate select with.
 */
function bz_populateSelectFromArray(aSelect, aArray) {
  // Clear the field
  bz_clearOptions(aSelect);

  for (var i = 0; i < aArray.length; i++) {
    var item = aArray[i];
    bz_createOptionInSelect(aSelect, item[1], item[0]);
  }
}

/**
 * Returns all Option elements that are selected in a <select>,
 * as an array. Returns an empty array if nothing is selected.
 *
 * @param aSelect The select you want the selected values of.
 */
function bz_selectedOptions(aSelect) {
    // HTML 5
    if (aSelect.selectedOptions) {
        return aSelect.selectedOptions;
    }

    var start_at = aSelect.selectedIndex;
    if (start_at == -1) return [];
    var first_selected =  aSelect.options[start_at];
    if (!aSelect.multiple) return first_selected;
    // selectedIndex is specified as being the "first selected item",
    // so we can start from there.
    var selected = [first_selected];
    var options_length = aSelect.options.length;
    // We start after first_selected
    for (var i = start_at + 1; i < options_length; i++) {
        var this_option = aSelect.options[i];
        if (this_option.selected) selected.push(this_option);
    }
    return selected;
}

/**
 * Returns all Option elements that have the "selected" attribute, as an array.
 * Returns an empty array if nothing is selected.
 *
 * @param aSelect The select you want the pre-selected values of.
 */
function bz_preselectedOptions(aSelect) {
    var options = aSelect.options;
    var selected = new Array();
    for (var i = 0, l = options.length; i < l; i++) {
        var attributes = options[i].attributes;
        for (var j = 0, m = attributes.length; j < m; j++) {
            if (attributes[j].name == 'selected') {
                if (!aSelect.multiple) return options[i];
                selected.push(options[i]);
            }
        }
    }
    return selected;
}

/**
 * Tells you whether or not a particular value is selected in a select,
 * whether it's a multi-select or a single-select. The check is
 * case-sensitive.
 *
 * @param aSelect        The select you're checking.
 * @param aValue         The value that you want to know about.
 */
function bz_valueSelected(aSelect, aValue) {
    var options = aSelect.options;
    for (var i = 0; i < options.length; i++) {
        if (options[i].selected && options[i].value == aValue) {
            return true;
        }
    }
    return false;
}

/**
 * Tells you where (what index) in a <select> a particular option is.
 * Returns -1 if the value is not in the <select>
 *
 * @param aSelect       The select you're checking.
 * @param aValue        The value you want to know the index of.
 */
function bz_optionIndex(aSelect, aValue) {
    for (var i = 0; i < aSelect.options.length; i++) {
        if (aSelect.options[i].value == aValue) {
            return i;
        }
    }
    return -1;
}

/**
 * Used to fire an event programmatically.
 *
 * @param anElement      The element you want to fire the event of.
 * @param anEvent        The name of the event you want to fire,
 *                       without the word "on" in front of it.
 */
function bz_fireEvent(anElement, anEvent) {
    if (document.createEvent) {
        // DOM-compliant browser
        var evt = document.createEvent("HTMLEvents");
        evt.initEvent(anEvent, true, true);
        return !anElement.dispatchEvent(evt);
    } else {
        // IE
        var evt = document.createEventObject();
        return anElement.fireEvent('on' + anEvent, evt);
    }
}

/**
 * Adds a CSS class to an element if it doesn't have it. Removes the
 * CSS class from the element if the element does have the class.
 *
 * @param anElement  The element to toggle the class on
 * @param aClass     The name of the CSS class to toggle.
 */
function bz_toggleClass(anElement, aClass) {
    if (typeof anElement === 'string') {
        anElement = document.getElementById(anElement);
    }

    anElement?.classList.toggle(aClass);
}

/* Returns a string representation of a duration.
 *
 * @param ss   Duration in seconds
 * or
 * @param date Date object
 */
function timeAgo(param) {
    var ss = param.constructor === Date ? Math.round((new Date() - param) / 1000) : param;
    var mm = Math.round(ss / 60),
        hh = Math.round(mm / 60),
        dd = Math.round(hh / 24),
        mo = Math.round(dd / 30),
        yy = Math.round(mo / 12);
    if (ss < 10) return 'Just now';
    if (ss < 45) return ss + ' seconds ago';
    if (ss < 90) return '1 minute ago';
    if (mm < 45) return mm + ' minutes ago';
    if (mm < 90) return '1 hour ago';
    if (hh < 24) return hh + ' hours ago';
    if (hh < 36) return '1 day ago';
    if (dd < 30) return dd + ' days ago';
    if (dd < 45) return '1 month ago';
    if (mo < 12) return mo + ' months ago';
    if (mo < 18) return '1 year ago';
    return yy + ' years ago';
}

/**
 * Format the given date as Bugzilla’s standard date format.
 * @param {Date | string} date Date instance or parsable date string.
 * @returns {string} Formatted date, e.g. `2023-04-05 06:07 PST`.
 */
const formatDate = (date) => {
  /** @type {Intl.DateTimeFormatOptions} */
  const options = {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    timeZoneName: 'short',
  };

  const { year, month, day, hour, minute, timeZoneName } = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', { ...options, hour12: false })
      .formatToParts(new Date(date))
      .filter(({ type }) => type in options)
      .map(({ type, value }) => [type, type === 'hour' && value === '24' ? '00' : value]),
  );

  return `${year}-${month}-${day} ${hour}:${minute} ${timeZoneName}`;
};

/**
 * Format the given file size as human-readable format.
 * @param {number} size Numeric size.
 * @returns {string} Formatted size, e.g. `1.23 MB`.
 */
const formatFileSize = (size) => {
  if (size === 1) {
    return `${size} byte`;
  }

  if (size < 1024) {
    return `${size} bytes`;
  }

  if (size < 1024 * 1024) {
    return `${(size / 1024).toFixed(2)} KB`;
  }

  if (size < 1024 * 1024 * 1024) {
    return `${(size / (1024 * 1024)).toFixed(2)} MB`;
  }

  return `${(size / (1024 * 1024 * 1024)).toFixed(2)} GB`;
};

/**
 * Decode the given Base64 data.
 * @param {string} data Encoded data.
 * @returns {string} Decoded data.
 * @see https://developer.mozilla.org/en-US/docs/Glossary/Base64#the_unicode_problem
 */
const decodeBase64 = (data) =>
  new TextDecoder().decode(Uint8Array.from(atob(data), (m) => m.codePointAt(0)));

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

/**
 * Enable easier access to the Bugzilla REST API.
 * @hideconstructor
 * @see https://bmo.readthedocs.io/en/latest/api/
 */
Bugzilla.API = class API {
  /**
   * Initialize the request settings for `fetch()` or `XMLHttpRequest`.
   * @private
   * @param {String} endpoint See the {@link Bugzilla.API._fetch} method.
   * @param {String} [method='GET'] See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [params] See the {@link Bugzilla.API._fetch} method.
   * @returns {Request} Request settings including the complete URL, HTTP method, headers and body.
   */
  static _init(endpoint, method = 'GET', params = {}) {
    const url = new URL(`${BUGZILLA.config.basepath}rest/${endpoint}`, location.origin);
    const token = BUGZILLA.api_token;

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
    if (token) {
      url.searchParams.set('Bugzilla_api_token', token);
    }

    return new Request(url, {
      method,
      body: method !== 'GET' ? JSON.stringify(params) : null,
      credentials: 'same-origin',
      cache: 'no-cache',
    });
  }

  /**
   * Send a `fetch()` request to a Bugzilla REST API endpoint and return results.
   * @private
   * @param {String} endpoint URL path excluding the `/rest/` prefix; may also contain query parameters.
   * @param {Object} [options] Request options.
   * @param {String} [options.method='GET'] HTTP request method. POST, GET, PUT, etc.
   * @param {Object} [options.params] Request parameters. For a GET request, it will be sent as the URL query params.
   * The values will be automatically URL-encoded, so don't use `encodeURIComponent()` for each. For a non-GET request,
   * this will be part of the request body. The params can be included in `endpoint` if those are simple (no encoding
   * required) or if the request is not GET but URL query params are required.
   * @param {Object} [options.init] Extra options for the `fetch()` method.
   * @returns {Promise.<(Object|Array.<Object>|Error)>} Response data for a valid response, or an `Error` object for an
   * error returned from the REST API as well as any other exception including an aborted or failed HTTP request.
   * @see https://developer.mozilla.org/en-US/docs/Web/API/WindowOrWorkerGlobalScope/fetch
   */
  static async _fetch(endpoint, { method = 'GET', params = {}, init = {} } = {}) {
    const request = this._init(endpoint, method, params);

    if (!navigator.onLine) {
      return Promise.reject(new Bugzilla.Error({ name: 'OfflineError', message: 'You are currently offline.' }));
    }

    return new Promise((resolve, reject) => {
      const timer = window.setTimeout(() => {
        reject(new Bugzilla.Error({ name: 'TimeoutError', message: 'Request Timeout' }));
      }, 30000);

      fetch(request, init)
      .then(response => response.json())
      .then(result => {
        const { error, code, message } = result;

        if (error) {
          reject(new Bugzilla.Error({ name: 'APIError', code, message }));
        } else {
          resolve(result);
        }
      }).catch(({ name, code, message }) => {
        reject(new Bugzilla.Error({ name, code, detail: message }));
      });

      window.clearTimeout(timer);
    });
  }

  /**
   * Shorthand for a GET request with the {@link Bugzilla.API._fetch} method.
   * @param {String} endpoint See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [params] See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [init] See the {@link Bugzilla.API._fetch} method.
   * @returns {Promise.<(Object|Array.<Object>|Error)>} See the {@link Bugzilla.API._fetch} method.
   */
  static async get(endpoint, params = {}, init = {}) {
    return this._fetch(endpoint, { method: 'GET', params, init });
  }

  /**
   * Shorthand for a POST request with the {@link Bugzilla.API._fetch} method.
   * @param {String} endpoint See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [params] See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [init] See the {@link Bugzilla.API._fetch} method.
   * @returns {Promise.<(Object|Array.<Object>|Error)>} See the {@link Bugzilla.API._fetch} method.
   */
  static async post(endpoint, params = {}, init = {}) {
    return this._fetch(endpoint, { method: 'POST', params, init });
  }

  /**
   * Shorthand for a PUT request with the {@link Bugzilla.API._fetch} method.
   * @param {String} endpoint See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [params] See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [init] See the {@link Bugzilla.API._fetch} method.
   * @returns {Promise.<(Object|Array.<Object>|Error)>} See the {@link Bugzilla.API._fetch} method.
   */
  static async put(endpoint, params = {}, init = {}) {
    return this._fetch(endpoint, { method: 'PUT', params, init });
  }

  /**
   * Shorthand for a PATCH request with the {@link Bugzilla.API._fetch} method.
   * @param {String} endpoint See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [params] See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [init] See the {@link Bugzilla.API._fetch} method.
   * @returns {Promise.<(Object|Array.<Object>|Error)>} See the {@link Bugzilla.API._fetch} method.
   */
  static async patch(endpoint, params = {}, init = {}) {
    return this._fetch(endpoint, { method: 'PATCH', params, init });
  }

  /**
   * Shorthand for a DELETE request with the {@link Bugzilla.API._fetch} method.
   * @param {String} endpoint See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [params] See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [init] See the {@link Bugzilla.API._fetch} method.
   * @returns {Promise.<(Object|Array.<Object>|Error)>} See the {@link Bugzilla.API._fetch} method.
   */
  static async delete(endpoint, params = {}, init = {}) {
    return this._fetch(endpoint, { method: 'DELETE', params, init });
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
   * control than `fetch()`, particularly to upload a file while monitoring the progress.
   * @param {String} endpoint See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [options] Request options.
   * @param {String} [options.method='GET'] See the {@link Bugzilla.API._fetch} method.
   * @param {Object} [options.params] See the {@link Bugzilla.API._fetch} method.
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

/**
 * A simple Web Storage API wrapper handling JSON parse/stringify.
 */
Bugzilla.Storage = class LocalStorage {
  /**
   * Get a value.
   * @param {string} key A storage key.
   * @param {any} [fallback] Whether to return `{}` instead of `null` when the value is unavailable.
   * @returns {object | null} A storage value.
   */
  static get(key, fallback = false) {
    const cache = window.localStorage.getItem(key);
    const fallbackValue = fallback ? {} : null;

    if (cache === null) {
      return fallbackValue;
    }

    try {
      return JSON.parse(cache);
    } catch {
      return fallbackValue;
    }
  }

  /**
   * Set a value.
   * @param {string} key A storage key.
   * @param {object} value A storage value.
   */
  static set(key, value) {
    window.localStorage.setItem(key, JSON.stringify(value));
  }

  /**
   * Merge an existing value with a new value.
   * @param {string} key A storage key.
   * @param {object} value A storage value.
   */
  static update(key, value) {
    this.set(key, { ...this.get(key, true), ...value });
  }

  /**
   * Delete a value.
   * @param {string} key A storage key.
   */
  static delete(key) {
    window.localStorage.removeItem(key);
  }

  /**
   * Clear the storage.
   */
  static clear() {
    window.localStorage.clear();
  }
}
