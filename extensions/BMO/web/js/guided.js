/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
  'use strict';

  $('a[href="#firefox"]').click(function (e) {
      $(".submenu:visible:not(#firefox_menu)").hide();
      $("#firefox_menu:hidden").slideDown("slow");
  });

  $('a[href="#firefox_os"]').click(function (e) {
      $(".submenu:visible:not(#firefox_os_menu)").hide();
      $("#firefox_os_menu:hidden").slideDown("slow");
  });

  $('a[href="#other"]').click(function (e) {
    $(".submenu:visible:not(#other_menu)").hide();
    $("#other_menu:hidden").slideDown("slow");
  });

  $('a[href="#service"]').click(function (e) {
    $(".submenu:visible:not(#services_menu)").hide();
    $("#services_menu:hidden").slideDown("slow");
  });

  $('a[href="#end_user_site_compat"]').click(function (e) {
    $(".subsubmenu:visible:not(#end_user_site_compat_menu)").hide();
    $("#end_user_site_compat_menu").slideDown("slow");
  });

  $('a[href="#end_user_site_compat"]').click(function (e) {
    $(".subsubmenu:visible:not(#end_user_site_compat_menu)").hide();
    $("#end_user_site_compat_menu").slideDown("slow");
  });

  $('a[href="#webdev_bug"]').click(function (e) {
    $(".subsubmenu:visible:not(#webdev_bug_menu)").hide();
    $("#webdev_bug_menu").slideDown("slow");
  });
});
