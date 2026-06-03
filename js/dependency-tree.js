/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

/**
 * Implement the Dependency Tree widget, which is used on the dependency tree page and in the modal
 * bug page.
 */
Bugzilla.DependencyTree = class DependencyTree {
  /**
   * Initialize the dependency tree widget by attaching event listeners to the toolbar and tree
   * items.
   */
  constructor() {
    this.$trees = document.querySelector('#dependency-tree');

    if (!this.$trees || this.$trees.dataset.initialized === '1') {
      return;
    }


    this.data = this.$trees.dataset;
    this.data.initialized = '1';
    this.realDepth = Number(this.data.realDepth);
    this.uriLimit = BUGZILLA.constant.CGI_URI_LIMIT;

    this.$toolbar = this.$trees.querySelector('[role="toolbar"]');
    this.$container = this.$trees.querySelector('.tree-container');

    this.activateToolbar();
    this.activateTrees();
  }

  /**
   * Attach event listeners to the toolbar buttons and inputs to handle user interactions.
   */
  activateToolbar() {
    this.$toggleBtn = this.$toolbar.querySelector('[data-id="toggle-visibility"]');
    this.$setLimitBtn = this.$toolbar.querySelector('[data-id="set-limit"]');
    this.$removeLimitBtn = this.$toolbar.querySelector('[data-id="remove-limit"]');
    this.$numberInput = this.$toolbar.querySelector('[data-id="custom-limit"]');

    this.$toolbar.addEventListener('click', async ({ target }) => {
      if (target.matches('button[type="button"]')) {
        await this.onAction(target.dataset.id);
      }
    });

    this.$numberInput?.addEventListener('change', async () => {
      await this.onAction('change-limit');
    });
  }

  /**
   * Handle actions triggered by toolbar buttons or inputs.
   * @param {string} action The action identifier.
   */
  async onAction(action) {
    // Get current values
    let maxDepth = Number(this.data.maxDepth || this.realDepth);
    let hideResolved = this.data.hideResolved === '1';

    const removeLimit = () => {
      maxDepth = 0;
      this.$numberInput.value = this.realDepth;
    };

    // Adjust parameters based on which button was clicked
    switch (action) {
      case 'toggle-visibility':
        hideResolved = !hideResolved;

        break;
      case 'set-limit':
        maxDepth = 1;
        this.$numberInput.value = 1;

        break;
      case 'remove-limit':
        removeLimit();

        break;
      case 'change-limit':
        maxDepth = Number(this.$numberInput?.value || this.realDepth);

        if (maxDepth === this.realDepth) {
          removeLimit();
        }

        break;
    }

    await this.updateTrees({ maxDepth, hideResolved });
    this.updateControllers({ maxDepth, hideResolved });
  }

  /**
   * Error message to display when the dependency tree fails to load.
   */
  #UPDATE_TREES_ERROR_MESSAGE = '<p class="error">Failed to load the dependency tree.</p>';

  /**
   * Fetch and update the dependency tree HTML based on the given parameters, then inject it into
   * the page.
   * @param {object} params Parameters.
   * @param {number} params.maxDepth The maximum depth to show in the tree.
   * @param {boolean} params.hideResolved Whether to hide resolved bugs in the tree.
   */
  async updateTrees({ maxDepth, hideResolved }) {
    // Build params for fetch
    const params = new URLSearchParams({
      id: this.data.bugId,
      maxdepth: maxDepth,
      hide_resolved: hideResolved ? '1' : '0',
    });

    const url = `${this.data.action}?${params}`;

    // Set up a delayed loading indicator — only show after 300ms to avoid flicker on fast loads
    const loadingTimeout = setTimeout(() => {
      this.$container.setAttribute('aria-busy', 'true');
    }, 300);

    try {
      const response = await fetch(`${url}&embed=1&tree_only=1`);
      const html = response.ok ? await response.text() : undefined;

      // Safe to inject HTML as is: same-origin fetch, Template Toolkit escapes all user-supplied data
      this.$container.innerHTML = html ?? this.#UPDATE_TREES_ERROR_MESSAGE;
    } catch {
      this.$container.innerHTML = this.#UPDATE_TREES_ERROR_MESSAGE;
    } finally {
      // Cancel the loading timeout if it hasn’t fired yet
      clearTimeout(loadingTimeout);
      // Remove the loading state if it was set
      this.$container.removeAttribute('aria-busy');
    }

    // Update the URL query parameters if we’re on the dependency tree page
    if (location.pathname === this.data.action) {
      history.replaceState(null, '', url);
    }
  }

  /**
   * Update the state of the toolbar buttons and inputs based on the current parameters.
   * @param {object} params Parameters.
   * @param {number} params.maxDepth The maximum depth to show in the tree.
   * @param {boolean} params.hideResolved Whether to hide resolved bugs in the tree.
   */
  updateControllers({ maxDepth, hideResolved }) {
    // Update dataset properties used as state
    this.data.maxDepth = maxDepth;
    this.data.hideResolved = hideResolved ? '1' : '0';

    // Update button states
    this.$toggleBtn.textContent = hideResolved ? 'Show Resolved' : 'Hide Resolved';
    this.$setLimitBtn.disabled = this.realDepth < 2 || maxDepth === 1;
    this.$removeLimitBtn.disabled = maxDepth === 0 || maxDepth === this.realDepth;
  }

  /**
   * Attach event listeners to the tree items to handle expanding/collapsing and highlighting
   * duplicates. Use event delegation to handle events on dynamically updated tree items.
   */
  activateTrees() {
    this.$trees.addEventListener('click', (event) => this.onClick(event));

    const onHover = (event) => this.onHover(event);

    this.$trees.addEventListener('mouseenter', onHover, { capture: true });
    this.$trees.addEventListener('mouseleave', onHover, { capture: true });
  }

  /**
   * Handle click events on the tree items. This includes expanding/collapsing tree items and
   * highlighting duplicates.
   * @param {MouseEvent} event `click` event.
   */
  onClick(event) {
    if (event.target.matches('.view-list-link')) {
      const { href, target } = event.target;

      // If the URL is too long, submit it via POST to avoid hitting server limits
      if (href.length > this.uriLimit) {
        event.preventDefault();
        this.submitForm({ href, target });
      }
    }

    if (event.target.matches('.expander')) {
      this.toggleTreeItem(event);
    }

    if (event.target.matches('.duplicate-highlighter')) {
      this.highlightDuplicates(event);
    }
  }

  /**
   * Highlight or remove highlights on duplicated tree items when the user hovers over the bug link
   * in the summary.
   * @param {MouseEvent} event `mouseenter` or `mouseleave` event.
   */
  onHover(event) {
    if (event.target.matches('.summary.duplicated .bug-link')) {
      this.highlightDuplicates(event);
    }
  }

  /**
   * Create and submit a hidden form with the given parameters to avoid hitting server limits for
   * long URLs when the user clicks the “View List” link in the tree.
   * @param {object} params Parameters.
   * @param {string} params.href The URL to submit the form to.
   * @param {string} params.target The target attribute for the form submission.
   */
  submitForm({ href, target }) {
    const { origin, pathname, searchParams } = new URL(href);

    const getInput = (name, value) =>
      Object.assign(document.createElement('input'), { type: 'hidden', name, value });

    const $form = Object.assign(document.createElement('form'), {
      method: 'POST',
      action: origin + pathname,
      target,
    });

    $form.appendChild(getInput('bug_id', searchParams.get('bug_id')));

    if (searchParams.get('tweak') === '1') {
      $form.appendChild(getInput('tweak', '1'));
    }

    document.body.appendChild($form);
    $form.submit();
    $form.remove();
  }

  /**
   * Expand or collapse one or more tree items.
   * @param {MouseEvent} event `click` event.
   */
  toggleTreeItem(event) {
    const { target, altKey, ctrlKey, metaKey, shiftKey } = event;
    const $item = target.closest('[role="treeitem"]');
    const expanded = $item.matches('[aria-expanded="false"]');
    const accelKey = navigator.platform === 'MacIntel' ? metaKey && !ctrlKey : ctrlKey;

    $item.setAttribute('aria-expanded', expanded);

    // Do the same for the subtrees if the Ctrl/Command key is pressed
    if (accelKey && !altKey && !shiftKey) {
      $item.querySelectorAll('[role="treeitem"]').forEach(($child) => {
        $child.setAttribute('aria-expanded', expanded);
      });
    }
  }

  /**
   * Highlight one or more duplicated tree items.
   * @param {MouseEvent} event `click`, `mouseenter` or `mouseleave` event.
   */
  highlightDuplicates(event) {
    const { target, type } = event;
    const id = Number(target.closest('[role="treeitem"]').dataset.id);
    const pressed = type === 'click' ? target.matches('[aria-pressed="false"]') : undefined;
    const $tree = target.closest('[role="tree"]');
    const { highlighted } = $tree.dataset;

    if (type.startsWith('mouse') && highlighted) {
      return;
    }

    if (type === 'click') {
      if (highlighted) {
        // Remove existing highlights
        $tree.querySelectorAll(`[role="treeitem"][data-id="${highlighted}"]`).forEach(($item) => {
          $item.querySelector('.duplicate-highlighter')?.setAttribute('aria-pressed', 'false');
          $item.querySelector('.summary').classList.remove('highlight');
        });
      }

      target.setAttribute('aria-pressed', pressed);
      $tree.dataset.highlighted = pressed ? id : '';
    }

    $tree.querySelectorAll(`[role="treeitem"][data-id="${id}"]`).forEach(($item, index) => {
      $item.querySelector('.summary').classList.toggle('highlight', pressed);

      if (index === 0 && pressed) {
        $item.scrollIntoView();
      }
    });
  }
};

window.addEventListener(
  'DOMContentLoaded',
  () => {
    new Bugzilla.DependencyTree();
  },
  { once: true },
);
