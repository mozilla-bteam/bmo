/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

"use strict";

const GitHubPullRequests = {
  pullRequests: [],

  // Maps PR state to display label and CSS class
  STATE_LABELS: {
    open:   { label: "Open",   cls: "gh-state-open"   },
    draft:  { label: "Draft",  cls: "gh-state-draft"  },
    merged: { label: "Merged", cls: "gh-state-merged" },
    closed: { label: "Closed", cls: "gh-state-closed" },
  },

  // Maps GitHub review state to a symbol shown next to reviewer name
  REVIEW_SYMBOLS: {
    APPROVED:           { symbol: "✓", cls: "gh-review-approved",  title: "Approved"           },
    CHANGES_REQUESTED:  { symbol: "✗", cls: "gh-review-changes",   title: "Changes Requested"  },
    DISMISSED:          { symbol: "–", cls: "gh-review-dismissed",  title: "Dismissed"          },
    PENDING:            { symbol: "…", cls: "gh-review-pending",    title: "Pending"            },
  },

  isClosedState(state) {
    return state === "closed" || state === "merged";
  },

  buildRow(pr) {
    const tr = document.createElement("tr");
    tr.dataset.prUrl = pr.url;
    tr.dataset.prState = pr.state || "";

    if (pr.inaccessible) {
      tr.classList.add("github-pr-inaccessible");
    }

    if (pr.state && this.isClosedState(pr.state)) {
      tr.classList.add("github-pr-closed");
    }

    // PR number cell
    const tdPr = document.createElement("td");
    tdPr.className = "gh-col-pr";
    const prLink = document.createElement("a");
    prLink.href = pr.url;
    prLink.target = "_blank";
    prLink.rel = "noopener noreferrer";
    prLink.textContent = `#${pr.number}`;
    tdPr.appendChild(prLink);
    tr.appendChild(tdPr);

    // Status cell
    const tdStatus = document.createElement("td");
    tdStatus.className = "gh-col-status";
    if (pr.inaccessible) {
      tdStatus.textContent = "—";
    } else {
      const stateInfo = this.STATE_LABELS[pr.state] || {label: pr.state, cls: ""};
      const badge = document.createElement("span");
      badge.className = `gh-state-badge ${stateInfo.cls}`;
      badge.textContent = stateInfo.label;
      tdStatus.appendChild(badge);
    }
    tr.appendChild(tdStatus);

    // Author cell
    const tdAuthor = document.createElement("td");
    tdAuthor.className = "gh-col-author";
    if (pr.inaccessible || !pr.author) {
      tdAuthor.textContent = "—";
    } else {
      const authorLink = document.createElement("a");
      authorLink.href = `https://github.com/${pr.author}`;
      authorLink.target = "_blank";
      authorLink.rel = "noopener noreferrer";
      authorLink.textContent = pr.author;
      tdAuthor.appendChild(authorLink);
    }
    tr.appendChild(tdAuthor);

    // Reviewers cell
    const tdReviewers = document.createElement("td");
    tdReviewers.className = "gh-col-reviewers";
    if (pr.inaccessible || !pr.reviews || pr.reviews.length === 0) {
      tdReviewers.textContent = "—";
    } else {
      const reviewerList = document.createElement("ul");
      reviewerList.className = "gh-reviewer-list";
      for (const review of pr.reviews) {
        const li = document.createElement("li");
        const symbol = this.REVIEW_SYMBOLS[review.state] || {symbol: "?", cls: "", title: review.state};
        const sym = document.createElement("span");
        sym.className = `gh-review-symbol ${symbol.cls}`;
        sym.title = symbol.title;
        sym.textContent = symbol.symbol;
        li.appendChild(sym);
        li.appendChild(document.createTextNode(` ${review.user}`));
        reviewerList.appendChild(li);
      }
      tdReviewers.appendChild(reviewerList);
    }
    tr.appendChild(tdReviewers);

    // Repository cell
    const tdRepo = document.createElement("td");
    tdRepo.className = "gh-col-repo";
    if (pr.inaccessible || !pr.repo) {
      tdRepo.textContent = pr.repo || "—";
    } else {
      const repoLink = document.createElement("a");
      repoLink.href = `https://github.com/${pr.repo}`;
      repoLink.target = "_blank";
      repoLink.rel = "noopener noreferrer";
      repoLink.textContent = pr.repo;
      tdRepo.appendChild(repoLink);
    }
    tr.appendChild(tdRepo);

    // Labels cell
    const tdLabels = document.createElement("td");
    tdLabels.className = "gh-col-labels";
    if (pr.inaccessible || !pr.labels || pr.labels.length === 0) {
      tdLabels.textContent = "—";
    } else {
      const labelList = document.createElement("span");
      labelList.className = "gh-label-list";
      for (const label of pr.labels) {
        const span = document.createElement("span");
        span.className = "gh-label";
        span.textContent = label;
        labelList.appendChild(span);
      }
      tdLabels.appendChild(labelList);
    }
    tr.appendChild(tdLabels);

    // Title cell
    const tdTitle = document.createElement("td");
    tdTitle.className = "gh-col-title";
    if (pr.inaccessible) {
      const titleLink = document.createElement("a");
      titleLink.href = pr.url;
      titleLink.target = "_blank";
      titleLink.rel = "noopener noreferrer";
      titleLink.textContent = `PR #${pr.number}`;
      tdTitle.appendChild(titleLink);
      const note = document.createElement("span");
      note.className = "gh-inaccessible-note";
      note.textContent = " (details unavailable)";
      tdTitle.appendChild(note);
    } else {
      const titleLink = document.createElement("a");
      titleLink.href = pr.url;
      titleLink.target = "_blank";
      titleLink.rel = "noopener noreferrer";
      titleLink.textContent = pr.title;
      tdTitle.appendChild(titleLink);
    }
    tr.appendChild(tdTitle);

    return tr;
  },

  async onLoad() {
    const tbody = document.querySelector("tbody.github-prs-body");
    if (!tbody) return;

    const loadingRow = tbody.querySelector(".github-loading-row");
    if (!loadingRow) return;

    const displayLoadError = (errStr) => {
      const errRow = tbody.querySelector(".github-loading-error-row");
      if (!errRow) return;
      errRow.querySelector(".github-load-error-string")?.replaceChildren(errStr);
      errRow.classList.remove("bz_default_hidden");
    };

    try {
      const { pull_requests } = await Bugzilla.API.get(
        `githubpr/bug_pull_requests/${BUGZILLA.bug_id}`
      );

      this.pullRequests = pull_requests || [];

      if (this.pullRequests.length === 0) {
        // Zero results is a normal outcome (e.g. all attachments were obsolete
        // or unparseable), not an error - show a neutral message in place.
        loadingRow.querySelector("td").textContent = "No pull requests found.";
      } else {
        for (const pr of this.pullRequests) {
          tbody.insertBefore(this.buildRow(pr), loadingRow);
        }
        loadingRow.classList.add("bz_default_hidden");
      }
    } catch (e) {
      console.error(e);
      displayLoadError(e.message);
      loadingRow.classList.add("bz_default_hidden");
    }
  },
};

window.addEventListener("DOMContentLoaded", () => {
  GitHubPullRequests.onLoad();
});
