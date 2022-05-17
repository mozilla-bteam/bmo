/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

var PhabUser = {};

PhabUser.getUser = async () => {
    var userCell = document.getElementById("phab_user");
    var revisionsCell = document.getElementById("phab_revisions");
    if (!userCell || !revisionsCell) {
      return;
    }

    var user_id = userCell.getAttribute("data-target-user-id");

    userCell.textContent = "Loading...";
    revisionsCell.textContent = "Loading...";

    function displayLoadError(errStr) {
        userCell.textContent = errStr;
        revisionsCell.textContent = "";
    }

    try {
        var { user } = await Bugzilla.API.get(`phabbugz/user/${user_id}`);
        if (!user) {
            userCell.textContent = "Not Found";
            revisionsCell.textContent = "Not Found";
            return;
        }

        var userLink = document.createElement("a");
        userLink.setAttribute("href", user.userURL);
        userLink.textContent = `${user.userName} (${user.realName})`;
        userCell.textContent = "";
        userCell.appendChild(userLink);

        var revisionsLink = document.createElement("a");
        revisionsLink.setAttribute("href", user.revisionsURL);
        revisionsLink.textContent = "Open revisions";
        revisionsCell.textContent = "";
        revisionsCell.appendChild(revisionsLink);
    } catch ({ message }) {
        displayLoadError('Error: ' + message);
    }
};

document.addEventListener("DOMContentLoaded", function(event) {
    PhabUser.getUser();
});
