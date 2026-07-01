/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

"use strict";

const GitHubPullRequests = {
  showClosed: false,
  pullRequests: [],

  // Some PRs may come back "pending" when the server hits its GitHub request
  // budget or an in-flight lock. Re-poll a few times so they fill in once the
  // cache warms, without requiring a manual page reload.
  refreshAttempts: 0,
  MAX_REFRESH_ATTEMPTS: 3,
  REFRESH_DELAY_MS: 5000,

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
    tr.classList.add("github-pr-row");
    tr.dataset.prUrl = pr.url;
    tr.dataset.prState = pr.state || "";

    // Cells with no useful data to show while a PR is pending or inaccessible.
    const unavailable = pr.pending || pr.inaccessible;

    if (pr.pending) {
      tr.classList.add("github-pr-pending");
    } else if (pr.inaccessible) {
      tr.classList.add("github-pr-inaccessible");
    }

    if (pr.state && this.isClosedState(pr.state)) {
      tr.classList.add("github-pr-closed");
      if (!this.showClosed) {
        tr.classList.add("bz_default_hidden");
      }
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
    if (pr.pending) {
      const badge = document.createElement("span");
      badge.className = "gh-state-badge gh-state-pending";
      badge.textContent = "Loading…";
      tdStatus.appendChild(badge);
    } else if (pr.inaccessible) {
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
    if (unavailable || !pr.author) {
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
    if (unavailable || !pr.reviews || pr.reviews.length === 0) {
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
    if (unavailable || !pr.repo) {
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
    if (unavailable || !pr.labels || pr.labels.length === 0) {
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
    if (unavailable) {
      const titleLink = document.createElement("a");
      titleLink.href = pr.url;
      titleLink.target = "_blank";
      titleLink.rel = "noopener noreferrer";
      titleLink.textContent = `PR #${pr.number}`;
      tdTitle.appendChild(titleLink);
      const note = document.createElement("span");
      note.className = "gh-inaccessible-note";
      note.textContent = pr.pending ? " (loading…)" : " (details unavailable)";
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

  updateVisibility() {
    for (const pr of this.pullRequests) {
      const tr = document.querySelector(`tr[data-pr-url="${CSS.escape(pr.url)}"]`);
      if (!tr) continue;
      if (this.isClosedState(pr.state || "")) {
        tr.classList.toggle("bz_default_hidden", !this.showClosed);
      }
    }
  },

  async onLoad() {
    const showClosedCheckbox = document.querySelector("#github-show-closed");
    if (!showClosedCheckbox) return;

    this.showClosed = showClosedCheckbox.checked;

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

    await this.poll(tbody, loadingRow, displayLoadError);

    showClosedCheckbox.addEventListener("click", () => {
      this.showClosed = showClosedCheckbox.checked;
      this.updateVisibility();
    });
  },

  async poll(tbody, loadingRow, displayLoadError) {
    try {
      const { pull_requests } = await Bugzilla.API.get(
        `githubpr/bug_pull_requests/${BUGZILLA.bug_id}`
      );

      this.pullRequests = pull_requests || [];

      // Remove any rows from a previous poll before re-rendering.
      tbody.querySelectorAll(".github-pr-row").forEach(row => row.remove());

      if (this.pullRequests.length === 0) {
        // Zero results is a normal outcome (e.g. all attachments were obsolete
        // or unparseable), not an error - show a neutral message in place.
        loadingRow.querySelector("td").textContent = "No pull requests found.";
        loadingRow.classList.remove("bz_default_hidden");
        return;
      }

      for (const pr of this.pullRequests) {
        tbody.insertBefore(this.buildRow(pr), loadingRow);
      }
      loadingRow.classList.add("bz_default_hidden");

      // Show the closed toggle if any PRs are closed/merged
      const hasClosed = this.pullRequests.some(pr => this.isClosedState(pr.state || ""));
      if (hasClosed) {
        const showClosedTbody = document.querySelector("tbody.github-show-closed");
        if (showClosedTbody) {
          showClosedTbody.classList.remove("bz_default_hidden");
        }
      }

      // Some PRs were deferred by the server (request budget / in-flight lock).
      // Re-poll a few times so they fill in once the cache warms.
      const hasPending = this.pullRequests.some(pr => pr.pending);
      if (hasPending && this.refreshAttempts < this.MAX_REFRESH_ATTEMPTS) {
        this.refreshAttempts++;
        setTimeout(
          () => this.poll(tbody, loadingRow, displayLoadError),
          this.REFRESH_DELAY_MS
        );
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
