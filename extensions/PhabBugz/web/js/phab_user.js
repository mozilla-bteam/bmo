/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

var PhabUser = {};

PhabUser.getUser = async () => {
    var userCell = $('#phab_user');
    var revisionsCell = $('#phab_revisions');
    if (!userCell || !revisionsCell) {
      return;
    }

    var user_id = userCell.data('target-user-id');

    userCell.text('Loading...');
    revisionsCell.text('Loading...');

    try {
        var { user } = await Bugzilla.API.get(`phabbugz/user/${user_id}`);
        if (!user) {
            userCell.text('Not Found');
            revisionsCell.text('Not Found');
            return;
        }

        var userLink = $('<a/>');
        userLink.attr('href', user.userURL);
        userLink.text(`${user.userName} (${user.realName})`);
        userCell.text('');
        userCell.append(userLink);

        var revisionsLink = $('<a/>');
        revisionsLink.attr('href', user.revisionsURL);
        revisionsLink.text('Open revisions');
        revisionsCell.text('');
        revisionsCell.append(revisionsLink);
    } catch ({ message }) {
        userCell.text(message);
        revisionsCell.text('');
    }
};


$().ready(function() {
    PhabUser.getUser();
});
