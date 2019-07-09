/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

/**
 * Provide the inline comment editing functionality that allows to edit and update a comment on the bug page.
 */
Bugzilla.InlineCommentEditor = class InlineCommentEditor extends Bugzilla.CommentEditor {
  /**
   * Initialize a new InlineCommentEditor instance.
   * @param {HTMLElement} $change_set Comment outer.
   */
  constructor($change_set) {
    const $comment_body = $change_set.querySelector('.comment-text');

    super({ use_markdown: $comment_body.matches('.markdown-body'), hide_tips: true });

    this.str = Object.assign(this.str, BUGZILLA.string.InlineCommentEditor);
    this.comment_id = Number($change_set.querySelector('.comment').dataset.id);
    this.commenter_id = Number($change_set.querySelector('.email').dataset.userId);
    this.is_empty = $comment_body.matches('.empty');

    this.$change_set = $change_set;
    this.$comment_body = $comment_body;
    this.$edit_button = $change_set.querySelector('.edit-btn');
    this.$revisions_link = $change_set.querySelector('.change-revisions a');

    this.render();
    this.fetch();
  }

  /**
   * Insert the inline comment editor to a comment body part.
   */
  render() {
    this.toggle_comment_action_buttons(true);
    this.$comment_body.hidden = true;

    // Replace the comment body with a disabled `<textarea>` filled with the text as a placeholder while retrieving the
    // raw comment text. Also, provide a toolbar with the Save and Cancel buttons as well as the Hide This Revision
    // checkbox for admin. Allow to preview the edited comment
    this.$comment_body.insertAdjacentHTML('afterend',
      `
      <div role="group" class="inline-comment-editor">
        <div role="toolbar" class="bottom-toolbar" aria-label="${this.str.toolbar}">
          <span role="status"></span>
          ${BUGZILLA.user.is_insider && BUGZILLA.user.id !== this.commenter_id ? `<label>
            <input type="checkbox" value="on" checked data-command="hide"> ${this.str.hide_revision}</label>` : ''}
          <button type="button" class="secondary" data-command="cancel" title="${this.str.cancel_tooltip} (Esc)">
            ${this.str.cancel}
          </button>
          <button type="button" class="primary" disabled data-command="save"
                  title="${this.str.save_tooltip} (${Bugzilla.UA.is_mac ? '&#x2318;Return' : 'Ctrl+Enter'})">
            ${this.str.save}
          </button>
        </div>
      </div>
      `
    );

    this.$outer = this.$comment_body.nextElementSibling;
    this.$outer.insertAdjacentElement('afterbegin', this.$container);

    this.$save_button = this.$outer.querySelector('[data-command="save"]');
    this.$cancel_button = this.$outer.querySelector('[data-command="cancel"]');
    this.$is_hidden_checkbox = this.$outer.querySelector('[data-command="hide"]');
    this.$status = this.$outer.querySelector('[role="status"]');

    this.$save_button.addEventListener('click', () => this.save());
    this.$cancel_button.addEventListener('click', () => this.finish());

    Bugzilla.Event.enable_keyshortcuts(this.$textarea, {
      'Accel+Enter': () => this.save(),
      'Escape': () => this.finish(),
    });

    // Adjust the height of `<textarea>`
    this.$textarea.style.height = `${this.$textarea.scrollHeight}px`;
  }

  /**
   * Called whenever the comment `<textarea>` is edited. Enable or disable the Save button depending on the content.
   * @override
   * @param {KeyboardEvent} event `input` event.
   */
  textarea_oninput(event) {
    super.textarea_oninput(event);

    if (event.isComposing) {
      return;
    }

    this.$save_button.disabled = !this.edited;
  }

  /**
   * Called whenever the Update Comment button is clicked. Upload the changes to the server.
   */
  async save() {
    if (!this.edited) {
      return;
    }

    // Disable the `<textarea>` and Save button while waiting for the response
    this.$textarea.disabled = this.$save_button.disabled = this.$cancel_button.disabled = true;
    this.$status.textContent = this.str.saving;

    try {
      this.save_onsuccess(await Bugzilla.API.put(`editcomments/comment/${this.comment_id}`, {
        new_comment: this.$textarea.value,
        is_hidden: this.$is_hidden_checkbox && this.$is_hidden_checkbox.checked ? 1 : 0,
      }));
    } catch ({ message }) {
      this.save_onerror(message);
    }
  }

  /**
   * Finish editing by restoring the UI, once editing is complete or cancelled. Any unsaved comment will be discarded.
   */
  finish() {
    this.toggle_comment_action_buttons(false);
    this.$edit_button.focus();
    this.$comment_body.hidden = false;
    this.$outer.remove();
  }

  /**
   * Enable or disable buttons on the comment actions toolbar (not the editor's own toolbar) while editing the comment
   * to avoid any unexpected behaviour. The Reply button should always be disabled if the comment is empty.
   * @param {Boolean} disabled Whether the buttons should be disabled.
   */
  toggle_comment_action_buttons(disabled) {
    this.$change_set.querySelectorAll('.comment-actions button').forEach($button => {
      $button.disabled = $button.matches('.reply-btn') && this.is_empty ? true : disabled;
    });
  }

  /**
   * Retrieve the raw comment text via the API, and fill in the `<textarea>` so user can start editing.
   */
  async fetch() {
    let data;

    if (this.is_empty) {
      // Let the user edit Description (Comment 0) immediately if it's empty
      data = { comments: { [this.comment_id]: '' } };
    } else {
      try {
        data = await Bugzilla.API.get(`editcomments/comment/${this.comment_id}`);
      } catch ({ message }) {
        // Restore the UI, and display an error message
        this.finish();
        window.alert(`${this.str.fetch_error}\n\n${message}`);

        return;
      }
    }

    this.$textarea.value = this.initial_text = data.comments[this.comment_id];
    this.$textarea.style.height = `${this.$textarea.scrollHeight}px`;
    this.$textarea.disabled = false;
    this.$textarea.focus();
    this.$textarea.selectionStart = this.$textarea.value.length;

    // Add `name` attribute to form widgets so the revision can also be submitted while saving the entire bug
    this.$textarea.name = `edit_comment_textarea_${this.comment_id}`;
    this.$is_hidden_checkbox ? this.$is_hidden_checkbox.name = `edit_comment_checkbox_${this.comment_id}` : '';
  }

  /**
   * Called whenever an updated comment is successfully saved. Restore the UI, and insert/update the revision link.
   * @param {Object} data Response data.
   */
  save_onsuccess(data) {
    this.$comment_body.innerHTML = data.html;

    // Remove the empty state (new comment cannot be empty)
    if (this.is_empty) {
      this.is_empty = false;
      this.$comment_body.classList.remove('empty');
    }

    this.finish();

    // Highlight code if possible
    if (Prism) {
      Prism.highlightAllUnder(this.$comment_body);
    }

    if (!this.$revisions_link) {
      const $time = this.$change_set.querySelector('.change-time');
      const params = new URLSearchParams({
        id: 'comment-revisions.html',
        bug_id: BUGZILLA.bug_id,
        comment_id: this.comment_id,
      });

      $time.insertAdjacentHTML('afterend',
        `
        &bull;
        <div class="change-revisions">
          <a href="${BUGZILLA.config.basepath}page.cgi?${params.toString().htmlEncode()}">${this.str.edited}</a>
        </div>
        `
      );
      this.$revisions_link = $time.nextElementSibling.querySelector('a');
    }

    this.$revisions_link.title = this.str.revision_count[data.count === 1 ? 0 : 1].replace('%d', data.count);
  }

  /**
   * Called whenever an updated comment could not be saved. Re-enable the `<textarea>` and Save button, and display an
   * error message.
   * @param {String} message Error message.
   */
  save_onerror(message) {
    this.$textarea.disabled = this.$save_button.disabled = this.$cancel_button.disabled = false;
    this.$status.textContent = '';

    window.alert(`${this.str.save_error}\n\n${message}`);
  }
};

window.addEventListener('DOMContentLoaded', () => {
  for (const $change_set of document.querySelectorAll('.change-set')) {
    const $edit_button = $change_set.querySelector('.edit-btn');

    if ($edit_button) {
      $edit_button.addEventListener('click', () => new Bugzilla.InlineCommentEditor($change_set));
    }
  }
}, { once: true });
