/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

var Phabricator = {};

// Add pseudo root revision that has all root revisions as child.
function addPseudoRoot(revisions, revMap) {
  for (const rev of revisions) {
    rev.isChild = false;
  }

  for (const rev of revisions) {
    for (const id of rev.children) {
      const child = revMap[id];
      if (!child) {
        continue;
      }

      child.isChild = true;
    }
  }

  // This code assumes the passed `revs` is already sorted by the submitted
  // order. If there's no relation between revisions, the original order
  // is kept.
  const roots = [];
  for (const rev of revisions) {
    if (!rev.isChild) {
      roots.push(rev.id);
    }
  }

  const pseudoRoot = {
    id: "ROOT",
    children: roots,
  };

  revisions.push(pseudoRoot);

  return pseudoRoot;
}

// Let child revision's rank be higher than parent revision's rank.
// This code assumes there's no cycle, that's guaranteed by phabricator.
function fixRank(root, revMap) {
  const queue = [root];
  while (queue.length) {
    const rev = queue.shift();
    for (const id of rev.children) {
      const child = revMap[id];
      if (!child) {
        continue;
      }

      child.rank = Math.max(child.rank, rev.rank + 1);

      if (!queue.some(rev => rev == child)) {
        queue.push(child);
      }
    }
  }
}

function sortByRank(revisions) {
  revisions.sort((a, b) => {
    if (a.rank != b.rank) {
      return a.rank - b.rank;
    }
    return a.sortkey - b.sortkey;
  });
}

function findFirstUnhandledBranch(revisions) {
  for (const rev of revisions) {
    if (rev.hasBranch && !rev.isBranchHandled) {
      return rev;
    }
  }
  return null;
}

// Split branches into contiguous space.
function splitBranches(revisions, revMap, branchCount) {
  let N = revisions.length;
  let n = N ** branchCount;
  while (true) {
    const rev = findFirstUnhandledBranch(revisions);
    if (!rev) {
      break;
    }

    // Split the range of rank for each child.
    for (const [i, id] of rev.children.entries()) {
      const child = revMap[id];
      if (!child) {
        continue;
      }

      child.rank += n * i;
    }
    n /= N;

    fixRank(rev, revMap);
    sortByRank(revisions);

    rev.isBranchHandled = true;
  }
}

// Sort revisions based on the graph.
function sortRevisions(revs) {
  if (!revs.length) {
    return revs;
  }

  const revisions = revs.slice();

  const revMap = {};
  for (const rev of revisions) {
    // If the data is old, do nothing.
    if (!rev.children) {
      return revs;
    }

    revMap[rev.id] = rev;
  }

  const pseudoRoot = addPseudoRoot(revisions, revMap);

  // Setup extra fields.
  let branchCount = 0;
  for (const rev of revisions) {
    rev.rank = 1;
    rev.hasBranch = rev.children.length > 1;
    rev.isBranchHandled = false;

    if (rev.hasBranch) {
      branchCount++;
    }
  }

  // Make the revisions partially ordered.
  fixRank(pseudoRoot, revMap);
  sortByRank(revisions);

  if (branchCount < 8) {
    // Perform only if the stack is simple enough.
    splitBranches(revisions, revMap, branchCount);
  }

  return revisions.filter(rev => rev != pseudoRoot).reverse();
}

Phabricator.getBugRevisions = async () => {
    var phabUrl = document.querySelector('.phabricator-revisions').getAttribute('data-phabricator-base-uri');

    function revisionRow(revision) {
        var trRevision     = document.createElement('tr');
        var tdId           = document.createElement('td');
        var tdTitle        = document.createElement('td');
        var tdRevisionStatus       = document.createElement('td');
        var tdReviewers    = document.createElement('td');
        var tableReviews   = document.createElement('table');

        var spanRevisionStatus     = document.createElement('span');
        var spanRevisionStatusIcon = document.createElement('span');
        var spanRevisionStatusText = document.createElement('span');

        var revLink = document.createElement('a');
        revLink.setAttribute('href', phabUrl + revision.id);
        revLink.append(revision.id);
        tdId.append(revLink);

        tdTitle.append(revision.title);
        tdTitle.classList.add('phabricator-title');

        spanRevisionStatusIcon.classList.add('revision-status-icon-' + revision.status);
        spanRevisionStatus.append(spanRevisionStatusIcon);
        spanRevisionStatusText.append(revision.long_status);
        spanRevisionStatus.append(spanRevisionStatusText);
        spanRevisionStatus.classList.add('revision-status-box-' + revision.status);
        tdRevisionStatus.append(spanRevisionStatus);

        var reviews = revision.reviews.slice().sort((a, b) => {
          return a.user < b.user ? -1 : 1;
        });

        var i = 0, l = reviews.length;
        for (; i < l; i++) {
            var trReview             = document.createElement('tr');
            var tdReviewStatus       = document.createElement('td');
            var tdReviewer           = document.createElement('td');
            var spanReviewStatusIcon = document.createElement('span');
            trReview.title = reviews[i].long_status;
            spanReviewStatusIcon.classList.add('review-status-icon-' + reviews[i].status);
            tdReviewStatus.append(spanReviewStatusIcon);
            tdReviewer.append(reviews[i].user);
            tdReviewer.classList.add('review-reviewer');
            trReview.append(tdReviewStatus, tdReviewer);
            tableReviews.append(trReview);
        }
        tableReviews.classList.add('phabricator-reviewers');
        tdReviewers.append(tableReviews);

        trRevision.setAttribute('data-status', revision.status);
        if (revision.status === 'abandoned') {
            trRevision.classList.add('bz_default_hidden');
            document.querySelector('tbody.phabricator-show-abandoned').classList.remove('bz_default_hidden');
        }

        trRevision.append(
            tdId,
            tdRevisionStatus,
            tdReviewers,
            tdTitle
        );

        return trRevision;
    }

    var tbody = document.querySelector('tbody.phabricator-revision');

    function displayLoadError(errStr) {
        var errRow = tbody.querySelector('.phabricator-loading-error-row');
        errRow.querySelector('.phabricator-load-error-string').replaceChildren(errStr);
        errRow.classList.remove('bz_default_hidden');
    }

    try {
        const { revisions } = await Bugzilla.API.get(`phabbugz/bug_revisions/${BUGZILLA.bug_id}`);

        if (revisions.length) {
            sortRevisions(revisions).forEach(rev => tbody.append(revisionRow(rev)));
        } else {
            displayLoadError('none returned from server');
        }
    } catch ({ message }) {
        displayLoadError(message);
    }

    tbody.querySelector('.phabricator-loading-row').classList.add('bz_default_hidden');
};

window.addEventListener("DOMContentLoaded", function() {
    Phabricator.getBugRevisions();

    document.querySelector('#phabricator-show-abandoned').addEventListener('click', event => {
        for (const row of document.querySelectorAll('tbody.phabricator-revision > tr')) {
            if (row.getAttribute('data-status') === 'abandoned') {
                if (document.querySelector('#phabricator-show-abandoned').checked) {
                    row.classList.remove('bz_default_hidden');
                }
                else {
                    row.classList.add('bz_default_hidden');
                }
            }
        }
    });
});
