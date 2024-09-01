/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

/* global Bugzilla */

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

/**
 * Provide inline comment editing functionality that allows the users to edit and update existing
 * comments on the modal bug page.
 */
Bugzilla.InlineCommentEditor = class InlineCommentEditor extends Bugzilla.CommentEditor {
  /**
   * Initialize a new `InlineCommentEditor` instance.
   * @param {HTMLElement} $changeSet Comment outer element.
   */
  constructor($changeSet) {
    /** @type {HTMLElement} */
    const $commentBody = $changeSet.querySelector('.comment-text');

    super({ useMarkdown: $commentBody.matches('.markdown-body'), showTips: false });

    /** @type {Record<string, string>} */
    this.str = Object.assign(this.str, BUGZILLA.string.InlineCommentEditor);
    /** @type {number} */
    this.commentId = Number($commentBody.dataset.commentId);
    /** @type {number} */
    this.commenterId = Number(
      /** @type {HTMLElement} */ ($changeSet.querySelector('.email')).dataset.userId,
    );
    /** @type {boolean} */
    this.isEmpty = $commentBody.matches('.empty');

    /** @type {HTMLElement} */
    this.$changeSet = $changeSet;
    /** @type {HTMLElement} */
    this.$commentBody = $commentBody;
    /** @type {HTMLButtonElement} */
    this.$editButton = $changeSet.querySelector('.edit-btn');
    /** @type {HTMLAnchorElement} */
    this.$revisionsLink = $changeSet.querySelector('.change-revisions a');

    this.render();
    this.fetch();
  }

  /**
   * Insert the inline comment editor to the comment body part. Replace the comment body with a
   * disabled `<textarea>` filled with the text as a placeholder while retrieving the raw comment
   * text. Also, provide a toolbar with the Save and Cancel buttons as well as the Hide This
   * Revision checkbox for admin.
   * @override
   */
  render() {
    const { isMac } = Bugzilla.UserAgent;

    this.toggleCommentActionButtons(true);
    this.$commentBody.hidden = true;

    this.$commentBody.insertAdjacentHTML(
      'afterend',
      `
        <div role="group" class="inline-comment-editor">
          <div role="toolbar" class="bottom-toolbar" aria-label="${this.str.toolbar}">
            <span role="status"></span>
            ${
              BUGZILLA.user.is_insider && BUGZILLA.user.id !== this.commenterId
                ? `
                  <label>
                    <input type="checkbox" value="on" checked data-command="hide">
                      ${this.str.hide_revision}
                  </label>
                `
                : ''
            }
            <button type="button" class="secondary" data-command="cancel"
                title="${this.str.cancel_tooltip} (Esc)">
              ${this.str.cancel}
            </button>
            <button type="button" class="primary" disabled data-command="save"
                title="${this.str.save_tooltip} (${isMac ? '&#x2318;Return' : 'Ctrl+Enter'})">
              ${this.str.save}
            </button>
          </div>
        </div>
      `,
    );

    this.$outer = /** @type {HTMLElement} */ (this.$commentBody.nextElementSibling);
    this.$outer.insertAdjacentElement('afterbegin', this.$container);

    /** @type {HTMLButtonElement} */
    this.$saveButton = this.$outer.querySelector('[data-command="save"]');
    /** @type {HTMLButtonElement} */
    this.$cancelButton = this.$outer.querySelector('[data-command="cancel"]');
    /** @type {HTMLInputElement} */
    this.$isHiddenCheckbox = this.$outer.querySelector('[data-command="hide"]');
    /** @type {HTMLElement} */
    this.$status = this.$outer.querySelector('[role="status"]');

    this.$saveButton.addEventListener('click', () => this.save());
    this.$cancelButton.addEventListener('click', () => this.finish());

    Bugzilla.Event.activateKeyShortcuts(this.$textarea, {
      'Accel+Enter': { handler: () => this.save() },
      Escape: { handler: () => this.finish() },
    });

    // Adjust the height of `<textarea>`
    this.$textarea.style.height = `${this.$textarea.scrollHeight}px`;
  }

  /**
   * Retrieve the comment’s raw text via the API, and fill in the `<textarea>` so the user can start
   * editing.
   */
  async fetch() {
    /** @type {{ comments: { [commentId: string]: string }}} */
    let data;

    if (this.isEmpty) {
      // Let the user edit Description (Comment 0) immediately if it’s empty
      data = { comments: { [this.commentId]: '' } };
    } else {
      try {
        data = await Bugzilla.API.get(`editcomments/comment/${this.commentId}`);
      } catch ({ message }) {
        // Restore the UI, and display an error message
        this.finish();
        window.alert(`${this.str.fetch_error}\n\n${message}`);

        return;
      }
    }

    this.initialText = data.comments[this.commentId];

    this.$textarea.value = this.initialText;
    this.$textarea.style.height = `${this.$textarea.scrollHeight}px`;
    this.$textarea.disabled = false;
    this.$textarea.focus();
    this.$textarea.selectionStart = this.$textarea.value.length;

    // Add the `name` attribute to the form widgets so the revision can also be submitted while
    // saving the entire bug
    this.$textarea.name = `edit_comment_textarea_${this.commentId}`;
    this.$isHiddenCheckbox
      ? (this.$isHiddenCheckbox.name = `edit_comment_checkbox_${this.commentId}`)
      : '';
  }

  /**
   * Called whenever the comment `<textarea>` is edited. Enable or disable the Save button depending
   * on the content.
   * @override
   * @param {InputEvent} event `input` event.
   */
  textareaOnInput(event) {
    super.textareaOnInput(event);

    if (event.isComposing) {
      return;
    }

    this.$saveButton.disabled = !this.edited;
  }

  /**
   * Enable or disable the buttons on the comment actions toolbar (not the editor’s own toolbar)
   * while the comment is being edited to avoid any unexpected behavior. The Reply button should
   * always be disabled if the comment is empty.
   * @param {Boolean} disabled Whether to disable the buttons.
   */
  toggleCommentActionButtons(disabled) {
    this.$changeSet
      .querySelectorAll('.comment-actions button')
      .forEach((/** @type {HTMLButtonElement} */ $button) => {
        $button.disabled = $button.matches('.reply-btn') && this.isEmpty ? true : disabled;
      });
  }

  /**
   * Called whenever the Update Comment button is clicked. Upload the changes to the server.
   */
  async save() {
    if (!this.edited) {
      return;
    }

    // Disable the `<textarea>` and Save button while waiting for the response
    this.$textarea.disabled = true;
    this.$saveButton.disabled = true;
    this.$cancelButton.disabled = true;
    this.$status.textContent = this.str.saving;

    try {
      this.saveOnSuccess(
        await Bugzilla.API.put(`editcomments/comment/${this.commentId}`, {
          new_comment: this.$textarea.value,
          is_hidden: this.$isHiddenCheckbox?.checked ? 1 : 0,
        }),
      );
    } catch ({ message }) {
      this.saveOnError(message);
    }
  }

  /**
   * Called whenever an updated comment is successfully saved. Restore the UI, and insert/update the
   * revision link.
   * @param {{ html: string, count: number }} data Response data.
   */
  saveOnSuccess(data) {
    this.$commentBody.innerHTML = data.html;

    // Remove the empty state (new comment cannot be empty)
    if (this.isEmpty) {
      this.isEmpty = false;
      this.$commentBody.classList.remove('empty');
    }

    this.finish();

    // Highlight code if possible
    if (Prism) {
      Prism.highlightAllUnder(this.$commentBody);
    }

    if (!this.$revisionsLink) {
      const $time = this.$changeSet.querySelector('.change-time');

      const params = new URLSearchParams({
        id: 'comment-revisions.html',
        bug_id: String(BUGZILLA.bug_id),
        comment_id: String(this.commentId),
      });

      $time.insertAdjacentHTML(
        'afterend',
        `
        &bull;
        <div class="change-revisions">
          <a href="${BUGZILLA.config.basepath}page.cgi?${params.toString().htmlEncode()}">
            ${this.str.edited}
          </a>
        </div>
        `,
      );

      this.$revisionsLink = $time.nextElementSibling.querySelector('a');
    }

    this.$revisionsLink.title = this.str.revision_count[data.count === 1 ? 0 : 1].replace(
      '%d',
      String(data.count),
    );
  }

  /**
   * Called whenever an updated comment could not be saved. Re-enable the `<textarea>` and Save
   * button, and display an error message.
   * @param {string} message Error message.
   */
  saveOnError(message) {
    this.$textarea.disabled = false;
    this.$saveButton.disabled = false;
    this.$cancelButton.disabled = false;
    this.$status.textContent = '';

    window.alert(`${this.str.save_error}\n\n${message}`);
  }

  /**
   * Finish editing by restoring the UI, once editing is complete or canceled. Any unsaved comment
   * will be discarded.
   */
  finish() {
    this.toggleCommentActionButtons(false);
    this.$editButton.focus();
    this.$commentBody.hidden = false;
    this.$outer.remove();
  }
};

window.addEventListener(
  'DOMContentLoaded',
  () => {
    document.querySelectorAll('.change-set').forEach((/** @type {HTMLElement} */ $changeSet) => {
      $changeSet.querySelector('.edit-btn')?.addEventListener('click', () => {
        new Bugzilla.InlineCommentEditor($changeSet);
      });
    });
  },
  { once: true },
);
