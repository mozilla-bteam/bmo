// @ts-check

/**
 * Implement a `<select>` element alternative that shows a searchbar for easier data input. This
 * partially implements the {@link HTMLSelectElement} DOM API and the `combobox` WAI-ARIA role.
 * @see https://developer.mozilla.org/en-US/docs/Web/API/HTMLSelectElement
 * @see https://w3c.github.io/aria/#combobox
 * @see https://www.w3.org/WAI/ARIA/apg/patterns/combobox/
 */
class BzSelectElement extends HTMLElement {
  /**
   * Make it the custom element part of the outer form.
   * @type {boolean}
   */
  static formAssociated = true;

  /**
   * A list of attributes to be captured with {@link attributeChangedCallback}.
   * @type {string[]}
   */
  static get observedAttributes() {
    return ['name', 'disabled', 'required', 'aria-required', 'aria-invalid', 'aria-errormessage'];
  }

  /**
   * Whether to allow selecting multiple options. This component doesn’t support multiple selection,
   * so the value is fixed with `false`.
   * @type {boolean}
   */
  multiple = false;

  /**
   * The `type` property. This component doesn’t support multiple selection, so the value is fixed.
   * @type {string}
   */
  type = 'select-one';

  /**
   * The internal field ID.
   * @type {string}
   */
  #id;

  /**
   * The internal field label.
   * @type {string}
   */
  #label;

  /**
   * A reference to the element with the `combobox` role.
   * @type {HTMLElement}
   */
  #combobox;

  /**
   * A reference to the label element inside the {@link #combobox},
   * @type {HTMLElement}
   */
  #comboboxLabel;

  /**
   * A reference to the `<dialog>` element that shows the dropdown list.
   * @type {HTMLDialogElement}
   */
  #dialog;

  /**
   * A reference to the `<input>` element that serves as a searchbar.
   * @type {HTMLInputElement}
   */
  #searchBar;

  /**
   * A reference to the `<button>` element that clears the {@link #searchBar} value.
   * @type {HTMLInputElement}
   */
  #clearButton;

  /**
   * A reference to the element with the `listbox` role showing options.
   * @type {HTMLElement}
   */
  #listbox;

  /**
   * A reference to the element with the no match message.
   * @type {HTMLElement}
   */
  #noMatchMessage;

  /**
   * A reference to the `<slot>` element.
   * @type {HTMLSlotElement}
   */
  #slot;

  /**
   * Hold DOM properties to be synced with the HTML attributes.
   * @type {{ [key: string]: string }}
   */
  #props = {};

  /**
   * The element internals required for form association.
   * @type {ElementInternals}
   */
  #internals;

  /**
   * Hold the characters typed on the {@link #combobox} to enable a quick value search.
   * @type {string}
   */
  #typeAheadFindChars = '';

  /**
   * Hold a timeout to reset the {@link #typeAheadFindChars} value.
   * @type {number}
   */
  #typeAheadFindTimer = 0;

  /**
   * Whether to dispatch the `change` event within {@link #selectedOption}. This has to be changed
   * to `true` when updating {@link value} or {@link #selectedOption} within an event handler.
   * @type {boolean}
   */
  #canDispatchEvent = false;

  /**
   * Whether the element is disabled.
   * @type {boolean}
   */
  get disabled() {
    return this.matches('[disabled]');
  }

  /**
   * Enable or disable the element.
   * @param {boolean} disabled The new state.
   */
  set disabled(disabled) {
    if (disabled) {
      if (!this.disabled) {
        this.setAttribute('disabled', 'disabled');
      }
    } else {
      if (this.disabled) {
        this.removeAttribute('disabled');
      }
    }

    this.#combobox.setAttribute('aria-disabled', disabled);
    this.#combobox.tabIndex = disabled ? -1 : 0;
  }

  /**
   * A list of the options.
   * @type {BzOptionElement[]}
   */
  get options() {
    return [...this.querySelectorAll('bz-option')];
  }

  /**
   * Whether the selection is required.
   * @type {boolean}
   */
  get required() {
    return this.matches('[required]');
  }

  /**
   * Enable or disable the selection requirement.
   * @param {boolean} required The new state.
   */
  set required(required) {
    if (required) {
      if (!this.required) {
        this.setAttribute('required', 'required');
      }
    } else {
      if (this.required) {
        this.removeAttribute('required');
      }
    }

    this.#combobox.setAttribute('aria-required', required);
  }

  /**
   * The currently selected option’s index.
   * @type {number}
   */
  get selectedIndex() {
    return this.options.findIndex((option) => option.selected);
  }

  /**
   * Select a new option by index.
   * @param {number} index A new index.
   */
  set selectedIndex(index) {
    this.#selectedOption = this.options[index];
  }

  /**
   * A reference to the currently selected option.
   * @type {BzOptionElement}
   */
  get #selectedOption() {
    return this.options.find((option) => option.selected);
  }

  /**
   * Select a new option.
   * @param {HTMLElement | undefined} newOption A new option to be selected. If
   * `undefined`, the selection will be cleared.
   */
  set #selectedOption(newOption) {
    const currentOption = this.#selectedOption;

    if (currentOption && currentOption !== newOption) {
      currentOption.selected = false;
    }

    if (newOption) {
      if (!newOption.selected) {
        newOption.selected = true;
      }

      this.#comboboxLabel.textContent = newOption.label;
      this.#internals.setFormValue(newOption.value);
      this.#comboboxLabel.classList.remove('no-value');
    } else {
      this.#comboboxLabel.textContent = 'Select...';
      this.#comboboxLabel.classList.add('no-value');
      this.#internals.setFormValue('');
    }

    if (this.#canDispatchEvent) {
      this.dispatchEvent(new Event('change'));
    }
  }

  /**
   * A list of currently selected options. It only includes 0 or 1 option because this custom
   * element doesn’t support multiple selection.
   * @type {BzOptionElement[]}
   */
  get selectedOptions() {
    return this.options.filter((option) => option.selected);
  }

  /**
   * A list of options that are not disabled.
   * @type {BzOptionElement[]}
   */
  get #enabledOptions() {
    return this.options.filter((option) => option.matches(':not([disabled])'));
  }

  /**
   * A list of options that are not disabled or hidden.
   * @type {BzOptionElement[]}
   */
  get #availableOptions() {
    return this.options.filter((option) => option.matches(':not([disabled], [hidden])'));
  }

  /**
   * A reference to the currently active option.
   * @type {BzOptionElement | undefined}
   */
  get #activeOption() {
    return this.options.find((option) => option.matches('.active'));
  }

  /**
   * Make a new option active.
   * @param {BzOptionElement | undefined} newOption A new option to be an active descendant of the
   * listbox, or `undefined` to reset the active state.
   */
  set #activeOption(newOption) {
    const currentOption = this.#activeOption;

    if (newOption) {
      if (currentOption) {
        currentOption.classList.remove('active');

        if (currentOption.id === `${this.#id}-active-option`) {
          currentOption.removeAttribute('id');
        }
      }

      newOption.id ||= `${this.#id}-active-option`;
      newOption.classList.add('active');
      newOption.scrollIntoView();
      this.#combobox.setAttribute('aria-activedescendant', newOption.id);
    } else {
      this.#combobox.removeAttribute('aria-activedescendant');
    }
  }

  /**
   * The currently selected option’s value, or an empty string if no option is selected.
   * @type {string}
   */
  get value() {
    return this.#selectedOption?.value || '';
  }

  /**
   * Select a new option by value.
   * @param {string} value
   */
  set value(value) {
    this.#selectedOption = this.options.find((option) => option.value === value);
  }

  /**
   * Initialize a new `BzSelectElement` instance.
   */
  constructor() {
    super();

    this.#internals = this.attachInternals();
    this.#id = `select-${Math.random().toString(36).split('.')[1]}`;
  }

  /**
   * Called when the element is added to the document. Initialize the internals including the shadow
   * DOM and event handers.
   */
  connectedCallback() {
    this.#label =
      (this.hasAttribute('aria-labelledby')
        ? document
            .getElementById(this.getAttribute('aria-labelledby'))
            ?.textContent?.trim()
            .replace(/:$/, '')
        : this.getAttribute('aria-label')) || this.getAttribute('name');

    this.attachShadow({ mode: 'open' }).innerHTML = `
      <style>
        :host {
          display: inline-block;
          min-width: 80px;
          max-width: 240px;
          white-space: nowrap;
          -webkit-user-select: none;
          user-select: none;
        }

        :host([disabled]) * {
          opacity: 0.5;
          pointer-events: none;
        }

        :host(.attention) [role="combobox"] {
          border-color: var(--invalid-control-border-color);
        }

        [role="combobox"] {
          display: flex;
          align-items: center;
          box-sizing: border-box;
          outline: 0;
          border: 1px solid var(--control-border-color);
          border-radius: var(--control-border-radius);
          padding: 0 24px 0 8px;
          width: 100%;
          height: 28px;
          color: var(--control-foreground-color);
          background-color: var(--control-background-color);
          background-image: url('data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="rgb(90, 91, 92)" d="M7.41 8.59L12 13.17l4.59-4.58L18 10l-6 6-6-6 1.41-1.41z"/><path fill="none" d="M0 0h24v24H0V0z"/></svg>');
          background-position: calc(100% - 4px) center;
          background-repeat: no-repeat;
          background-size: 16px;
          cursor: pointer;
          pointer-events: auto;
        }

        [role="combobox"] .label {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        [role="combobox"] .label.no-value {
          font-style: italic;
        }

        dialog {
          flex-direction: column;
          inset: 0 auto auto 0;
          outline: 0;
          margin: 0;
          border: 1px solid var(--control-border-color);
          border-radius: var(--control-border-radius);
          padding: 0;
          width: min-content;
          max-width: 100%;
          max-height: 600px;
          color: var(--menu-foreground-color);
          background-color: var(--menu-background-color);
          box-shadow: var(--menu-box-shadow);
        }

        dialog[open] {
          display: flex;
        }

        dialog::backdrop {
          background: transparent;
        }

        [role="search"] {
          flex: none;
          box-sizing: border-box;
          outline: 0;
          margin: 8px;
          border: 1px solid var(--control-border-color);
          border-radius: var(--control-border-radius);
          padding: var(--control-padding);
          width: calc(100% - 16px);
          min-width: 80px;
          color: var(--control-foreground-color);
          background-color: var(--control-background-color);
          box-shadow: none;
          font-family: var(--font-family-sans-serif);
          font-size: var(--font-size-medium);
        }

        [role="search"][aria-hidden="true"] {
          display: none;
        }

        [role="combobox"]:focus,
        [role="search"]:focus {
          border-color: var(--focused-control-border-color);
        }

        [role="listbox"] {
          flex: auto;
          outline: 0;
          margin: 8px 0;
          overflow-y: auto;
          overscroll-behavior: contain;
        }

        [role="search"][aria-hidden="false"] ~ [role="listbox"] {
          margin-top: 0;
        }

        button:not([hidden]) {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 4px;
          margin: 0;
          border-width: 0;
          border-style: solid;
          border-color: transparent;
          padding: 0;
          color: inherit;
          background-color: transparent;
          box-shadow: none;
          font-family: inherit;
          font-size: inherit;
          line-height: inherit;
          font-weight: normal;
          text-align: left;
          white-space: nowrap;
          cursor: pointer;
        }

        button.clear {
          position: absolute;
          inset: 9px 9px auto auto;
          border-radius: 4px;
          width: 28px;
          height: 28px;
          font-size: 24px;
        }

        .no-match {
          margin: 0 8px;
        }
      </style>
      <div id="${this.#id}-combobox" tabindex="0" role="combobox" aria-readonly="true"
          aria-autocomplete="list" aria-haspopup="dialog" aria-expanded="false"
          aria-controls="${this.#id}-dialog">
        <span class="label no-value">Select...</span>
      </div>
      <dialog id="${this.#id}-dialog" aria-label="Select ${this.#label}">
        <input type="text" role="search" aria-label="Filter ${this.#label} options" />
        <button type="button" class="clear" aria-label="Clear Filtering" hidden>×</button>
        <div id="${this.#id}-listbox" role="listbox" aria-label="Available ${this.#label} options">
          <slot></slot>
        </div>
        <div class="no-match" role="status" hidden>
          <em>No matching options.</em>
        </div>
      </dialog>
    `;

    this.#combobox = this.shadowRoot.querySelector('[role="combobox"]');
    this.#comboboxLabel = this.#combobox.querySelector('.label');
    this.#dialog = this.shadowRoot.querySelector('dialog');
    this.#searchBar = this.shadowRoot.querySelector('[role="search"]');
    this.#clearButton = this.shadowRoot.querySelector('button.clear');
    this.#listbox = this.shadowRoot.querySelector('[role="listbox"]');
    this.#slot = this.shadowRoot.querySelector('slot');
    this.#noMatchMessage = this.shadowRoot.querySelector('.no-match');

    this.#combobox.addEventListener('mousedown', (event) => this.#onComboboxMouseDown(event));
    this.#combobox.addEventListener('keydown', (event) => this.#onComboboxKeyDown(event));
    this.#dialog.addEventListener('click', (event) => this.#onDialogClick(event));
    this.#dialog.addEventListener('keydown', (event) => this.#onDialogKeyDown(event));
    this.#dialog.addEventListener('close', () => this.#onDialogClose(event));
    this.#searchBar.addEventListener('input', () => this.#onSearchbarInput(event));
    this.#clearButton.addEventListener('click', (event) => this.#onClearButtonClick(event));
    this.#listbox.addEventListener('mouseover', (event) => this.#onListboxMouseOver(event));
    this.#listbox.addEventListener('mouseup', (event) => this.#onListboxMouseUp(event));
    this.#slot.addEventListener('slotchange', () => this.#onSlotChange());

    this.#setProps();
  }

  /**
   * Called whenever attributes are changed. Sync the values with corresponding properties.
   * @param {string} name Attribute name.
   * @param {string} oldValue Old attribute value.
   * @param {string} value New attribute value.
   */
  attributeChangedCallback(name, oldValue, value) {
    this.#props[name] = value;
    this.#setProps();
  }

  /**
   * Called whenever a mouse button is pressed on the {@link #combobox}. Show the dropdown list.
   * @param {MouseEvent} event `mousedown` event.
   */
  #onComboboxMouseDown(event) {
    event.preventDefault();
    this.#showDropdown();
  }

  /**
   * Called whenever a key is pressed on the {@link #combobox}. Mimic the native `<select>`
   * element’s behavior, including arrow key selection and type ahead find.
   * @param {KeyboardEvent} event `keydown` event.
   */
  #onComboboxKeyDown(event) {
    const { key } = event;
    /** @type {BzOptionElement | undefined} */
    let newOption;

    if ([' ', 'ArrowUp', 'ArrowDown'].includes(key)) {
      event.stopPropagation();
      this.#showDropdown();
    } else if (['ArrowRight', 'ArrowLeft'].includes(key)) {
      event.stopPropagation();

      const selectedOptionIndex = this.#selectedOption
        ? this.#enabledOptions.findIndex((option) => option === this.#selectedOption)
        : -1;

      if (key === 'ArrowRight') {
        const startIndex = this.#selectedOption ? selectedOptionIndex + 1 : 0;

        newOption = this.#enabledOptions.find((_, index) => index >= startIndex);
      } else {
        const endIndex = this.#selectedOption
          ? selectedOptionIndex - 1
          : this.#enabledOptions.length - 1;

        newOption = this.#enabledOptions.findLast((_, index) => index <= endIndex);
      }
    } else if (key.length === 1) {
      event.stopPropagation();

      if (this.#typeAheadFindChars !== key) {
        this.#typeAheadFindChars += key;
      }

      clearTimeout(this.#typeAheadFindTimer);

      this.#typeAheadFindTimer = window.setTimeout(() => {
        this.#typeAheadFindChars = '';
      }, 1000);

      const regex = new RegExp(`^${this.#typeAheadFindChars}`, 'i');
      const startIndex = this.#selectedOption?.label.match(regex)
        ? this.#enabledOptions.findIndex((option) => option === this.#selectedOption) + 1
        : 0;

      newOption = this.#enabledOptions.find(
        (option, index) => index >= startIndex && option.label.match(regex),
      );
    }

    if (newOption) {
      this.#canDispatchEvent = true;
      this.#selectedOption = newOption;
      this.#canDispatchEvent = false;
    }
  }

  /**
   * Called whenever the {@link #dialog} is clicked. Hide the dropdown list, and select a new option
   * if possible. Usually {@link #onListboxMouseUp} handles selection, but the code is needed to
   * pass the Selenium tests using `click` events.
   * @param {MouseEvent} event `click` event.
   */
  #onDialogClick(event) {
    const { target } = event;

    if (target === this) {
      this.#hideDropdown();
    } else if (target.matches('bz-option:not([disabled])')) {
      this.#hideDropdown();
      this.#canDispatchEvent = true;
      this.value = target.value;
      this.#canDispatchEvent = false;
    }
  }

  /**
   * Called whenever a key is pressed on the {@link #dialog}. Change the active state when an arrow
   * key is pressed, or select a new option when the Enter key is pressed.
   * @param {KeyboardEvent} event `keydown` event.
   */
  #onDialogKeyDown(event) {
    const { key } = event;
    const options = this.#availableOptions;
    const currentOption = this.#activeOption;
    /** @type {BzOptionElement | undefined} */
    let newActiveOption;

    if (key === 'ArrowDown') {
      event.preventDefault();
      newActiveOption = currentOption ? options[options.indexOf(currentOption) + 1] : options[0];
    }

    if (key === 'ArrowUp') {
      event.preventDefault();
      newActiveOption = currentOption
        ? options[options.indexOf(currentOption) - 1]
        : options[options.length - 1];
    }

    if (key === 'Enter') {
      event.preventDefault();
      this.#hideDropdown();

      if (currentOption) {
        this.#canDispatchEvent = true;
        this.value = currentOption.value;
        this.#canDispatchEvent = false;
      }
    }

    this.#activeOption = newActiveOption;
  }

  /**
   * Called whenever the {@link #dialog} is closed with the Escape key. Hide the dropdown list.
   */
  #onDialogClose() {
    this.#hideDropdown();
  }

  /**
   * Called whenever a key is pressed on the {@link #searchBar}. Filter the options based on the
   * input.
   */
  #onSearchbarInput() {
    const value = this.#searchBar.value.trim();
    const terms = value.split(/\s+/).map((term) => term.toLocaleLowerCase());
    /** @type {BzOptionElement | undefined} */
    let newActiveOption;

    this.#enabledOptions.forEach((option) => {
      if (terms.every((term) => option.label.toLocaleLowerCase().includes(term))) {
        newActiveOption ??= option;
        option.removeAttribute('hidden');
      } else {
        option.setAttribute('hidden', 'hidden');
      }
    });

    const hasAvailableOptions = !!this.#availableOptions.length;

    this.#activeOption = newActiveOption;
    this.#listbox.hidden = !hasAvailableOptions;
    this.#noMatchMessage.hidden = hasAvailableOptions;
    this.#clearButton.hidden = !value;
  }

  /**
   * Whenever the {@link #clearButton} is clicked. Clear the filter value.
   * @param {MouseEvent} event `click` event.
   */
  #onClearButtonClick(event) {
    event.stopPropagation();

    this.#searchBar.value = '';
    this.#onSearchbarInput();
  }

  /**
   * Called whenever the mouse is moved over the {@link #listbox}. Update the active state if the
   * target is an option.
   * @param {MouseEvent} event `mouseover` event.
   */
  #onListboxMouseOver(event) {
    const { target } = event;

    if (target.matches('bz-option:not([disabled])')) {
      this.#activeOption = target;
    }
  }

  /**
   * Called whenever a mouse button is released on the {@link #listbox}. Select a new option if the
   * target is an option.
   * @param {MouseEvent} event `mouseup` event.
   */
  #onListboxMouseUp(event) {
    const { target } = event;

    if (target.matches('bz-option:not([disabled])')) {
      event.preventDefault();
      this.#hideDropdown();
      this.#canDispatchEvent = true;
      this.value = target.value;
      this.#canDispatchEvent = false;
    }
  }

  /**
   * Called whenever the slot content is updated. Show or hide the {@link #searchBar} depending on
   * the number of options.
   */
  #onSlotChange() {
    this.#searchBar.setAttribute('aria-hidden', this.options.length < 10);
  }

  /**
   * Sync properties with attributes added to {@link #props}.
   */
  #setProps() {
    if (!this.#combobox) {
      return;
    }

    Object.entries(this.#props).forEach(([name, value]) => {
      if (['name'].includes(name)) {
        this[name] = value;
      }

      if (['disabled', 'required'].includes(name)) {
        this[name] = value !== null;
      }

      if (name.startsWith('aria-') && value !== null) {
        this.#combobox.setAttribute(name, value);
        this.removeAttribute(name);
      }
    });

    this.#props = {};
  }

  /**
   * Show the dropdown list.
   */
  #showDropdown() {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(({ intersectionRect, rootBounds }) => {
        if (!intersectionRect) {
          return;
        }

        const { scrollHeight: contentHeight, scrollWidth: contentWidth } = this.#dialog;
        const topMargin = intersectionRect.top - 8;
        const bottomMargin = rootBounds.height - intersectionRect.bottom - 8;
        let showAtTop = false;
        let height = 'auto';

        if (contentHeight > bottomMargin) {
          if (topMargin > bottomMargin) {
            height = `${Math.min(topMargin, contentHeight)}px`;
            showAtTop = true;
          } else {
            height = `${Math.min(bottomMargin, contentHeight)}px`;
          }
        }

        const top = showAtTop ? 'auto' : `${intersectionRect.bottom}px`;
        const right = 'auto';
        const bottom = showAtTop ? `${rootBounds.height - intersectionRect.top}px` : 'auto';
        const left = `${intersectionRect.left}px`;

        this.#dialog.style.inset = [top, right, bottom, left].join(' ');
        this.#dialog.style.height = height;
        this.#dialog.style.opacity = 1;

        observer.disconnect();
      });
    });

    this.#dialog.style.opacity = 0;
    this.#dialog.showModal();
    this.#combobox.setAttribute('aria-expanded', 'true');
    document.body.style.setProperty('overflow', 'hidden');

    window.requestAnimationFrame(() => {
      observer.observe(this);
    });

    const selected = this.#selectedOption;

    if (selected) {
      selected.classList.add('active');
      selected.scrollIntoView();
    }
  }

  /**
   * Hide the dropdown list and reset the states.
   */
  #hideDropdown() {
    if (this.#dialog.open) {
      this.#dialog.close();
    }

    document.body.style.removeProperty('overflow');
    this.#dialog.style = '';
    this.#searchBar.value = '';
    this.#combobox.setAttribute('aria-expanded', 'false');
    this.#combobox.removeAttribute('aria-activedescendant');

    this.options.forEach((option) => {
      option.removeAttribute('hidden');
      option.classList.remove('active');

      if (option.id === `${this.#id}-active-option`) {
        option.removeAttribute('id');
      }
    });
  }
}

/**
 * Implement an `<option>` alternative that can display a tooltip. This partially implements the
 * {@link HTMLOptionElement} DOM API and the `option` WAI-ARIA role.
 * @see https://developer.mozilla.org/en-US/docs/Web/API/HTMLOptionElement
 * @see https://w3c.github.io/aria/#option
 */
class BzOptionElement extends HTMLElement {
  /**
   * A list of attributes to be captured with {@link attributeChangedCallback}.
   * @type {string[]}
   */
  static get observedAttributes() {
    return ['class', 'value', 'selected', 'disabled', 'hidden', 'aria-description'];
  }

  /**
   * The option’s value.
   * @type {string}
   */
  value = '';

  /**
   * A reference to the element with the `option` role.
   * @type {HTMLElement}
   */
  #option;

  /**
   * A reference to the `<slot>` element.
   * @type {HTMLSlotElement}
   */
  #slot;

  /**
   * A reference to the `<dialog>` element that shows a tooltip.
   * @type {HTMLDialogElement}
   */
  #dialog;

  /**
   * Hold a timeout to reset the {@link #dialog} opener.
   * @type {number}
   */
  #dialogOpenTimer = 0;

  /**
   * Hold DOM properties to be synced with the HTML attributes.
   * @type {{ [key: string]: string }}
   */
  #props = {};

  /**
   * Whether to element is selected by default. Note that the `selected` attribute is not updated
   * when the selection is updated; it always indicates the default selection.
   * @type {boolean}
   */
  get defaultSelected() {
    return this.matches('[selected]');
  }

  /**
   * Whether the element is disabled.
   * @type {boolean}
   */
  get disabled() {
    return this.matches('[disabled]');
  }

  /**
   * Enable or disable the element.
   * @param {boolean} disabled The new state.
   */
  set disabled(disabled) {
    if (disabled) {
      if (!this.disabled) {
        this.setAttribute('disabled', 'disabled');
      }
    } else {
      if (this.disabled) {
        this.removeAttribute('disabled');
      }
    }

    this.#option.setAttribute('aria-disabled', disabled);
  }

  /**
   * Whether the element is hidden.
   * @type {boolean}
   */
  get hidden() {
    return this.matches('[hidden]');
  }

  /**
   * Show or hide the element.
   * @param {boolean} hidden The new state.
   */
  set hidden(hidden) {
    if (hidden) {
      if (!this.hidden) {
        this.setAttribute('hidden', 'hidden');
      }
    } else {
      if (this.hidden) {
        this.removeAttribute('hidden');
      }
    }

    this.#option.setAttribute('aria-hidden', hidden);
  }

  /**
   * The position of the option within the parent `<bz-select>` element’s option list.
   * @type {number}
   */
  get index() {
    return this.closest('bz-select').options.indexOf(this);
  }

  /**
   * The option’s displayed label.
   * @type {string}
   */
  get label() {
    return this.#slot.assignedNodes()[0]?.textContent.trim() ?? '';
  }

  /**
   * A reference to the parent `<bz-select>` element.
   * @type {BzSelectElement}
   */
  get #select() {
    return this.closest('bz-select');
  }

  /**
   * Whether the option is currently selected. Note that, as mentioned in the comment for
   * {@link defaultSelected}, the `selected` attribute cannot be used to determine the selection.
   * @type {boolean}
   */
  get selected() {
    return this.#option.matches('[aria-selected="true"]');
  }

  /**
   * Select or deselect the option.
   * @param {boolean} selected The new state.
   */
  set selected(selected) {
    if (selected) {
      if (!this.selected) {
        this.#option.setAttribute('aria-selected', 'true');
      }

      if (this.#select.value !== this.value) {
        this.#select.value = this.value;
      }
    } else {
      if (this.selected) {
        this.#option.setAttribute('aria-selected', 'false');
      }

      if (this.#select.value !== '') {
        this.#select.value = '';
      }
    }
  }

  /**
   * The option’s displayed label. An alias of {@link label}.
   * @type {string}
   */
  get text() {
    return this.label;
  }

  /**
   * Initialize a new `BzOptionElement` instance.
   */
  constructor() {
    super();
  }

  /**
   * Called when the element is added to the document. Initialize the internals including the shadow
   * DOM and event handers.
   */
  connectedCallback() {
    this.attachShadow({ mode: 'open' }).innerHTML = `
      <style>
        :host {
          display: block;
          white-space: nowrap;
          -webkit-user-select: none;
          user-select: none;
        }

        :host([hidden]) {
          display: none;
        }

        :host([disabled]) * {
          opacity: 0.5;
          pointer-events: none;
        }

        [role="option"] {
          position: relative;
          display: flex;
          align-items: center;
          padding: 0 16px 0 32px;
          height: 28px;
          cursor: pointer;
        }

        [role="option"][aria-selected="true"] {
          background-image: url('data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="rgb(170, 171, 172)" d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>');
          background-position: 8px center;
          background-repeat: no-repeat;
          background-size: 16px;
        }

        :host(.active),
        [role="option"]:hover {
          background-color: var(--hovered-menuitem-background-color);
        }

        dialog {
          position: fixed;
          outline: 0;
          margin: 0;
          border: 1px solid var(--control-border-color);
          border-radius: var(--control-border-radius);
          padding: 12px;
          width: 240px;
          max-width: 100%;
          max-height: 100%;
          color: var(--secondary-label-color);
          background-color: var(--menu-background-color);
          box-shadow: var(--menu-box-shadow);
          font-size: var(--font-size-small);
          line-height: var(--line-height-comfortable);
          white-space: normal;
        }

        dialog :is(p, ul) {
          margin: 8px 0;
          padding: 0;
        }

        dialog li {
          margin: 4px 0 4px 16px;
          padding: 0;
        }

        dialog :first-child {
          margin-top: 0;
        }

        dialog :last-child {
          margin-bottom: 0;
        }
      </style>
      <div role="option" aria-selected="${this.hasAttribute('selected')}">
        <slot></slot>
        <dialog role="none">
          ${
            // Assume `aria-description` is sanitized
            this.getAttribute('aria-description') || ''
          }
        </dialog>
      </div>
    `;

    this.#option = this.shadowRoot.querySelector('[role="option"]');
    this.#slot = this.shadowRoot.querySelector('slot');
    this.#dialog = this.shadowRoot.querySelector('dialog');

    this.#slot.addEventListener('slotchange', (event) => this.#onSlotChange(event));

    this.#setProps();
  }

  /**
   * Called when attributes are changed. Sync the values with corresponding properties.
   * @param {string} name Attribute name.
   * @param {string} oldValue Old attribute value.
   * @param {string} value New attribute value.
   */
  attributeChangedCallback(name, oldValue, value) {
    this.#props[name] = value;
    this.#setProps();
  }

  /**
   * Scroll the parent `<bz-select>` element to make the option visible.
   */
  scrollIntoView() {
    if (super.scrollIntoViewIfNeeded) {
      super.scrollIntoViewIfNeeded();
    } else {
      const observer = new IntersectionObserver((entries) => {
        entries.forEach(({ intersectionRect, intersectionRatio }) => {
          if (!intersectionRect) {
            return;
          }

          if (intersectionRatio < 1) {
            super.scrollIntoView(false);
          }

          observer.disconnect();
        });
      });

      observer.observe(this);
    }
  }

  /**
   * Sync properties with attributes added to {@link #props}.
   */
  #setProps() {
    if (!this.#option) {
      return;
    }

    Object.entries(this.#props).forEach(([name, value]) => {
      if (['value'].includes(name)) {
        this[name] = value;
      }

      if (['selected', 'disabled', 'hidden'].includes(name)) {
        this[name] = value !== null;
      }

      if (name.startsWith('aria-') && value !== null) {
        this.#option.setAttribute(name, value);
        this.removeAttribute(name);
      }

      if (name === 'class') {
        if (this.#dialog.textContent.trim()) {
          if (value.match(/\bactive\b/)) {
            this.#showTooltip();
          } else {
            this.#hideTooltip();
          }
        }
      }
    });

    this.#props = {};
  }

  /**
   * Show the tooltip.
   */
  #showTooltip() {
    if (this.#dialog.open) {
      return;
    }

    this.#dialogOpenTimer = window.setTimeout(() => {
      const optionRect = this.getBoundingClientRect();

      // Avoid autofocus with `inert`
      this.#dialog.inert = true;
      this.#dialog.style.top = `${optionRect.top + 4}px`;
      this.#dialog.style.left = `${optionRect.right - 4}px`;
      this.#dialog.style.opacity = 0;
      this.#dialog.show();
      this.#dialog.inert = false;

      // Adjust the position
      window.requestAnimationFrame(() => {
        const dialogRect = this.#dialog.getBoundingClientRect();
        const rootRect = document.body.getBoundingClientRect();

        if (dialogRect.bottom > rootRect.bottom) {
          this.#dialog.style.top = 'auto';
          this.#dialog.style.bottom = '4px';
        }

        this.#dialog.style.opacity = 1;
      });
    }, 250);
  }

  /**
   * Hide the tooltip.
   */
  #hideTooltip() {
    window.clearTimeout(this.#dialogOpenTimer);

    if (this.#dialog.open) {
      this.#dialog.close();
    }
  }

  /**
   * Called whenever the slot content is updated. Update the parent `<bz-select>` element’s value if
   * it’s selected by default.
   */
  #onSlotChange() {
    if (this.defaultSelected) {
      this.#select.value = this.value;
    }
  }
}

window.customElements.define('bz-select', BzSelectElement);
window.customElements.define('bz-option', BzOptionElement);
