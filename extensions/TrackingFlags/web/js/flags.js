/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

$(function() {
  'use strict';

   // tracking flags
   $('.tracking-flags select')
     .change(function(event) {
       tracking_flag_change(event.target);
     });

  function tracking_flag_change(e) {
    var value = e.value;
    var prefill;
    if (TrackingFlags.comments[e.name])
      prefill = TrackingFlags.comments[e.name][e.value];
    if (!prefill) {
      var cr = document.getElementById('cr_' + e.id);
      if (cr)
        cr.parentElement.removeChild(cr);
      return;
    }
    if (!document.getElementById('cr_' + e.id)) {
      // create "comment required"
      var span = document.createElement('span');
      span.id = 'cr_' + e.id;
      span.appendChild(document.createTextNode(' ('));
      var a = document.createElement('a');
      a.appendChild(document.createTextNode('comment required'));
      a.href = '#';
      a.onclick = function(event) {
        event.preventDefault();
        var c = document.getElementById('comment');
        c.focus();
        c.select();
        var btn = document.getElementById('add_comment') || document.getElementById('add-comment');
        if (btn)
          btn.scrollIntoView();
      };
      span.appendChild(a);
      span.appendChild(document.createTextNode(')'));
      e.parentNode.appendChild(span);
    }
    // prefill comment
    var commentEl = document.getElementById('comment');
    if (!commentEl)
      return;
    var value = commentEl.value;
    if (value == prefill)
      return;
    if (value == '') {
      commentEl.value = prefill;
      a.innerHTML = 'comment required';
    } else {
      commentEl.value = prefill + "\n\n" + value;
      a.innerHTML = 'comment updated';
    }
  }
});

