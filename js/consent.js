/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

var MozConsentBanner = {};
var EVENT_NAME_STATUS = 'mozConsentStatus';
var EVENT_NAME_OPEN = 'mozConsentOpen';
var EVENT_NAME_CLOSE = 'mozConsentClose';
var COOKIE_ID = 'moz-consent-pref';
var COOKIE_EXPIRY_DAYS = 182; // 6 months
var MSG_OPTIONS_ERROR_DISABLED = 'verifyOptions(): cookies are disabled.';
var MSG_OPTIONS_ERROR_EXPIRY = 'verifyOptions(): options.cookieExpiryDays not set.';
var MSG_OPTIONS_ERROR_HELPER = 'verifyOptions(): options.helper not set.';
var MSG_OPTIONS_ERROR_OPT_OUT = 'verifyOptions(): options.optOut not set.';
var MSG_OPTIONS_VALID = 'verifyOptions(): success.';
var options;

/**
 * Sets cookie indicating consent choice.
 * @param {Object} data - consent settings.
 */
MozConsentBanner.setConsentCookie = function (data) {
  try {
    var date = new Date();
    date.setDate(date.getDate() + options.cookieExpiryDays);
    var expires = date.toUTCString();
    options.helper.setItem(options.cookieID, JSON.stringify(data), expires, '/', options.cookieDomain, false, 'lax');
    return true;
  } catch (e) {
    return false;
  }
};

/**
 * Get consent cookie value if set.
 * @returns {Boolean}
 */
MozConsentBanner.getConsentCookie = function () {
  try {
    return options.helper.hasItem(options.cookieID) && JSON.parse(options.helper.getItem(options.cookieID));
  } catch (e) {
    return false;
  }
};

/**
 * Returns the domain to set for the consent cookie. When in production
 * we want to specify '.mozilla.org' instead of 'www.mozilla.org',
 * so that multiple Mozilla sub domains can use the same consent cookie.
 * @returns {domain} string or null.
 */
MozConsentBanner.getHostName = function (hostname) {
  var url = typeof hostname === 'string' ? hostname : window.location.hostname;
  var domain = null;
  if (url.indexOf('.allizom.org') !== -1) {
    domain = '.allizom.org';
  }
  if (url.indexOf('.mozilla.org') !== -1) {
    domain = '.mozilla.org';
  }
  return domain;
};

/**
 * Helper for dispatching a custom event with a
 * given name and data payload.
 * @param {Object} eventName
 * @param {Object} eventData
 */
MozConsentBanner.dispatchEvent = function (eventName, eventData) {
  if (typeof window.CustomEvent === 'function') {
    // Modern browsers
    window.dispatchEvent(new CustomEvent(eventName, {
      detail: eventData
    }));
  } else if (typeof document.createEvent === 'function') {
    // Internet Explorer 10
    var customEvent = document.createEvent('CustomEvent');
    customEvent.initCustomEvent(eventName, false, false, eventData);
    window.dispatchEvent(customEvent);
  } else if (typeof document.createEventObject === 'function') {
    // Internet Explorer 9
    var customEventObj = document.createEventObject();
    customEventObj.type = eventName;
    customEventObj.bubbles = false;
    customEventObj.cancelable = false;
    customEventObj.detail = eventData; // Optional data for the event
    window.fireEvent('on' + customEventObj.type, customEventObj);
  }
};

/**
 * Event handler for accepting cookies.
 */
MozConsentBanner.onAcceptClick = function () {
  var preferences = {
    analytics: true,
    preference: true
  };
  MozConsentBanner.setConsentCookie(preferences);
  MozConsentBanner.dispatchEvent(EVENT_NAME_STATUS, preferences);
  MozConsentBanner.dispatchEvent(EVENT_NAME_CLOSE, {});
};

/**
 * Event handler for rejecting cookies.
 */
MozConsentBanner.onRejectClick = function () {
  var preferences = {
    analytics: false,
    preference: false
  };
  MozConsentBanner.setConsentCookie(preferences);
  MozConsentBanner.dispatchEvent(EVENT_NAME_STATUS, preferences);
  MozConsentBanner.dispatchEvent(EVENT_NAME_CLOSE, {});
};

/**
 * Validates BannerOptions configuration object.
 * @param {BannerOptions} object containing one or more properties.
 * @returns {String} message to indicate either success or error.
 */
MozConsentBanner.verifyOptions = function (options) {
  // Verify cookie expiry has been set.
  if (typeof options.cookieExpiryDays !== 'number') {
    return MSG_OPTIONS_ERROR_EXPIRY;
  }

  // Verify cookie helper dependency is defined.
  if (!options.helper || typeof options.helper.setItem !== 'function') {
    return MSG_OPTIONS_ERROR_HELPER;
  }

  // Verify that optOut flag is set.
  if (typeof options.optOut !== 'boolean') {
    return MSG_OPTIONS_ERROR_OPT_OUT;
  }

  // Verify that cookies are enabled in the browser.
  if (!options.helper.enabled()) {
    return MSG_OPTIONS_ERROR_DISABLED;
  }
  return MSG_OPTIONS_VALID;
};

/**
 * MozConsentBanner.init() configuration options:
 * @typedef {Object} BannerOptions
 * @property {string} cookieDomain - Sets a consent cookie for a specific host name.
 * @property {number} cookieExpiryDays - Consent cookie expiry by number of days.
 * @property {string} cookieID - Consent cookie identifier.
 * @property {object} helper (required) - reference to @mozmeao/cookie-helper peer dependency.
 * @property {object} optOut - Sets the banner to be opt-out instead of the default opt-in.
 */

/**
 * Initializes cookie banner and binds events.
 * @param {BannerOptions} object containing one or more properties.
 * @returns {Boolean} to indicate if initialization succeeded.
 */
MozConsentBanner.init = function (config) {
  /**
   * Default configuration options that can be overridden via init().
   */
  var defaults = {
    cookieDomain: null,
    cookieExpiryDays: COOKIE_EXPIRY_DAYS,
    cookieID: COOKIE_ID,
    optOut: false,
    eventName: EVENT_NAME_STATUS,
    helper: null
  };
  for (var opt in config) {
    if (Object.prototype.hasOwnProperty.call(config, opt)) {
      defaults[opt] = config[opt];
    }
  }
  options = defaults;

  /**
   * If domain for consent cookie has not be supplied via config,
   * set it via getHostName()
   */
  if (!options.cookieDomain) {
    options.cookieDomain = MozConsentBanner.getHostName();
  }

  /**
   * Validate options object before trying to show the banner.
   */
  var configValidationMsg = MozConsentBanner.verifyOptions(options);
  if (configValidationMsg !== MSG_OPTIONS_VALID) {
    if (window.console && window.console.error) {
      console.error(configValidationMsg); // eslint-disable-line no-console
    }
    return false;
  }

  /**
   * If cookie exists and consent has previously been given,
   * despatch consent event. Otherwise show the banner.
   */
  var consent = MozConsentBanner.getConsentCookie();
  if (consent) {
    MozConsentBanner.dispatchEvent(EVENT_NAME_STATUS, consent);
  } else {
    MozConsentBanner.dispatchEvent(EVENT_NAME_OPEN, {});

    /**
     * If the banner is opt out, despatch event to indicate
     * cookies and analytics are OK to load.
     */
    if (options.optOut) {
      MozConsentBanner.dispatchEvent(EVENT_NAME_STATUS, {
        preference: true,
        analytics: true
      });
    }
  }
  return true;
};
