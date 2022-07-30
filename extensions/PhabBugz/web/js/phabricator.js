/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

/* global Bugzilla, BUGZILLA */

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

function findFreeIndex(edges) {
  let index = 0;

  while (true) {
    if (!edges.has(index)) {
      return index;
    }
    index++;
  }
}

const svgns = "http://www.w3.org/2000/svg";

const EdgeMargin = 8;

const Phabricator = {
  // A map from revision ID to graph's svg element.
  svgs: new Map(),

  // A map from revision ID to table row.
  trs: new Map(),

  // True if abandoned revisions should be shown.
  showAbandoned: false,

  // A list of revisions, sorted in the stack order, root to leaf.
  revisions: null,

  // Set revisions and sort them in the stack order.
  setRevisions(revisions) {
    this.revisions = revisions.slice();

    if (!this.revisions.length) {
      return;
    }

    revisions = this.revisions;

    const revMap = {};
    for (const rev of revisions) {
      // If the data is old, do nothing.
      if (!rev.children) {
        return;
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

    this.revisions = revisions.filter(rev => rev != pseudoRoot);
  },

  // Calculate a graph edges.
  //
  // The graph uses X-axis as index.
  //
  //    0 1 2
  //
  //    o
  //    |
  //    |\
  //    | |
  //    | o
  //    | |
  //    | | o
  //    | | |
  //    | |/
  //    | o
  //    | |\
  //    | | |
  //    | | o
  //    | | |
  //    | o |
  //    | |/
  //    o |
  //    | |
  //    |/
  //    |
  //    o
  //
  // Each revision has the following information:
  //
  //   * The node's index
  //   * List of parent node's index
  //   * Whether the node has children
  //   * List of other edge, represented by from/to indices
  //
  // That correspnds to the following part in the above graph:
  //
  //    | | |
  //    | o |
  //    | |/
  //
  calculateGraph() {
    if (!this.revisions.length) {
      return;
    }

    let revisions = this.revisions;
    if (!this.showAbandoned) {
      revisions = revisions.filter(rev => rev.status !== "abandoned");
    }

    const revMap = {};
    for (const rev of revisions) {
      revMap[rev.id] = rev;
    }

    // A map from edge's index to a set of remaining children.
    const edges = new Map();

    let maxEdgeCount = 1;
    for (const rev of revisions) {
      const visibleChildren = rev.children.filter(child => child in revMap);

      const graph = {
        // This node's index.
        index: null,

        // List of parent node's index.
        parentIndices: [],

        // True if there are visible children.
        hasChildren: visibleChildren.length > 0,

        // Othe edges in the same row.
        otherEdges: [],
      };
      rev.graph = graph;

      // Find all parents, and clear the parent's edge if this node is the last
      // remaining child.
      for (const [index, edge] of edges) {
        if (edge.remainingChildren.has(rev.id)) {
          edge.remainingChildren.delete(rev.id);
          if (edge.remainingChildren.size == 0) {
            edges.delete(index);
          }

          graph.parentIndices.push(index);
        }
      }

      // After cleaning up parent edges, the remaining edges are drawn
      // concurrently.
      for (const [index, edge] of edges) {
        graph.otherEdges.push({
          from: index,
          to: index,
        });
      }

      // Find this node's index.
      if (graph.parentIndices.length > 0) {
        for (const parentIndex of graph.parentIndices) {
          if (!edges.has(parentIndex)) {
            // If there's any parent where this node is the last remaining
            // child, use that parent's index.
            //
            //   o <- this node
            //   |
            //   o <- parent
            //   |
            //
            graph.index = parentIndex;
            break;
          }
        }

        if (graph.index === null) {
          // If all parents still have remaining children, put this node
          // at the first parent's index, and move the remaining children of
          // the first child into a new index.
          //
          // | <--- edge for remaining chidlren
          // |
          // | o <- this node
          //  \|
          //   |
          //   o <- parent
          //   |
          //
          const parentIndex = graph.parentIndices[0];
          graph.index = parentIndex;
          const newParentIndex = findFreeIndex(edges);
          const parentEdge = edges.get(parentIndex);
          edges.delete(parentIndex);
          edges.set(newParentIndex, parentEdge);

          // The edge for the remaining children.
          graph.otherEdges.push({
            from: parentIndex,
            to: newParentIndex,
          });
        }
      } else {
        // This node has no parent. Put it into a new index.
        graph.index = findFreeIndex(edges);
      }

      // Put a new edge to this node's children.
      if (graph.hasChildren) {
        edges.set(graph.index, {
          remainingChildren: new Set(visibleChildren),
        });
      }

      maxEdgeCount = Math.max(maxEdgeCount, edges.size);
    }

    this.maxEdgeCount = maxEdgeCount;
  },

  svgWidth() {
    return (this.maxEdgeCount + 1) * EdgeMargin;
  },

  toNodeX(index) {
    return EdgeMargin * (1 + index);
  },

  // Draw graph in the pre-populated svg elements for each revision's row.
  drawGraph() {
    const color = "#cc0099";

    for (const rev of this.revisions) {
      if (!this.showAbandoned) {
        if (rev.status === "abandoned") {
          continue;
        }
      }

      const svg = this.svgs.get(rev.id);

      // Cleanup the previous result before switching showAbandoned checkbox.
      svg.setAttribute("width", this.svgWidth());
      svg.replaceChildren();

      // Fit to the table row.
      // The height of the row can differ for each, due to:
      //   * The number of reviewers can be different for each
      //   * Long title can be wrapped into multiple lines
      const h = svg.parentNode.offsetHeight;
      svg.setAttribute("height", h);

      const graph = rev.graph;

      const x = this.toNodeX(graph.index);
      const y = h / 2;

      // An edge to children.
      if (graph.hasChildren) {
        const path = document.createElementNS(svgns, "path");
        svg.append(path);
        path.setAttribute("d", `M ${x} ${y} L ${x} 0`);
        path.setAttribute("fill", "none");
        path.setAttribute("stroke", color);
        path.setAttribute("stroke-width", "1");
      }

      // An edge from parents.
      for (const index of graph.parentIndices) {
        const px = this.toNodeX(index);

        const path = document.createElementNS(svgns, "path");
        svg.append(path);
        path.setAttribute("d",
                          `M ${x} ${y} ` +
                          `C ${x} ${h},  ${px} ${y},  ${px} ${h}`);
        path.setAttribute("fill", "none");
        path.setAttribute("stroke", color);
        path.setAttribute("stroke-width", "1");
      }

      // Other edges in the same row.
      for (const {from, to} of graph.otherEdges) {
        const fromX = this.toNodeX(from);
        const toX = this.toNodeX(to);

        const path = document.createElementNS(svgns, "path");
        svg.append(path);
        path.setAttribute("d",
                          `M ${toX} 0 ` +
                          `L ${toX} ${y} ` +
                          `C ${toX} ${h}, ${fromX} ${y}, ${fromX} ${h}`);
        path.setAttribute("fill", "none");
        path.setAttribute("stroke", color);
        path.setAttribute("stroke-width", "1");
      }

      // This node.
      const circle = document.createElementNS(svgns, "circle");
      svg.append(circle);
      circle.setAttribute("fill", color);
      circle.setAttribute("stroke", color);
      circle.setAttribute("cx", x);
      circle.setAttribute("cy", y);
      circle.setAttribute("r", "3");
    }
  },

  createTable() {
    const phabUrl = document.querySelector(".phabricator-revisions").getAttribute("data-phabricator-base-uri");

    const tbody = document.querySelector("tbody.phabricator-revision");

    let hasAbandonedRevisions = false;

    for (const rev of this.revisions.slice().reverse()) {
      const trRevision = document.createElement("tr");
      this.trs.set(rev.id, trRevision);

      // Graph

      const tdGraph = document.createElement("td");
      tdGraph.style.paddingTop = "0";
      tdGraph.style.paddingBottom = "0";

      const svg = document.createElementNS(svgns, "svg");
      svg.setAttribute("xmlns", svgns);
      svg.setAttribute("version", "1.1");
      svg.setAttribute("width", this.svgWidth());
      svg.setAttribute("height", 10);
      svg.style.display = "block";
      this.svgs.set(rev.id,  svg);
      tdGraph.append(svg);

      // Revision ID

      const tdId = document.createElement("td");
      const revLink = document.createElement("a");
      revLink.setAttribute("href", phabUrl + rev.id);
      revLink.append(rev.id);
      tdId.append(revLink);

      // Revision status

      const tdRevisionStatus = document.createElement("td");

      const spanRevisionStatus = document.createElement("span");
      spanRevisionStatus.classList.add("revision-status-box-" + rev.status);

      const spanRevisionStatusIcon = document.createElement("span");
      spanRevisionStatusIcon.classList.add("revision-status-icon-" + rev.status);
      spanRevisionStatus.append(spanRevisionStatusIcon);

      const spanRevisionStatusText = document.createElement("span");
      spanRevisionStatusText.append(rev.long_status);
      spanRevisionStatus.append(spanRevisionStatusText);

      tdRevisionStatus.append(spanRevisionStatus);

      // Reviewers

      const tdReviewers = document.createElement("td");

      const tableReviews = document.createElement("table");
      tableReviews.classList.add("phabricator-reviewers");

      for (const review of rev.reviews.slice().sort((a, b) => {
        return a.user < b.user ? -1 : 1;
      })) {
        const trReview = document.createElement("tr");
        trReview.title = review.long_status;

        const tdReviewStatus = document.createElement("td");
        const spanReviewStatusIcon = document.createElement("span");
        spanReviewStatusIcon.classList.add("review-status-icon-" + review.status);
        tdReviewStatus.append(spanReviewStatusIcon);

        const tdReviewer = document.createElement("td");
        tdReviewer.classList.add("review-reviewer");
        tdReviewer.append(review.user);

        trReview.append(tdReviewStatus, tdReviewer);

        tableReviews.append(trReview);
      }
      tdReviewers.append(tableReviews);

      // Revision Title

      const tdTitle = document.createElement("td");
      tdTitle.classList.add("phabricator-title");
      tdTitle.append(rev.title);

      // Hide abandoned revisions

      if (rev.status === "abandoned") {
        if (!this.showAbandoned) {
          trRevision.classList.add("bz_default_hidden");
        }
        hasAbandonedRevisions = true;
      }

      trRevision.append(
        tdGraph,
        tdId,
        tdRevisionStatus,
        tdReviewers,
        tdTitle
      );

      tbody.append(trRevision);
    }

    if (hasAbandonedRevisions) {
      document.querySelector("tbody.phabricator-show-abandoned").classList.remove("bz_default_hidden");
    }
  },

  // Show/hide abandoned revisions.
  updateVisibility() {
    for (const rev of this.revisions) {
      const tr = this.trs.get(rev.id);

      if (rev.status !== "abandoned") {
        continue;
      }

      tr.classList.toggle("bz_default_hidden", !this.showAbandoned);
    }
  },

  async onLoad() {
    const showAbandonedCheckbox = document.querySelector("#phabricator-show-abandoned");
    this.showAbandoned = showAbandonedCheckbox.checked;

    const tbody = document.querySelector("tbody.phabricator-revision");

    function displayLoadError(errStr) {
      const errRow = tbody.querySelector(".phabricator-loading-error-row");
      errRow.querySelector(".phabricator-load-error-string").replaceChildren(errStr);
      errRow.classList.remove("bz_default_hidden");
    }

    try {
      const { revisions } = await Bugzilla.API.get(`phabbugz/bug_revisions/${BUGZILLA.bug_id}`);

      if (revisions.length) {
        this.setRevisions(revisions);
        this.calculateGraph();
        this.createTable();
        this.drawGraph();
      } else {
        displayLoadError("none returned from server");
      }
    } catch (e) {
      console.error(e);
      displayLoadError(e.message);
    }

    tbody.querySelector(".phabricator-loading-row").classList.add("bz_default_hidden");

    showAbandonedCheckbox.addEventListener("click", event => {
      this.showAbandoned = showAbandonedCheckbox.checked;
      this.updateVisibility();
      this.calculateGraph();
      this.drawGraph();
    });
  },
};

window.addEventListener("DOMContentLoaded", function() {
  Phabricator.onLoad();
});
