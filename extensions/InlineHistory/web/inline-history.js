/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

var inline_history = {
  _ccDivs: null,
  _hasAttachmentFlags: false,
  _hasBugFlags: false,

  init: function() {
    Dom = YAHOO.util.Dom;

    var reDuplicate = /^\*\*\* \S+ \d+ has been marked as a duplicate of this/;
    var reBugId = /show_bug\.cgi\?id=(\d+)/;
    var reHours = /Additional hours worked: \d+\.\d+/;

    var comments = Dom.getElementsByClassName("bz_comment", 'div', 'comments');
    for (var i = 1, il = comments.length; i < il; i++) {
      // remove 'has been marked as a duplicate of this bug' comments
      var textDiv = Dom.getElementsByClassName('bz_comment_text', 'pre', comments[i]);
      if (textDiv) {
        var match = reDuplicate.exec(textDiv[0].textContent || textDiv[0].innerText);
        if (match) {
          // grab the comment and bug number from the element
          var comment = comments[i];
          var number = comment.id.substr(1);
          var time = this.trim(Dom.getElementsByClassName('bz_comment_time', 'span', comment)[0].innerHTML);
          var dupeId = 0;
          match = reBugId.exec(Dom.get('comment_text_' + number).innerHTML);
          if (match)
            dupeId = match[1];
          // remove the element
          comment.parentNode.removeChild(comment);
          comments[i] = false;
          // update the html for the history item to include the comment number
          if (dupeId == 0)
            continue;
          for (var j = 0, jl = ih_activity.length; j < jl; j++) {
            var item = ih_activity[j];
            if (item[5] == dupeId && item[1] == time) {
              // insert comment number and link into the header
              item[3] = item[3].substr(0, item[3].length - 6) // remove trailing </div>
                // add comment number
                + '<span class="bz_comment_number" id="c' + number + '">'
                + '<a href="#c' + number + '">Comment ' + number + '</a>'
                + '</span>'
                + '</div>';
              break;
            }
          }
        }
      }
      if (!comments[i])
        continue;

      // remove 'Additional hours worked: ' comments
      var commentNodes = comments[i].childNodes;
      for (var j = 0, jl = commentNodes.length; j < jl; j++) {
        if (reHours.exec(commentNodes[j].textContent)) {
            comments[i].removeChild(commentNodes[j]);
            // Remove the <br> before it
            comments[i].removeChild(commentNodes[j-1]);
            break;
        }
      }
    }

    // remove deleted comments
    for (var i = 0; i < comments.length; i++) {
        if (!comments[i]) {
            comments.splice(i, 1);
            i--;
        }
    }

    // ensure new items are placed immediately after the last comment
    if (!comments.length) return;
    var lastCommentDiv = comments[comments.length - 1];

    // insert activity into the correct location
    var commentTimes = Dom.getElementsByClassName('bz_comment_time', 'span', 'comments');
    for (var i = 0, il = ih_activity.length; i < il; i++) {
      var item = ih_activity[i];
      // item[0] : who
      // item[1] : when
      // item[2] : change html
      // item[3] : header html
      // item[4] : bool; cc-only
      // item[5] : int; dupe bug id (or 0)
      // item[6] : bool; is flag
      var user = item[0];
      var time = item[1];

      var reachedEnd = false;
      var start_index = (ih_activity_sort_order == 'newest_to_oldest_desc_first' && commentTimes.length > 1) ? 1 : 0;
      for (var j = start_index, jl = commentTimes.length; j < jl; j++) {
        var commentHead = commentTimes[j].parentNode;
        var mainUser = Dom.getElementsByClassName('email', 'a', commentHead)[0].href.substr(7);
        var text = commentTimes[j].textContent || commentTimes[j].innerText;
        var mainTime = this.trim(text);

        if (ih_activity_sort_order == 'oldest_to_newest' ? time > mainTime : time < mainTime) {
          if (j < commentTimes.length - 1) {
            continue;
          } else {
            reachedEnd = true;
          }
        }

        var inline = (mainUser == user && time == mainTime);
        var currentDiv = document.createElement("div");

        // place ih_cc class on parent container if it's the only child
        var containerClass = '';
        if (item[4]) {
          item[2] = item[2].replace('"ih_cc"', '""');
          containerClass = 'ih_cc';
        }

        if (inline) {
          // assume that the change was made by the same user
          commentHead.parentNode.appendChild(currentDiv);
          currentDiv.innerHTML = item[2];
          Dom.addClass(currentDiv, 'ih_inlinehistory');
          Dom.addClass(currentDiv, containerClass);
          if (item[6])
            this.setFlagChangeID(item, commentHead.parentNode.id);

        } else {
          // the change was made by another user
          if (!reachedEnd) {
            var parentDiv = commentHead.parentNode;
            var previous = this.previousElementSibling(parentDiv);
            if (previous && previous.className.indexOf("ih_history") >= 0) {
              currentDiv = this.previousElementSibling(parentDiv);
            } else {
              if (commentTimes.length == 1) {
                parentDiv.parentNode.insertBefore(currentDiv, parentDiv.nextSibling);
              } else {
                parentDiv.parentNode.insertBefore(currentDiv, parentDiv);
              }
            }
          } else {
            var parentDiv = commentHead.parentNode;
            var next = this.nextElementSibling(parentDiv);
            if (next && next.className.indexOf("ih_history") >= 0) {
              currentDiv = this.nextElementSibling(parentDiv);
            } else {
              lastCommentDiv.parentNode.insertBefore(currentDiv, lastCommentDiv.nextSibling);
            }
          }

          var itemContainer = document.createElement('div');
          itemContainer.className = 'ih_history_item ' + containerClass;
          itemContainer.id = 'h' + i;
          itemContainer.innerHTML = item[3] + '<div class="ih_history_change">' + item[2] + '</div>';

          if (ih_activity_sort_order == 'oldest_to_newest') {
            currentDiv.appendChild(itemContainer);
          } else {
            currentDiv.insertBefore(itemContainer, currentDiv.firstChild);
          }
          currentDiv.setAttribute("class", "bz_comment ih_history");
          if (item[6])
            this.setFlagChangeID(item, 'h' + i);
        }
        break;
      }
    }

    // find comment blocks which only contain cc changes, shift the ih_cc
    var historyDivs = Dom.getElementsByClassName('ih_history', 'div', 'comments');
    for (var i = 0, il = historyDivs.length; i < il; i++) {
      var historyDiv = historyDivs[i];
      var itemDivs = Dom.getElementsByClassName('ih_history_item', 'div', historyDiv);
      var ccOnly = true;
      for (var j = 0, jl = itemDivs.length; j < jl; j++) {
        if (!Dom.hasClass(itemDivs[j], 'ih_cc')) {
          ccOnly = false;
          break;
        }
      }
      if (ccOnly) {
        for (var j = 0, jl = itemDivs.length; j < jl; j++) {
          Dom.removeClass(itemDivs[j], 'ih_cc');
        }
        Dom.addClass(historyDiv, 'ih_cc');
      }
    }

    if (this._hasAttachmentFlags)
      this.linkAttachmentFlags();
    if (this._hasBugFlags)
      this.linkBugFlags();

    ih_activity = undefined;
    ih_activity_flags = undefined;

    this._ccDivs = Dom.getElementsByClassName('ih_cc', '', 'comments');
    this.hideCC();
    YAHOO.util.Event.onDOMReady(this.addCCtoggler);
  },

  setFlagChangeID: function(changeItem, id) {
    // put the ID for the change into ih_activity_flags
    for (var i = 0, il = ih_activity_flags.length; i < il; i++) {
      var flagItem = ih_activity_flags[i];
      // flagItem[0] : who.login
      // flagItem[1] : when
      // flagItem[2] : attach id
      // flagItem[3] : flag
      // flagItem[4] : who.identity
      // flagItem[5] : change div id
      if (flagItem[0] == changeItem[0] && flagItem[1] == changeItem[1]) {
        // store the div
        flagItem[5] = id;
        // tag that we have flags to process
        if (flagItem[2]) {
          this._hasAttachmentFlags = true;
        } else {
          this._hasBugFlags = true;
        }
        if (flagItem[3].match(/^needinfo\?/)) {
          this.lastNeedinfo = flagItem;
        }
        // don't break as there may be multiple flag changes at once
      }
    }
  },

  linkAttachmentFlags: function() {
    var rows = Dom.get('attachment_table').getElementsByTagName('tr');
    for (var i = 0, il = rows.length; i < il; i++) {

      // deal with attachments with flags only
      var tr = rows[i];
      if (!tr.id || tr.id == 'a0')
        continue;
      var attachFlagTd = Dom.getElementsByClassName('bz_attach_flags', 'td', tr);
      if (attachFlagTd.length == 0)
        continue;
      attachFlagTd = attachFlagTd[0];

      // get the attachment id
      var attachId = 0;
      var anchors = tr.getElementsByTagName('a');
      for (var j = 0, jl = anchors.length; j < jl; j++) {
        var match = anchors[j].href.match(/attachment\.cgi\?id=(\d+)/);
        if (match) {
          attachId = match[1];
          break;
        }
      }
      if (!attachId)
        continue;

      var html = '';

      // there may be multiple flags, split by <br>
      var attachFlags = attachFlagTd.innerHTML.split('<br>');
      for (var j = 0, jl = attachFlags.length; j < jl; j++) {
        var match = attachFlags[j].match(/^\s*(<span.+\/span>):([^\?\-\+]+[\?\-\+])([\s\S]*)/);
        if (!match) continue;
        var setterSpan = match[1];
        var flag = this.trim(match[2].replace(/\u2011/g, '-'));
        var requestee = this.trim(match[3]);
        var requesteeLogin = '';

        match = setterSpan.match(/title="([^"]+)"/);
        if (!match) continue;
        var setterIdentity = this.htmlDecode(match[1]);

        if (requestee) {
          match = requestee.match(/title="([^"]+)"/);
          if (!match) continue;
          requesteeLogin = this.htmlDecode(match[1]);
          match = requesteeLogin.match(/<([^>]+)>/);
          if (match)
            requesteeLogin = match[1];
        }

        var flagValue = requestee ? flag + '(' + requesteeLogin + ')' : flag;
        // find the id for this change
        var found = false;
        for (var k = 0, kl = ih_activity_flags.length; k < kl; k++) {
          flagItem = ih_activity_flags[k];
          if (
            flagItem[2] == attachId
            && flagItem[3] == flagValue
            && flagItem[4] == setterIdentity
          ) {
            html +=
              setterSpan + ': '
              + '<a href="#' + flagItem[5] + '">' + flag + '</a> '
              + requestee + '<br>';
            found = true;
            break;
          }
        }
        if (!found) {
          // something went wrong, insert the flag unlinked
          html += attachFlags[j] + '<br>';
        }
      }

      if (html)
        attachFlagTd.innerHTML = html;
    }
  },

  linkBugFlags: function() {
    var flags = Dom.get('flags');
    if (!flags) return;
    var rows = flags.getElementsByTagName('tr');
    for (var i = 0, il = rows.length; i < il; i++) {
      var cells = rows[i].getElementsByTagName('td');
      if (!cells[1]) continue;

      var match = cells[0].innerHTML.match(/title="([^"]+)"/);
      if (!match) continue;
      var setterIdentity = this.htmlDecode(match[1]);

      var flagValue = cells[2].getElementsByTagName('select');
      if (!flagValue.length) continue;
      flagValue = flagValue[0].value;

      var flagLabel = cells[1].getElementsByTagName('label');
      if (!flagLabel.length) continue;
      flagLabel = flagLabel[0];
      var flagName = this.trim(flagLabel.innerHTML).replace(/\u2011/g, '-');

      for (var j = 0, jl = ih_activity_flags.length; j < jl; j++) {
        flagItem = ih_activity_flags[j];
        if (
          !flagItem[2]
          && flagItem[3] == flagName + flagValue
          && flagItem[4] == setterIdentity
        ) {
          flagLabel.innerHTML =
            '<a href="#' + flagItem[5] + '">' + flagName + '</a>';
          break;
        }
      }
    }
  },

  hideCC: function() {
    Dom.addClass(this._ccDivs, 'ih_hidden');
  },

  showCC: function() {
    Dom.removeClass(this._ccDivs, 'ih_hidden');
  },

  addCCtoggler: function() {
    var ul = Dom.getElementsByClassName('bz_collapse_expand_comments');
    if (ul.length == 0)
      return;
    ul = ul[0];
    var a = document.createElement('a');
    a.href = 'javascript:void(0)';
    a.id = 'ih_toggle_cc';
    YAHOO.util.Event.addListener(a, 'click', function(e) {
      if (Dom.get('ih_toggle_cc').innerHTML == 'Show CC Changes') {
        a.innerHTML = 'Hide CC Changes';
        inline_history.showCC();
      } else {
        a.innerHTML = 'Show CC Changes';
        inline_history.hideCC();
      }
    });
    a.innerHTML = 'Show CC Changes';
    var li = document.createElement('li');
    li.appendChild(a);
    ul.appendChild(li);
  },

  confirmUnsafeUrl: function(url) {
    try {
        return confirm(
        'This is considered an unsafe URL and could possibly be harmful.\n'
        + 'The full URL is:\n\n' + url + '\n\nContinue?');
    } catch(e) {
        return false;
    }
  },

  previousElementSibling: function(el) {
    if (el.previousElementSibling)
      return el.previousElementSibling;
    while (el = el.previousSibling) {
      if (el.nodeType == 1)
        return el;
    }
  },

  nextElementSibling: function(el) {
    if (el.nextElementSibling)
      return el.nextElementSibling;
    while (el = el.nextSibling) {
      if (el.nodeType == 1)
        return el;
    }
  },

  getNeedinfoDiv: function () {
    if (this.lastNeedinfo && this.lastNeedinfo[5]) {
      return this.lastNeedinfo[5];
    }
  },

  htmlDecode: function(v) {
    if (!v.match(/&/)) return v;
    var e = document.createElement('textarea');
    e.innerHTML = v;
    return e.value;
  },

  trim: function(s) {
    return s.replace(/^\s+|\s+$/g, '');
  }
};
