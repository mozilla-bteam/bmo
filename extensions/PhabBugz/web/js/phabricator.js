/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

var Phabricator = {};

Phabricator.getBugRevisions = function() {
    var phabUrl = $('.phabricator-revisions').data('phabricator-base-uri');
    var tr      = $('<tr/>');
    var td      = $('<td/>');
    var link    = $('<a/>');
    var table   = $('<table/>');

    function revisionRow(revision) {
        var trRevision   = tr.clone();
        var tdId         = td.clone();
        var tdAuthor     = td.clone();
        var tdTitle      = td.clone();
        var tdStatus     = td.clone();
        var tdReviewers  = td.clone();
        var tableReviews = table.clone();

        var revLink = link.clone();
        revLink.attr('href', phabUrl + '/' + revision.id);
        revLink.text(revision.id);
        tdId.append(revLink);

        tdAuthor.text(revision.author);
        tdStatus.text(revision.status);

        tdTitle.text(revision.title);
        tdTitle.addClass('phabricator-title');

        var i = 0, l = revision.reviews.length;
        for (; i < l; i++) {
            var trReview       = tr.clone();
            var tdReviewStatus = td.clone();
            var tdReviewer     = td.clone();
            tdReviewStatus.text(revision.reviews[i].status);
            tdReviewer.text(revision.reviews[i].user);
            trReview.append(tdReviewStatus, tdReviewer);
            tableReviews.append(trReview);
        }
        tdReviewers.append(tableReviews);

        trRevision.append(
            tdId,
            tdTitle,
            tdAuthor,
            tdStatus,
            tdReviewers
        );

        return trRevision;
    }

    var tbody = $('tbody.phabricator-revision');

    function displayLoadError(errStr) {
        var errRow = tbody.find('.phabricator-loading-error-row');
        errRow.find('.phabricator-load-error-string').text(errStr);
        errRow.removeClass('bz_default_hidden');
    }

    var $getUrl = '/rest/phabbugz/bug_revisions/' + BUGZILLA.bug_id +
                  '?Bugzilla_api_token=' + BUGZILLA.api_token;

    $.getJSON($getUrl, function(data) {
        if (data.revisions.length === 0) {
            displayLoadError('none returned from server');
        } else {
            var i = 0;
            for (; i < data.revisions.length; i++) {
                tbody.append(revisionRow(data.revisions[i]));
            }
        }
        tbody.find('.phabricator-loading-row').addClass('bz_default_hidden');
    }).fail(function(jqXHR, textStatus, errorThrown) {
        var errStr;
        if (jqXHR.responseJSON && jqXHR.responseJSON.err &&
            jqXHR.responseJSON.err.msg) {
            errStr = jqXHR.responseJSON.err.msg;
        } else if (errorThrown) {
            errStr = errorThrown;
        } else {
            errStr = 'unknown';
        }
        displayLoadError(errStr);
        tbody.find('.phabricator-loading-row').addClass('bz_default_hidden');
    });
};

$().ready(function() {
    Phabricator.getBugRevisions();
});
