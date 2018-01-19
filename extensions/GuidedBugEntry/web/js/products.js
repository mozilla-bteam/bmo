/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

/* Product-specifc configuration for guided bug entry
 *
 * related: array of product names which will also be searched for duplicates
 * version: function which returns a version (eg. detected from UserAgent)
 * support: string which is displayed at the top of the duplicates page
 * secgroup: the group to place confidential bugs into
 * defaultComponent: the default compoent to select.  Defaults to 'General'
 * noComponentSelection: when true, the default component will always be
 *     used.  Defaults to 'false';
 * detectPlatform: when true the platform and op_sys will be set from the
 *     browser's user agent.  when false, these will be set to All
 */

var products = {
  "addons.mozilla.org": {
    l10n: true
  },

  "Firefox": {
    related: [ "Core", "Toolkit" ],
    version: function() {
      var re = /Firefox\/(\d+)\.(\d+)/i;
      var match = re.exec(navigator.userAgent);
      if (match) {
        var maj = match[1];
        var min = match[2];
        if (maj * 1 >= 5) {
          return maj + " Branch";
        } else {
          return maj + "." + min + " Branch";
        }
      } else {
        return false;
      }
    },
    defaultComponent: "Untriaged",
    noComponentSelection: true,
    detectPlatform: true,
    l10n: true,
    support:
      'If you are new to Firefox or Bugzilla, please consider checking ' +
      '<a href="https://support.mozilla.org/">' +
      '<img src="extensions/GuidedBugEntry/web/images/sumo.png" width="16" height="16" align="absmiddle">' +
      ' <b>Firefox Help</b></a> instead of creating a bug.'
  },

  "Firefox for Android": {
    related: [ "Core", "Toolkit" ],
    detectPlatform: true,
    l10n: true,
    support:
      'If you are new to Firefox or Bugzilla, please consider checking ' +
      '<a href="https://support.mozilla.org/">' +
      '<img src="extensions/GuidedBugEntry/web/images/sumo.png" width="16" height="16" align="absmiddle">' +
      ' <b>Firefox Help</b></a> instead of creating a bug.'
  },

  "SeaMonkey": {
    related: [ "Core", "Toolkit", "MailNews Core" ],
    detectPlatform: true,
    l10n: true,
    version: function() {
      var re = /SeaMonkey\/(\d+)\.(\d+)/i;
      var match = re.exec(navigator.userAgent);
      if (match) {
        var maj = match[1];
        var min = match[2];
        return "SeaMonkey " + maj + "." + min + " Branch";
      } else {
        return false;
      }
    }
  },

  "Calendar": {
    l10n: true
  },

  "Camino": {
    related: [ "Core", "Toolkit" ],
    detectPlatform: true
  },

  "Core": {
    detectPlatform: true
  },

  "Thunderbird": {
    related: [ "Core", "Toolkit", "MailNews Core" ],
    detectPlatform: true,
    l10n: true,
    defaultComponent: "Untriaged",
    componentFilter : function(components) {
        var index = -1;
        for (var i = 0, l = components.length; i < l; i++) {
            if (components[i].name == 'General') {
                index = i;
                break;
            }
        }
        if (index != -1) {
            components.splice(index, 1);
        }
        return components;
    }
  },

  "Marketplace": {
    l10n: true
  },

  "Penelope": {
    related: [ "Core", "Toolkit", "MailNews Core" ]
  },

  "Bugzilla": {
    support:
      'Please use <a href="https://landfill.bugzilla.org/">Bugzilla Landfill</a> to file "test bugs".'
  },

  "bugzilla.mozilla.org": {
    related: [ "Bugzilla" ],
    support:
      'Please use <a href="https://landfill.bugzilla.org/">Bugzilla Landfill</a> to file "test bugs".'
  }
};
