/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

window.addEventListener('DOMContentLoaded', () => {
  'use strict';

  const $meta = document.querySelector('meta[name="google-analytics"]');

  if (!$meta) {
    return;
  }

  const url = new URL(document.location);
  const params = url.searchParams;

  // Sanitize params
  params.delete('list_id');
  params.delete('token');

  // Activate Google Analytics
  window.ga=window.ga||function(){(ga.q=ga.q||[]).push(arguments)};ga.l=+new Date;
  ga('create', $meta.content, 'auto');
  ga('set', 'anonymizeIp', true);
  ga('set', 'location', url);
  ga('set', 'transport', 'beacon');
  // Custom Dimension: logged in (true) or out (false)
  ga('set', 'dimension1', !!BUGZILLA.user.login);
  // Track page view
  ga('send', 'pageview');
}, { once: true });
