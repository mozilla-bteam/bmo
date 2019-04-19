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
 * Implement Custom Search features.
 */
Bugzilla.CustomSearch = class CustomSearch {
  /**
   * Initialize a new CustomSearch instance.
   */
  constructor() {
    this.data = Bugzilla.CustomSearch.data = { group_count: 0, row_count: 0 };
    this.$container = document.querySelector('#custom-search');

    // Decode and store required data
    Object.entries(this.$container.dataset).forEach(([key, value]) => this.data[key] = JSON.parse(value));

    this.restore();

    this.$container.addEventListener('change', () => this.save_state());
    this.$container.addEventListener('CustomSearch:ItemAdded', () => this.update_input_names());
    this.$container.addEventListener('CustomSearch:ItemRemoved', () => this.update_input_names());
    this.$container.addEventListener('CustomSearch:ItemMoved', () => this.remove_empty_group());
    this.$container.addEventListener('CustomSearch:DragStarted', event => this.enable_drop_targets(event));
    this.$container.addEventListener('CustomSearch:DragEnded', () => this.disable_drop_targets());
  }

  /**
   * Add rows and groups specified with the URL query or history state.
   */
  restore() {
    const state = history.state || {};
    const { j_top, conditions } = state.default || this.data.default;
    const groups = [];
    let level = 0;

    groups.push(new Bugzilla.CustomSearch.Group({ j: j_top, is_top: true, add_empty_row: !conditions.length }));
    groups[0].render(this.$container);

    // Use `let` to work around test failures on Firefox 47 (Bug 1101653)
    // eslint-disable-next-line prefer-const
    for (let condition of conditions) {
      // Skip empty conditions
      if (!condition || !condition.f) {
        continue;
      }

      // Stop if the condition is invalid (due to any extra CP)
      if (level < 0) {
        break;
      }

      if (condition.f === 'OP') {
        groups[level + 1] = groups[level].add_group(condition);
        level++;
      } else if (condition.f === 'CP') {
        level--;
      } else {
        groups[level].add_row(condition);
      }
    }

    this.update_input_names();
  }

  /**
   * Update the `name` attribute on all the `<input>` elements when a row or group is added, removed or moved.
   */
  update_input_names() {
    let index = 1;
    let cp_index = 0;

    // Cache radio button state, which can be reset while renaming
    const radio_states =
      new Map([...this.$container.querySelectorAll('input[type="radio"]')].map(({ id, checked }) => [id, checked]));

    // Use spread syntax to work around test failures on Firefox 47. `NodeList.forEach` was added to Firefox 50
    [...this.$container.querySelectorAll('.group.top .condition')].forEach($item => {
      if ($item.matches('.group')) {
        cp_index = index + $item.querySelectorAll('.row').length + ($item.querySelectorAll('.group').length * 2) + 1;
      }

      [...$item.querySelectorAll('[name]')].filter($input => $input.closest('.condition') === $item).forEach($input => {
        $input.name = $input.value === 'CP' ? `f${cp_index}` : `${$input.name.charAt(0)}${index}`;
      });

      index++;

      if (index === cp_index) {
        index++;
      }
    });

    // Restore radio button state
    radio_states.forEach((checked, id) => document.getElementById(id).checked = checked);

    this.save_state();
  }

  /**
   * Save the current search conditions in the browser history, so these rows and groups can be restored after the user
   * reloads or navigates back to the page, just like native static form widgets.
   */
  save_state() {
    const form_data = new FormData(this.$container.closest('form'));
    const conditions = [];

    // eslint-disable-next-line prefer-const
    for (let [name, value] of form_data.entries()) {
      const [, key, index] = name.match(/^([njfov])(\d+)$/) || [];

      if (key) {
        conditions[index] = Object.assign(conditions[index] || {}, { [key]: value });
      }
    }

    history.replaceState({ default: { j_top: form_data.get('j_top'), conditions } }, document.title, document.URL);
  }

  /**
   * Remove any empty group when a row or group is moved.
   */
  remove_empty_group() {
    this.$container.querySelectorAll('.group').forEach($group => {
      if (!$group.querySelector('.condition') && !$group.matches('.top')) {
        $group.previousElementSibling.remove(); // drop target
        $group.remove();
      }
    });

    this.update_input_names();
  }

  /**
   * Enable drop targets between conditions when drag action is started.
   * @param {DragEvent} event `dragstart` event.
   */
  enable_drop_targets(event) {
    const $source = document.getElementById(event.detail.id);

    this.$container.querySelectorAll('.drop-target').forEach($target => {
      // A group cannot be moved into itself, and targets above/below the source should be disabled
      if (!$source.contains($target) &&
          $source.previousElementSibling !== $target && $source.nextElementSibling !== $target) {
        $target.setAttribute('aria-dropeffect', 'move');
      }
    });
  }

  /**
   * Disable drop targets between conditions when drag action is ended.
   */
  disable_drop_targets() {
    this.$container.querySelectorAll('[aria-dropeffect]').forEach($target => {
      $target.removeAttribute('aria-dropeffect');
    });
  }
};

/**
 * Implement a Custom Search condition features shared by rows and groups.
 * @abstract
 */
Bugzilla.CustomSearch.Condition = class CustomSearchCondition {
  /**
   * Add a group or row to the given element.
   * @param {HTMLElement} $parent Parent node for the element.
   */
  render($parent) {
    $parent.appendChild(this.$element);
  }

  /**
   * Remove a group or row from view.
   */
  remove() {
    this.$element.remove();

    document.querySelector('#custom-search').dispatchEvent(
      new CustomEvent('CustomSearch:ItemRemoved', { detail: { id: this.id } }));
  }

  /**
   * Enable drag action.
   */
  enable_drag() {
    this.$element.draggable = true;
    this.$element.setAttribute('aria-grabbed', 'true');
    this.$action_grab.setAttribute('aria-pressed', 'true');
  }

  /**
   * Disable drag action.
   */
  disable_drag() {
    this.$element.draggable = false;
    this.$element.setAttribute('aria-grabbed', 'false');
    this.$action_grab.setAttribute('aria-pressed', 'false');
  }

  /**
   * Handle drag events at the source, which is a row or group.
   * @param {DragEvent} event One of drag-related events.
   */
  handle_drag(event) {
    event.stopPropagation();

    if (event.type === 'dragstart') {
      event.dataTransfer.setData('application/x-cs-condition', this.$element.id);
      event.dataTransfer.dropEffect = event.dataTransfer.effectAllowed = 'move';

      document.querySelector('#custom-search').dispatchEvent(
        new CustomEvent('CustomSearch:DragStarted', { detail: { id: this.id } }));
    }

    if (event.type === 'dragend') {
      this.disable_drag();

      document.querySelector('#custom-search').dispatchEvent(
        new CustomEvent('CustomSearch:DragEnded', { detail: { id: this.id } }));
    }
  }
};

/**
 * Implement a Custom Search group.
 */
Bugzilla.CustomSearch.Group = class CustomSearchGroup extends Bugzilla.CustomSearch.Condition {
  /**
   * Initialize a new CustomSearchGroup instance.
   * @param {Boolean} [n] Whether to use NOT.
   * @param {String} [j] How to join: AND or OR.
   * @param {Boolean} [is_top] Whether this is the topmost group within the custom search container.
   * @param {Boolean} [add_empty_row] Whether to add an empty new row to the condition area by default.
   */
  constructor({ n = false, j = 'AND', is_top = false, add_empty_row = false } = {}) {
    super();

    const $placeholder = document.createElement('div');
    const { data } = Bugzilla.CustomSearch;
    const { strings: str } = data;
    const count = ++data.group_count;
    const id = this.id = `group-${count}`;

    $placeholder.innerHTML = `
      <section role="group" id="${id}" class="condition group ${is_top ? 'top' : ''}" draggable="false"
          aria-grabbed="false" aria-label="${str.group_name.replace('{ $count }', count)}">
        ${is_top ? '' : '<input type="hidden" name="f0" value="OP">'}
        <header role="toolbar">
          ${is_top ? '' : `
            <button type="button" class="iconic" aria-label="${str.grab}" data-action="grab">
              <span class="icon" aria-hidden="true"></span>
            </button>
            <label><input type="checkbox" name="n0" value="1" ${n ? 'checked' : ''}> ${str.not}</label>
          `}
          <div class="match">
            <div role="radiogroup" class="buttons toggle">
              <div class="item">
                <input id="${id}-join-r1" type="radio" name="${is_top ? 'j_top' : 'j0'}" value="AND"
                  ${j !== 'OR' ? 'checked' : ''}>
                <label for="${id}-join-r1">${str.match_all}</label>
              </div>
              <div class="item">
                <input id="${id}-join-r2" type="radio" name="${is_top ? 'j_top' : 'j0'}" value="OR"
                  ${j === 'OR' ? 'checked' : ''}>
                <label for="${id}-join-r2">${str.match_any}</label>
              </div>
            </div>
          </div>
          ${is_top ? '' : `
            <button type="button" class="iconic" aria-label="${str.remove}" data-action="remove">
              <span class="icon" aria-hidden="true"></span>
            </button>
          `}
        </header>
        <div class="conditions"></div>
        <footer role="toolbar">
          <button type="button" class="minor iconic-text" data-action="add-group" aria-label="${str.add_group}">
            <span class="icon" aria-hidden="true"></span> ${str.group}
          </button>
          <button type="button" class="minor iconic-text" data-action="add-row" aria-label="${str.add_row}">
            <span class="icon" aria-hidden="true"></span> ${str.criteria}
          </button>
        </footer>
        ${is_top ? '' : '<input type="hidden" name="f2" value="CP">'}
      </section>
    `;

    this.$element = $placeholder.firstElementChild;
    this.$conditions = this.$element.querySelector('.conditions');
    this.$action_grab = this.$element.querySelector('[data-action="grab"]');
    this.$action_remove = this.$element.querySelector('[data-action="remove"]');
    this.$action_add_group = this.$element.querySelector('[data-action="add-group"]');
    this.$action_add_row = this.$element.querySelector('[data-action="add-row"]');

    this.$element.addEventListener('dragstart', event => this.handle_drag(event));
    this.$element.addEventListener('dragend', event => this.handle_drag(event));
    this.$action_add_group.addEventListener('click', () => this.add_group({ add_empty_row: true }));
    this.$action_add_row.addEventListener('click', () => this.add_row());

    if (!is_top) {
      this.$action_grab.addEventListener('mousedown', () => this.enable_drag());
      this.$action_grab.addEventListener('mouseup', () => this.disable_drag());
      this.$action_remove.addEventListener('click', () => this.remove());
    }

    this.add_drop_target();

    if (add_empty_row) {
      this.add_row();
    }
  }

  /**
   * Add a new child group to the condition area.
   * @param {Object} [conditions] Search conditions.
   * @returns {CustomSearchGroup} New group object.
   */
  add_group(conditions = {}) {
    const group = new Bugzilla.CustomSearch.Group(conditions);

    group.render(this.$conditions);
    this.add_drop_target();

    document.querySelector('#custom-search').dispatchEvent(
      new CustomEvent('CustomSearch:ItemAdded', { detail: { type: 'group', id: group.id, conditions } }));

    return group;
  }

  /**
   * Add a new child row to the condition area.
   * @param {Object} [conditions] Search conditions.
   * @returns {CustomSearchRow} New row object.
   */
  add_row(conditions = {}) {
    const row = new Bugzilla.CustomSearch.Row(conditions);

    row.render(this.$conditions);
    this.add_drop_target();

    document.querySelector('#custom-search').dispatchEvent(
      new CustomEvent('CustomSearch:ItemAdded', { detail: { type: 'row', id: row.id, conditions } }));

    return row;
  }

  /**
   * Add a new drop target to the condition area.
   */
  add_drop_target() {
    (new Bugzilla.CustomSearch.DropTarget()).render(this.$conditions);
  }
};

/**
 * Implement a Custom Search row.
 */
Bugzilla.CustomSearch.Row = class CustomSearchRow extends Bugzilla.CustomSearch.Condition {
  /**
   * Initialize a new CustomSearchRow instance.
   * @param {Boolean} [n] Whether to use NOT.
   * @param {String} [f] Field name to be selected in the dropdown list.
   * @param {String} [o] Operator name to be selected in the dropdown list.
   * @param {String} [v] Field value.
   */
  constructor({ n = false, f = 'noop', o = 'noop', v = '' }) {
    super();

    const $placeholder = document.createElement('div');
    const { data } = Bugzilla.CustomSearch;
    const { strings: str, fields, types } = data;
    const count = ++data.row_count;
    const id = this.id = `row-${count}`;

    $placeholder.innerHTML = `
      <div role="group" id="${id}" class="condition row" draggable="false" aria-grabbed="false"
          aria-label="${str.row_name.replace('{ $count }', count)}">
        <button type="button" class="iconic" aria-label="${str.grab}" aria-pressed="false" data-action="grab">
          <span class="icon" aria-hidden="true"></span>
        </button>
        <label><input type="checkbox" name="n1" value="1" ${n ? 'checked' : ''}> ${str.not}</label>
        <select name="f1" aria-label="${str.field}">
          ${fields.map(({ value, label }) => `
            <option value="${value.htmlEncode()}" ${f === value ? 'selected' : ''}>${label.htmlEncode()}</option>
          `).join('')}
        </select>
        <select name="o1" aria-label="${str.operator}">
          ${types.map(({ value, label }) => `
            <option value="${value.htmlEncode()}" ${o === value ? 'selected' : ''}>${label.htmlEncode()}</option>
          `).join('')}
        </select>
        <input type="text" name="v1" value="${v.htmlEncode()}" aria-label="${str.value}">
        <button type="button" class="iconic" aria-label="${str.remove}" data-action="remove">
          <span class="icon" aria-hidden="true"></span>
        </button>
      </div>
    `;

    this.$element = $placeholder.firstElementChild;
    this.$action_grab = this.$element.querySelector('[data-action="grab"]');
    this.$action_remove = this.$element.querySelector('[data-action="remove"]');

    this.$element.addEventListener('dragstart', event => this.handle_drag(event));
    this.$element.addEventListener('dragend', event => this.handle_drag(event));
    this.$action_grab.addEventListener('mousedown', () => this.enable_drag());
    this.$action_grab.addEventListener('mouseup', () => this.disable_drag());
    this.$action_remove.addEventListener('click', () => this.remove());
  }
};

/**
 * Implement a Custom Search drop target.
 */
Bugzilla.CustomSearch.DropTarget = class CustomSearchDropTarget {
  /**
   * Initialize a new CustomSearchDropTarget instance.
   */
  constructor() {
    const $placeholder = document.createElement('div');

    $placeholder.innerHTML = `
      <div role="separator" class="drop-target">
        <div class="indicator"></div>
      </div>
    `;

    this.$element = $placeholder.firstElementChild;

    this.$element.addEventListener('dragenter', event => this.handle_drag(event));
    this.$element.addEventListener('dragover', event => this.handle_drag(event));
    this.$element.addEventListener('dragleave', event => this.handle_drag(event));
    this.$element.addEventListener('drop', event => this.handle_drag(event));
  }

  /**
   * Add a drop target to the given element.
   * @param {HTMLElement} $parent Parent node for the element.
   */
  render($parent) {
    $parent.appendChild(this.$element);
  }

  /**
   * Handle drag events at the target.
   * @param {DragEvent} event One of drag-related events.
   */
  handle_drag(event) {
    if (!this.$element.matches('[aria-dropeffect]')) {
      return;
    }

    if (event.type === 'dragenter') {
      this.$element.classList.add('dragover');
    }

    if (event.type === 'dragover') {
      event.preventDefault();
    }

    if (event.type === 'dragleave') {
      this.$element.classList.remove('dragover');
    }

    if (event.type === 'drop') {
      event.preventDefault();

      const source_id = event.dataTransfer.getData('application/x-cs-condition');
      const $source = document.getElementById(source_id);

      this.$element.classList.remove('dragover');
      this.$element.insertAdjacentElement('beforebegin', $source.previousElementSibling); // drop target
      this.$element.insertAdjacentElement('beforebegin', $source);

      document.querySelector('#custom-search').dispatchEvent(
        new CustomEvent('CustomSearch:ItemMoved', { detail: { id: source_id } }));
    }
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.CustomSearch(), { once: true });
