/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

/**
 * @param {HTMLElement} vcard
 */
function show_usermenu(vcard) {
    const {
      userId: id,
      userEmail: email,
      userName: name,
      showEdit: show_edit,
      hideProfile: hide_profile,
    } = vcard.dataset;

    var items = [
        {
            name: "Activity",
            callback: function () {
                var href = `${BUGZILLA.config.basepath}page.cgi?` +
                           `id=user_activity.html&action=run&from=-14d&who=${encodeURIComponent(email)}`;
                window.open(href, "_blank");
            }
        },
        {
            name: "Mail",
            callback: function () {
                var href = "mailto:" + encodeURIComponent(email);
                window.open(href, "_blank");
            }
        }
    ];
    if (name) {
        items.unshift({
            name: "Copy Name",
            callback: function () {
                $('#clip-container').show();
                $('#clip').val(name).select();
                $('#floating-message-text')
                  .text(document.execCommand('copy') ? 'Name has been copied' : 'Could not copy name');
                $('#floating-message').fadeIn(250).delay(2500).fadeOut();
                $('#clip-container').hide();
            }
        });
    }
    if (hide_profile === "0") {
        items.unshift({
            name: "Profile",
            callback: function () {
                var href = `${BUGZILLA.config.basepath}user_profile?user_id=${id}`;
                window.open(href, "_blank");
            }
        });
    }
    if (show_edit === "1") {
        items.push({
            name: "Edit",
            callback: function () {
                var href = `${BUGZILLA.config.basepath}editusers.cgi?action=edit&userid=${id}`;
                window.open(href, "_blank");
            }
        });
    }
    if (id && $('#needinfo_role').is(':visible')) {
        items.push({
            name: "Needinfo",
            callback: function () {
                let role = "other";
                $('#needinfo_role option').each(function() {
                    if ($(this).data('userid') === parseInt(id)) {
                        role = $(this).val();
                        return false;
                    }
                });
                $('#needinfo').prop('checked', true);
                $('#needinfo_role').val(role);
                $('#needinfo_role').trigger('change');
                if (role == 'other') {
                    $('#needinfo_from').val(email);
                    $('#needinfo_from').focus();
                }
                $.scrollTo($('#needinfo_container'));
            }
        });
    }

    /** @type {HTMLDialogElement | HTMLBodyElement} */
    const appendTo = vcard.closest('dialog, body');

    $.contextMenu({
        selector: `${appendTo.matches('dialog') ? 'dialog' : 'body'} .vcard_${id}`,
        appendTo,
        position: appendTo.matches('dialog') ? ({ $menu }, x, y) => {
            $menu.css({ top: y - appendTo.offsetTop, left: x - appendTo.offsetLeft });
        } : undefined,
        trigger: "left",
        items,
        events: {
            hide: () => {
                window.setTimeout(() => {
                    // Remove the base layer because it won’t get updated when `appendTo` changes
                    document.querySelector('#context-menu-layer')?.remove();
                }, 500)
            },
        },
    });
}

$(function() {
  $('.show_usermenu').on("click", function (event) {
    return show_usermenu($(this)[0]);
  });
});
