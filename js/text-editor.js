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
 * Implement an enhanced text editor featuring preview and Markdown support.
 */
Bugzilla.TextEditor = class TextEditor {
  /**
   * Initialize a new TextEditor instance.
   * @param {Object} [options] Options for the instance.
   * @param {HTMLTextAreaElement} [options.$textarea] Existing plain `<textarea>` to be replaced with the text editor.
   * If omitted, a new `<textarea>` is created within the editor.
   * @param {Boolean} [options.use_markdown] Whether to use the Markdown features.
   * @param {String} [options.initial_text] Initial text content used to detect if the text is edited.
   */
  constructor({ $textarea = undefined, use_markdown = true, initial_text = '' } = {}) {
    this.id = `text-editor-${Bugzilla.String.generate_hash()}`;
    this.str = BUGZILLA.string.TextEditor;
    this.use_markdown = use_markdown;
    this.initial_text = initial_text;

    this.$container = this.create_container();
    this.$tablist = this.$container.querySelector('[role="tablist"]');
    this.$edit_tab = this.$container.querySelector('[role="tab"][data-command="edit"]');
    this.$edit_tabpanel = this.$container.querySelector('[role="tabpanel"][data-id="edit"]');
    this.$preview_tab = this.$container.querySelector('[role="tab"][data-command="preview"]');
    this.$preview_tabpanel = this.$container.querySelector('[role="tabpanel"][data-id="preview"]');
    this.$toolbar = this.$container.querySelector('[role="toolbar"]');
    this.$textarea = $textarea || this.$edit_tabpanel.appendChild(document.createElement('textarea'));
    this.$preview = this.$container.querySelector('.comment-text');

    new Bugzilla.Tabs(this.$tablist);

    this.$tablist.addEventListener('select', event => this.tablist_onselect(event));
    this.$textarea.addEventListener('input', event => this.textarea_oninput(event));

    this.toggle_preview_tab();

    if (this.use_markdown) {
      this.$toolbar.querySelectorAll('[role="button"]').forEach($button => {
        new Bugzilla.Button($button, event => this.button_onclick(event));
      });

      Bugzilla.Event.enable_keyshortcuts(this.$textarea, {
        'Accel+B': () => this.exec_command('bold'),
        'Accel+I': () => this.exec_command('italic'),
        'Accel+K': () => this.exec_command('link'),
      });
    }
  }

  /**
   * Create a container element in HTML.
   * @returns {HTMLElement} Created element.
   */
  create_container() {
    const $placeholder = document.createElement('div');
    const accel = Bugzilla.UA.is_mac ? '\u2318' : 'Ctrl+';
    const _ = key => this.str[key].htmlEncode();

    $placeholder.innerHTML = `
      <section role="group" id="${this.id}" class="text-editor" aria-label="${_('container_label')}">
        <header>
          <div role="tablist">
            <label role="tab" tabindex="0" data-command="edit" aria-selected="true"
                aria-controls="${this.id}-tabpanel-edit">${_('edit')}</label>
            <label role="tab" tabindex="-1" data-command="preview" aria-disabled="true"
                aria-controls="${this.id}-tabpanel-preview">${_('preview')}</label>
          </div>
          ${this.use_markdown ? `
          <div role="toolbar" class="markdown-toolbar" aria-label="${_('toolbar_label')}">
            <div class="group">
              <label role="button" tabindex="0" class="minor iconic" title="${_('command_heading')}"
                  data-command="heading"><span class="icon" aria-hidden="true"></span></label>
              <label role="button" tabindex="0" class="minor iconic" title="${_('command_bold')} (${accel}B)"
                  data-command="bold"><span class="icon" aria-hidden="true"></span></label>
              <label role="button" tabindex="0" class="minor iconic" title="${_('command_italic')} (${accel}I)"
                  data-command="italic"><span class="icon" aria-hidden="true"></span></label>
            </div>
            <div class="group">
              <label role="button" tabindex="0" class="minor iconic" title="${_('command_quote')}"
                  data-command="quote"><span class="icon" aria-hidden="true"></span></label>
              <label role="button" tabindex="0" class="minor iconic" title="${_('command_code')}"
                  data-command="code"><span class="icon" aria-hidden="true"></span></label>
              <label role="button" tabindex="0" class="minor iconic" title="${_('command_link')} (${accel}K)"
                  data-command="link"><span class="icon" aria-hidden="true"></span></label>
            </div>
            <div class="group">
              <label role="button" tabindex="0" class="minor iconic" title="${_('command_bulleted_list')}"
                  data-command="bulleted-list"><span class="icon" aria-hidden="true"></span></label>
              <label role="button" tabindex="0" class="minor iconic" title="${_('command_numbered_list')}"
                  data-command="numbered-list"><span class="icon" aria-hidden="true"></span></label>
            </div>
          </div>
          ` : ''}
        </header>
        <div role="tabpanel" id="${this.id}-tabpanel-edit" data-id="edit"></div>
        <div role="tabpanel" id="${this.id}-tabpanel-preview" data-id="preview" hidden>
          <div class="comment-text ${this.use_markdown ? 'markdown-body' : ''}"></div>
        </div>
        <footer class="comment-tips" hidden>
          <div>
            <a href="${BUGZILLA.config.basepath}page.cgi?id=etiquette.html" target="_blank">${_('etiquette')}</a>
          </div>
          ${this.use_markdown ? `
          <div class="markdown-help">
            <a href="https://guides.github.com/features/mastering-markdown/" target="_blank"
                class="iconic">${_('markdown_supported')}</a>
          </div>
          ` : ''}
        </footer>
      </section>
    `;

    return $placeholder.firstElementChild;
  }

  /**
   * Check if the text is edited. Ignore leading/trailing white space(s) and/or additional empty line(s) while
   * comparing the changes.
   * @private
   * @readonly
   * @type {Boolean}
   */
  get edited() {
    if (this.initial_text) {
      return this.$textarea.value.trim() !== this.initial_text.trim();
    }

    return !!this.$textarea.value.match(/\S/);
  }

  /**
   * Called whenever a tab is selected. Trigger a relevant action.
   * @param {CustomEvent} event `select` event.
   */
  tablist_onselect(event) {
    const { original_event, $new_tab } = event.detail;

    if ($new_tab.matches('[data-command="edit"]')) {
      if (this.$toolbar) {
        this.$toolbar.hidden = false;
      }

      if (original_event.type === 'click') {
        this.$textarea.focus();
      }
    }

    if ($new_tab.matches('[data-command="preview"]')) {
      if (this.$toolbar) {
        this.$toolbar.hidden = true;
      }

      this.preview();
    }
  }

  /**
   * Called whenever a toolbar button is pressed. Trigger a command specified on the button.
   * @param {(MouseEvent|KeyboardEvent)} event `click` or `keydown` event.
   */
  button_onclick(event) {
    this.exec_command(event.target.dataset.command);

    if (event.type === 'click') {
      this.$textarea.focus();
    }
  }

  /**
   * Called whenever the `<textarea>` is edited. Disable the Preview tab if needed.
   * @param {KeyboardEvent} event `input` event.
   */
  textarea_oninput(event) {
    if (event.isComposing) {
      return;
    }

    this.toggle_preview_tab();
  }

  /**
   * Enable or disable the Preview tab depending on the content, usually when it's empty.
   */
  toggle_preview_tab() {
    const disabled = !this.edited;

    this.$preview_tab.setAttribute('aria-disabled', !this.edited);
    this.$preview_tab.tabIndex = disabled ? -1 : 0;
  }

  /**
   * Get information related to the selected text in the `<textarea>`.
   * @returns {Object} Selection range and relevant information.
   */
  get_selection() {
    const { value: text, selectionStart: start, selectionEnd: end } = this.$textarea;
    const selection = text.substring(start, end);
    const lines = selection.split(/\n/);

    return {
      start,
      end,
      selection,
      before: text.substring(0, start),
      after: text.substring(end),
      lines,
      multiline: lines.length > 1,
      any_chars: '[\\s\\S]*', // Include line breaks
    };
  }

  /**
   * Update the text in the `<textarea>`.
   * @param {String} text Updated text content.
   * @param {Number} [start] New selection start position.
   * @param {Number} [end] New selection end position.
   */
  update_text(text, start, end) {
    this.$textarea.value = text;

    if (start !== undefined) {
      this.$textarea.setSelectionRange(start, end || start);
    }

    // Fire an event to resize the `<textarea>` if needed
    this.$textarea.dispatchEvent(new InputEvent('input'));
  }

  /**
   * Insert a Markdown link to the `<textarea>`, or remove an existing link.
   */
  insert_link() {
    const { start, end, selection, before, after, any_chars } = this.get_selection();
    const before_match = before.match(new RegExp(`^(${any_chars})\\[$`));
    const after_match = after.match(new RegExp(`^\\]\\(url\\)(${any_chars})$`));

    if (before_match && after_match) {
      // Remove markup outside of the selection
      this.update_text(`${before_match[1]}${selection}${after_match[1]}`, start - 1, end - 1);
    } else if (selection.match(/^(https?|mailto):/) || !selection) {
      // Convert any URL to a markup, and let the user enter the label
      this.update_text(`${before}[](${selection || 'url'})${after}`, start + 1);
    } else {
      // Convert any label to a markup, and let the user enter the URL
      this.update_text(`${before}[${selection}](url)${after}`, end + 3, end + 6);
    }
  }

  /**
   * Insert an inline Markdown markup to the `<textarea>`, or remove an existing markup.
   * @param {String} mark Character(s) to be added before and after any selected text, e.g. "**" for bold text.
   */
  insert_inline_markup(mark) {
    const { start, end, selection, before, after, any_chars } = this.get_selection();
    const escaped_mark = Bugzilla.RegExp.escape(mark);
    const before_match = before.match(new RegExp(`^(${any_chars})${escaped_mark}$`));
    const after_match = after.match(new RegExp(`^${escaped_mark}(${any_chars})$`));
    const inside_match = selection.match(new RegExp(`^${escaped_mark}(${any_chars})${escaped_mark}$`));

    if (before_match && after_match) {
      // Remove markup outside of the selection
      this.update_text(`${before_match[1]}${selection}${after_match[1]}`, start - mark.length, end - mark.length);
    } else if (inside_match) {
      // Remove markup inside of the selection
      this.update_text(`${before}${inside_match[1]}${after}`, start, end - (mark.length * 2));
    } else {
      // Add markup
      this.update_text(`${before}${mark}${selection}${mark}${after}`, start + mark.length, end + mark.length);
    }
  };

  /**
   * Insert a block Markdown markup to the `<textarea>`, or remove an existing markup.
   * @param {String} mark Character(s) to be added at the beginning of each line, e.g. "*" for a bulleted list.
   */
  insert_block_markup(mark) {
    const { start, selection, before, after, lines } = this.get_selection();
    const is_numbered = mark === '1.';
    const line_re = new RegExp(`^${is_numbered ? '\\d+\\.' : Bugzilla.RegExp.escape(mark)}\\ (.*)`);
    const _before = before.replace(/\n{1,2}$/, '');
    const _after = after.replace(/^\n{1,2}/, '');

    if (lines.every(line => line.match(line_re))) {
      // Remove markup from each line inside of the selection
      const text = lines.map(line => line.match(line_re)[1]).join('\n');

      this.update_text(`${before}${text}${after}`, start, start + text.length);
    } else if (selection) {
      // Add markup to each line inside of the selection
      const text = lines.map((line, i) => `${is_numbered ? `${i + 1}.`: mark} ${line}`).join('\n');
      const _start = _before.length + (_before ? 2 : 0);

      this.update_text(`${_before}${_before ? '\n\n' : ''}${text}${_after ? '\n\n' : ''}${_after}`,
        _start, _start + text.length);
    } else {
      // Add markup to new line
      this.update_text(`${_before}${_before ? '\n\n' : ''}${mark} ${_after ? '\n\n' : ''}${_after}`,
        _before.length + (_before ? 2 : 0) + mark.length + 1);
    }
  };

  /**
   * Insert a code fencing block to the `<textarea>`, or remove an existing markup.
   */
  insert_code_fencing() {
    const { start, end, before, after, selection, any_chars } = this.get_selection();
    const escaped_mark = Bugzilla.RegExp.escape('```');
    const before_match = before.match(new RegExp(`^(${any_chars}\n)?(${escaped_mark}\n)$`));
    const after_match = after.match(new RegExp(`^(\n?${escaped_mark})(\n${any_chars})?$`));
    const inside_match = selection.match(new RegExp(`^${escaped_mark}\n(${any_chars})\n${escaped_mark}$`));

    if (before_match && after_match) {
      // Remove markup outside of the selection
      this.update_text(`${before_match[1] || ''}${selection}${after_match[2] || ''}`,
        start - before_match[2].length, end - after_match[1].length);
    } else if (inside_match) {
      // Remove markup inside of the selection
      this.update_text(`${before}${inside_match[1]}${after}`, start, end - (mark.length * 2) - 2);
    } else {
      // Wrap the selection with the markup
      const _before = before.replace(/\n{1,2}$/, '');
      const _after = after.replace(/^\n{1,2}/, '');
      const _selection = selection.replace(/\n$/, '');
      const _start = _before.length + (_before ? 2 : 0);

      this.update_text(
        `${_before}${_before ? '\n\n' : ''}${mark}\n${_selection}\n${mark}${_after ? '\n\n' : ''}${_after}`,
        _start, _start + _selection.length + (mark.length * 2) + 2);
    }
  };

  /**
   * Execute a command on the `<textarea>`.
   * @param {String} command Command name like `bold`.
   */
  exec_command(command) {
    const { multiline } = this.get_selection();

    const action = {
      'heading': () => this.insert_block_markup('###'),
      'bold': () => this.insert_inline_markup('**'),
      'italic': () => this.insert_inline_markup('_'),
      'quote': () => this.insert_block_markup('>'),
      'code': () => (multiline ? this.insert_code_fencing() : this.insert_inline_markup('`')),
      'link': () => this.insert_link(),
      'bulleted-list': () => this.insert_block_markup('*'),
      'numbered-list': () => this.insert_block_markup('1.'),
    }[command];

    if (action) {
      action();
    }
  }

  /**
   * Called whenever the Preview tab is clicked. Fetch and display the rendered text if it's edited.
   */
  async preview() {
    if (this.$textarea.value === this.last_previewed_text) {
      return;
    }

    // Copy the current height: the tabpanel should be visible to get the `scrollHeight` property
    this.$edit_tabpanel.hidden = false;
    this.$preview.style.setProperty('height', `${this.$textarea.scrollHeight}px`);
    this.$edit_tabpanel.hidden = true;

    this.$preview.focus();
    this.$preview.setAttribute('aria-busy', 'true');

    this.$preview.innerHTML = `<p role="status">${this.str.loading.htmlEncode()}</p>`;

    try {
      const { html } = await Bugzilla.API.post('bug/comment/render', { text: this.$textarea.value });

      // Use the HTML without `htmlEncode()` because it should be safe to be embedded as is
      this.$preview.innerHTML = html;

      // Highlight code if possible
      if (Prism) {
        Prism.highlightAllUnder(this.$preview);
      }

      this.$preview.setAttribute('aria-busy', 'false');
    } catch (ex) {
      this.$preview.innerHTML = `<p role="alert" class="error">${this.str.preview_error.htmlEncode()}</p>`;
      this.$preview.setAttribute('aria-busy', 'false');
    }

    this.last_previewed_text = this.$textarea.value;
  }
};

/**
 * Implement an enhanced comment editor that replaces a plain `<textarea>` found on bug pages.
 */
Bugzilla.CommentEditor = class CommentEditor extends Bugzilla.TextEditor {
  /**
   * Initialize a new CommentEditor instance.
   * @param {Object} [options] Options for the instance.
   * @param {HTMLTextAreaElement} [options.$textarea] Comment `<textarea>` to be replaced with the text editor.
   * @param {Boolean} [options.use_markdown] Whether to use the Markdown features.
   * @param {String} [options.initial_text] Initial text content used to detect if the text is edited.
   * @param {Boolean} [options.hide_tips] Whether to hide the tips below the `<textarea>`.
   */
  constructor({ $textarea = undefined, use_markdown = true, initial_text = '', hide_tips = false } = {}) {
    super({ $textarea, use_markdown, initial_text });

    this.$container.classList.add('comment-editor');
    this.$container.querySelector('footer.comment-tips').hidden = hide_tips;

    if (this.$textarea.hasAttribute('aria-label')) {
      this.$edit_tab.textContent = this.$textarea.getAttribute('aria-label');
    }

    if (this.$textarea.matches('#comment')) {
      this.$save_button = this.$textarea.form ? this.$textarea.form.querySelector('[type="submit"]') : undefined;

      if (this.$save_button) {
        Bugzilla.Event.enable_keyshortcuts(this.$textarea, {
          'Accel+Enter': () => this.submit_form(),
        });
      }

      Bugzilla.Event.enable_keyshortcuts(window, {
        'Ctrl+Shift+P': event => this.toggle_comment_preview(event),
      });
    }
  }

  /**
   * Replace the existing `<textarea>` with the enhanced comment editor.
   */
  render() {
    this.$textarea.insertAdjacentElement('afterend', this.$container);
    this.$edit_tabpanel.appendChild(this.$textarea);
  }

  /**
   * Submit the bug form if the comment is entered. Trigger a `click` event instead of submitting the form directly to
   * make sure any event handler associated with the button will be called.
   */
  submit_form() {
    if (this.edited) {
      this.$save_button.click();
    }
  }

  /**
   * Toggle the comment edit and preview tabs if possible.
   * @param {KeyboardEvent} event `keydown` event.
   */
  toggle_comment_preview(event) {
    event.preventDefault();

    if (this.edited) {
      if (this.$preview_tabpanel.hidden) {
        this.$preview_tab.click();
      } else {
        this.$edit_tab.click();
      }
    }
  }
};

window.addEventListener('DOMContentLoaded', () => {
  const $textarea = document.querySelector('#comment');

  if ($textarea) {
    (new Bugzilla.CommentEditor({ $textarea, use_markdown: BUGZILLA.param.use_markdown === '1' })).render();
  }
}, { once: true });
