/* The contents of this file are subject to the Mozilla Public
 * License Version 1.1 (the "License"); you may not use this file
 * except in compliance with the License. You may obtain a copy of
 * the License at http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS
 * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * rights and limitations under the License.
 *
 * The Original Code is the Bugzilla Bug Tracking System.
 *
 * The Initial Developer of the Original Code is Everything Solved, Inc.
 * Portions created by Everything Solved are Copyright (C) 2007 Everything
 * Solved, Inc. All Rights Reserved.
 *
 * Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>
 *                 Guy Pyrzak <guy.pyrzak@gmail.com>
 *                 Reed Loden <reed@reedloden.com>
 */

/* This library assumes that the needed YUI libraries have been loaded
   already. */

var bz_no_validate_enter_bug = false;
function validateEnterBug(theform) {
    // This is for the "bookmarkable templates" button.
    if (bz_no_validate_enter_bug) {
        // Set it back to false for people who hit the "back" button
        bz_no_validate_enter_bug = false;
        return true;
    }

    var component = theform.component;
    var short_desc = theform.short_desc;
    var version = theform.version;
    var bug_status = theform.bug_status;
    var bug_type = theform.bug_type;
    var description = theform.comment;
    var attach_data = theform.data;
    var attach_desc = theform.description;

    const $bug_type_group = document.querySelector('#bug_type');

    var current_errors = YAHOO.util.Dom.getElementsByClassName(
        'validation_error_text', null, theform);
    for (var i = 0; i < current_errors.length; i++) {
        current_errors[i].parentNode.removeChild(current_errors[i]);
    }
    var current_error_fields = YAHOO.util.Dom.getElementsByClassName(
        'validation_error_field', null, theform);
    for (var i = 0; i < current_error_fields.length; i++) {
        var field = current_error_fields[i];
        YAHOO.util.Dom.removeClass(field, 'validation_error_field');
    }

    var focus_me;

    // These are checked in the reverse order that they appear on the page,
    // so that the one closest to the top of the form will be focused.
    if (attach_data.value && attach_desc.value.trim() == '') {
        _errorFor(attach_desc, 'attach_desc');
        focus_me = attach_desc;
    }
    var check_description = status_comment_required[bug_status.value];
    if (check_description && description.value.trim() == '') {
        _errorFor(description, 'description');
        focus_me = description;
    }
    if (short_desc.value.trim() == '') {
        _errorFor(short_desc);
        focus_me = short_desc;
    }
    if (version.selectedIndex < 0) {
        _errorFor(version);
        focus_me = version;
    }
    if (component.selectedIndex < 0) {
        _errorFor(component);
        focus_me = component;
    }
    if ($bug_type_group.matches('[aria-required="true"]') && !bug_type.value) {
        _errorFor($bug_type_group);
        focus_me = bug_type[0];
    }

    if (focus_me) {
        focus_me.focus();
        return false;
    }

    return true;
}

function _errorFor(field, name) {
    if (!name) name = field.id;
    var string_name = name + '_required';
    var error_text = BUGZILLA.string[string_name];
    var new_node = document.createElement('div');
    YAHOO.util.Dom.addClass(new_node, 'validation_error_text');
    new_node.innerHTML = error_text;
    YAHOO.util.Dom.insertAfter(new_node, field);
    YAHOO.util.Dom.addClass(field, 'validation_error_field');
}

function createCalendar(name) {
    var cal = new YAHOO.widget.Calendar('calendar_' + name,
                                        'con_calendar_' + name);
    YAHOO.bugzilla['calendar_' + name] = cal;
    var field = document.getElementById(name);
    cal.selectEvent.subscribe(setFieldFromCalendar, field, false);
    updateCalendarFromField(field);
    cal.render();
}

/* The onclick handlers for the button that shows the calendar. */
function showCalendar(field_name) {
    var calendar  = YAHOO.bugzilla["calendar_" + field_name];
    var field     = document.getElementById(field_name);
    var button    = document.getElementById('button_calendar_' + field_name);

    bz_overlayBelow(calendar.oDomContainer, field);
    calendar.show();
    button.onclick = function() { hideCalendar(field_name); };

    // Because of the way removeListener works, this has to be a function
    // attached directly to this calendar.
    calendar.bz_myBodyCloser = function(event) {
        var container = this.oDomContainer;
        var target    = YAHOO.util.Event.getTarget(event);
        if (target != container && target != button
            && !YAHOO.util.Dom.isAncestor(container, target))
        {
            hideCalendar(field_name);
        }
    };

    // If somebody clicks outside the calendar, hide it.
    YAHOO.util.Event.addListener(document.body, 'click',
                                 calendar.bz_myBodyCloser, calendar, true);

    // Make Esc close the calendar.
    calendar.bz_escCal = function (event) {
        var key = YAHOO.util.Event.getCharCode(event);
        if (key == 27) {
            hideCalendar(field_name);
        }
    };
    YAHOO.util.Event.addListener(document.body, 'keydown', calendar.bz_escCal);
}

function hideCalendar(field_name) {
    var cal = YAHOO.bugzilla["calendar_" + field_name];
    cal.hide();
    var button = document.getElementById('button_calendar_' + field_name);
    button.onclick = function() { showCalendar(field_name); };
    YAHOO.util.Event.removeListener(document.body, 'click',
                                    cal.bz_myBodyCloser);
    YAHOO.util.Event.removeListener(document.body, 'keydown', cal.bz_escCal);
}

/* This is the selectEvent for our Calendar objects on our custom
 * DateTime fields.
 */
function setFieldFromCalendar(type, args, date_field) {
    var dates = args[0];
    var setDate = dates[0];

    // We can't just write the date straight into the field, because there
    // might already be a time there.
    var timeRe = /\b(\d{1,2}):(\d\d)(?::(\d\d))?/;
    var currentTime = timeRe.exec(date_field.value);
    var d = new Date(setDate[0], setDate[1] - 1, setDate[2]);
    if (currentTime) {
        d.setHours(currentTime[1], currentTime[2]);
        if (currentTime[3]) {
            d.setSeconds(currentTime[3]);
        }
    }

    var year = d.getFullYear();
    // JavaScript's "Date" represents January as 0 and December as 11.
    var month = d.getMonth() + 1;
    if (month < 10) month = '0' + String(month);
    var day = d.getDate();
    if (day < 10) day = '0' + String(day);
    var dateStr = year + '-' + month  + '-' + day;

    if (currentTime) {
        var minutes = d.getMinutes();
        if (minutes < 10) minutes = '0' + String(minutes);
        var seconds = d.getSeconds();
        if (seconds > 0 && seconds < 10) {
            seconds = '0' + String(seconds);
        }

        dateStr = dateStr + ' ' + d.getHours() + ':' + minutes;
        if (seconds) dateStr = dateStr + ':' + seconds;
    }

    date_field.value = dateStr;
    date_field.dispatchEvent(new Event('input'));
    hideCalendar(date_field.id);
}

/* Sets the calendar based on the current field value.
 */
function updateCalendarFromField(date_field) {
    var dateRe = /(\d\d\d\d)-(\d\d?)-(\d\d?)/;
    var pieces = dateRe.exec(date_field.value);
    if (pieces) {
        var cal = YAHOO.bugzilla["calendar_" + date_field.id];
        cal.select(new Date(pieces[1], pieces[2] - 1, pieces[3]));
        var selectedArray = cal.getSelectedDates();
        var selected = selectedArray[0];
        cal.cfg.setProperty("pagedate", (selected.getMonth() + 1) + '/'
                                        + selected.getFullYear());
        cal.render();
    }
}

function setupEditLink(id) {
    var link_container = 'container_showhide_' + id;
    var input_container = 'container_' + id;
    var link = 'showhide_' + id;
    hideEditableField(link_container, input_container, link);
}

/* Hide input/select fields and show the text with (edit) next to it */
function hideEditableField( container, input, action, field_id, original_value, new_value, hide_input ) {
    YAHOO.util.Dom.removeClass(container, 'bz_default_hidden');
    YAHOO.util.Dom.addClass(input, 'bz_default_hidden');
    YAHOO.util.Event.addListener(action, 'click', showEditableField,
                                 new Array(container, input, field_id, new_value));
    if(field_id != ""){
        YAHOO.util.Event.addListener(window, 'load', checkForChangedFieldValues,
                        new Array(container, input, field_id, original_value, hide_input ));
    }
}

/* showEditableField (e, ContainerInputArray)
 * Function hides the (edit) link and the text and displays the input/select field
 *
 * var e: the event
 * var ContainerInputArray: An array containing the (edit) and text area and the input being displayed
 * var ContainerInputArray[0]: the container that will be hidden usually shows the (edit) or (take) text
 * var ContainerInputArray[1]: the input area and label that will be displayed
 * var ContainerInputArray[2]: the input/select field id for which the new value must be set
 * var ContainerInputArray[3]: the new value to set the input/select field to when (take) is clicked
 */
function showEditableField (e, ContainerInputArray) {
    var inputs = new Array();
    var inputArea = YAHOO.util.Dom.get(ContainerInputArray[1]);
    if ( ! inputArea ){
        YAHOO.util.Event.preventDefault(e);
        return;
    }
    YAHOO.util.Dom.addClass(ContainerInputArray[0], 'bz_default_hidden');
    YAHOO.util.Dom.removeClass(inputArea, 'bz_default_hidden');
    if ( inputArea.tagName.toLowerCase() == "input" ) {
        inputs.push(inputArea);
    } else if (ContainerInputArray[2]) {
        inputs.push(document.getElementById(ContainerInputArray[2]));
    } else {
        inputs = inputArea.getElementsByTagName('input');
        if ( inputs.length == 0 )
            inputs = inputArea.getElementsByTagName('textarea');
    }
    if ( inputs.length > 0 ) {
        // Change the first field's value to ContainerInputArray[2]
        // if present before focusing.
        var type = inputs[0].tagName.toLowerCase();
        if (ContainerInputArray[3]) {
            if ( type == "input" ) {
                inputs[0].value = ContainerInputArray[3];
            } else {
                for (var i = 0; inputs[0].length; i++) {
                    if ( inputs[0].options[i].value == ContainerInputArray[3] ) {
                        inputs[0].options[i].selected = true;
                        break;
                    }
                }
            }
        }
        // focus on the first field, this makes it easier to edit
        inputs[0].focus();
        if ( type == "input" || type == "textarea" ) {
            inputs[0].select();
        }
    }
    YAHOO.util.Event.preventDefault(e);
}


/* checkForChangedFieldValues(e, array )
 * Function checks if after the autocomplete by the browser if the values match the originals.
 *   If they don't match then hide the text and show the input so users don't get confused.
 *
 * var e: the event
 * var ContainerInputArray: An array containing the (edit) and text area and the input being displayed
 * var ContainerInputArray[0]: the container that will be hidden usually shows the (edit) text
 * var ContainerInputArray[1]: the input area and label that will be displayed
 * var ContainerInputArray[2]: the field that is on the page, might get changed by browser autocomplete
 * var ContainerInputArray[3]: the original value from the page loading.
 *
 */
function checkForChangedFieldValues(e, ContainerInputArray ) {
    var el = document.getElementById(ContainerInputArray[2]);
    var unhide = false;
    if ( el ) {
        if ( !ContainerInputArray[4]
             && (el.value != ContainerInputArray[3]
                 || (el.value == "" && el.id != "alias" && el.id != "qa_contact" && el.id != "bug_mentors")) )
        {

            unhide = true;
        }
        else {
            var set_default = document.getElementById("set_default_" +
                                                      ContainerInputArray[2]);
            if ( set_default ) {
                if(set_default.checked){
                    unhide = true;
                }
            }
        }
    }
    if(unhide){
        YAHOO.util.Dom.addClass(ContainerInputArray[0], 'bz_default_hidden');
        YAHOO.util.Dom.removeClass(ContainerInputArray[1], 'bz_default_hidden');
    }

}

function hideAliasAndSummary(short_desc_value, alias_value) {
    // check the short desc field
    hideEditableField( 'summary_alias_container','summary_alias_input',
                       'editme_action','short_desc', short_desc_value);
    // check that the alias hasn't changed
    var bz_alias_check_array = new Array('summary_alias_container',
                                     'summary_alias_input', 'alias', alias_value);
    YAHOO.util.Event.addListener( window, 'load', checkForChangedFieldValues,
                                 bz_alias_check_array);
}

function showPeopleOnChange( field_id_list ) {
    for(var i = 0; i < field_id_list.length; i++) {
        YAHOO.util.Event.addListener( field_id_list[i],'change', showEditableField,
                                      new Array('bz_qa_contact_edit_container',
                                                'bz_qa_contact_input'));
        YAHOO.util.Event.addListener( field_id_list[i],'change',showEditableField,
                                      new Array('bz_assignee_edit_container',
                                                'bz_assignee_input'));
    }
}

function assignToDefaultOnChange(field_id_list, default_assignee, default_qa_contact) {
    showPeopleOnChange(field_id_list);
    for(var i = 0, l = field_id_list.length; i < l; i++) {
        YAHOO.util.Event.addListener(field_id_list[i], 'change', function(evt, defaults) {
            if (document.getElementById('assigned_to').value == defaults[0]) {
                setDefaultCheckbox(evt, 'set_default_assignee');
            }
            if (document.getElementById('qa_contact')
                && document.getElementById('qa_contact').value == defaults[1])
            {
                setDefaultCheckbox(evt, 'set_default_qa_contact');
            }
        }, [default_assignee, default_qa_contact]);
    }
}

function initDefaultCheckbox(field_id){
    YAHOO.util.Event.addListener( 'set_default_' + field_id,'change', boldOnChange,
                                  'set_default_' + field_id);
    YAHOO.util.Event.addListener( window,'load', checkForChangedFieldValues,
                                  new Array( 'bz_' + field_id + '_edit_container',
                                             'bz_' + field_id + '_input',
                                             'set_default_' + field_id ,'1'));

    YAHOO.util.Event.addListener( window, 'load', boldOnChange,
                                 'set_default_' + field_id );
}

function showHideStatusItems(e, dupArrayInfo) {
    var el = document.getElementById('bug_status');
    // finish doing stuff based on the selection.
    if ( el ) {
        showDuplicateItem(el);

        // Make sure that fields whose visibility or values are controlled
        // by "resolution" behave properly when resolution is hidden.
        var resolution = document.getElementById('resolution');
        if (resolution && resolution.options[0].value != '') {
            resolution.bz_lastSelected = resolution.selectedIndex;
            var emptyOption = new Option('', '');
            resolution.insertBefore(emptyOption, resolution.options[0]);
            emptyOption.selected = true;
        }
        YAHOO.util.Dom.addClass('resolution_settings', 'bz_default_hidden');
        if (document.getElementById('resolution_settings_warning')) {
            YAHOO.util.Dom.addClass('resolution_settings_warning',
                                    'bz_default_hidden');
        }
        YAHOO.util.Dom.addClass('duplicate_display', 'bz_default_hidden');


        if ( (el.value == dupArrayInfo[1] && dupArrayInfo[0] == "is_duplicate")
             || bz_isValueInArray(close_status_array, el.value) )
        {
            YAHOO.util.Dom.removeClass('resolution_settings',
                                       'bz_default_hidden');
            YAHOO.util.Dom.removeClass('resolution_settings_warning',
                                       'bz_default_hidden');

            // Remove the blank option we inserted.
            if (resolution && resolution.options[0].value == '') {
                resolution.removeChild(resolution.options[0]);
                resolution.selectedIndex = resolution.bz_lastSelected;
            }
        }

        if (resolution) {
            bz_fireEvent(resolution, 'change');
        }
    }
}

function showDuplicateItem(e) {
    var resolution = document.getElementById('resolution');
    var bug_status = document.getElementById('bug_status');
    var dup_id = document.getElementById('dup_id');
    if (resolution) {
        if (resolution.value == 'DUPLICATE' && bz_isValueInArray( close_status_array, bug_status.value) ) {
            // hide resolution show duplicate
            YAHOO.util.Dom.removeClass('duplicate_settings',
                                       'bz_default_hidden');
            YAHOO.util.Dom.addClass('dup_id_discoverable', 'bz_default_hidden');
            // check to make sure the field is visible or IE throws errors
            if( ! YAHOO.util.Dom.hasClass( dup_id, 'bz_default_hidden' ) ){
                dup_id.focus();
                dup_id.select();
            }
        }
        else {
            YAHOO.util.Dom.addClass('duplicate_settings', 'bz_default_hidden');
            YAHOO.util.Dom.removeClass('dup_id_discoverable',
                                       'bz_default_hidden');
            dup_id.blur();
        }
    }
    YAHOO.util.Event.preventDefault(e); //prevents the hyperlink from going to the URL in the href.
}

function setResolutionToDuplicate(e, duplicate_or_move_bug_status) {
    var status = document.getElementById('bug_status');
    var resolution = document.getElementById('resolution');
    YAHOO.util.Dom.addClass('dup_id_discoverable', 'bz_default_hidden');
    status.value = duplicate_or_move_bug_status;
    bz_fireEvent(status, 'change');
    resolution.value = "DUPLICATE";
    bz_fireEvent(resolution, 'change');
    YAHOO.util.Event.preventDefault(e);
}

function setDefaultCheckbox(e, field_id) {
    var el = document.getElementById(field_id);
    var elLabel = document.getElementById(field_id + "_label");
    if( el && elLabel ) {
        el.checked = "true";
        YAHOO.util.Dom.setStyle(elLabel, 'font-weight', 'bold');
    }
}

function boldOnChange(e, field_id){
    var el = document.getElementById(field_id);
    var elLabel = document.getElementById(field_id + "_label");
    if( el && elLabel ) {
        if( el.checked ){
            YAHOO.util.Dom.setStyle(elLabel, 'font-weight', 'bold');
        }
        else{
            YAHOO.util.Dom.setStyle(elLabel, 'font-weight', 'normal');
        }
    }
}

function updateCommentTagControl(checkbox, field) {
    if (checkbox.checked) {
        YAHOO.util.Dom.addClass(field, 'bz_private');
    } else {
        YAHOO.util.Dom.removeClass(field, 'bz_private');
    }
}

/**
 * Reset the value of the classification field and fire an event change
 * on it.  Called when the product changes, in case the classification
 * field (which is hidden) controls the visibility of any other fields.
 */
function setClassification() {
    var classification = document.getElementById('classification');
    var product = document.getElementById('product');
    var selected_product = product.value;
    var select_classification = all_classifications[selected_product];
    classification.value = select_classification;
    bz_fireEvent(classification, 'change');
}

/**
 * Says that a field should only be displayed when another field has
 * a certain value. May only be called after the controller has already
 * been added to the DOM.
 */
function showFieldWhen(controlled_id, controller_id, values) {
    var controller = document.getElementById(controller_id);
    // Note that we don't get an object for "controlled" here, because it
    // might not yet exist in the DOM. We just pass along its id.
    YAHOO.util.Event.addListener(controller, 'change',
        handleVisControllerValueChange, [controlled_id, controller, values]);
}

/**
 * Called by showFieldWhen when a field's visibility controller
 * changes values.
 */
function handleVisControllerValueChange(e, args) {
    var controlled_id = args[0];
    var controller = args[1];
    var values = args[2];

    var label_container =
        document.getElementById('field_label_' + controlled_id);
    var field_container =
        document.getElementById('field_container_' + controlled_id);
    var selected = false;
    for (var i = 0; i < values.length; i++) {
        if (bz_valueSelected(controller, values[i])) {
            selected = true;
            break;
        }
    }

    if (selected) {
        YAHOO.util.Dom.removeClass(label_container, 'bz_hidden_field');
        YAHOO.util.Dom.removeClass(field_container, 'bz_hidden_field');
    }
    else {
        YAHOO.util.Dom.addClass(label_container, 'bz_hidden_field');
        YAHOO.util.Dom.addClass(field_container, 'bz_hidden_field');
    }
}

function showValueWhen(controlled_field_id, controlled_value_ids,
                       controller_field_id, controller_value_id)
{
    var controller_field = document.getElementById(controller_field_id);
    // Note that we don't get an object for the controlled field here,
    // because it might not yet exist in the DOM. We just pass along its id.
    YAHOO.util.Event.addListener(controller_field, 'change',
        handleValControllerChange, [controlled_field_id, controlled_value_ids,
                                    controller_field, controller_value_id]);
}

function handleValControllerChange(e, args) {
    var controlled_field = document.getElementById(args[0]);
    var controlled_value_ids = args[1];
    var controller_field = args[2];
    var controller_value_id = args[3];

    var controller_item = document.getElementById(
        _value_id(controller_field.id, controller_value_id));

    for (var i = 0; i < controlled_value_ids.length; i++) {
        var item = getPossiblyHiddenOption(controlled_field,
                                           controlled_value_ids[i]);
        if (item.disabled && controller_item && controller_item.selected) {
            YAHOO.util.Dom.removeClass(item, 'bz_hidden_option');
            item.disabled = false;
        }
        else if (!item.disabled && controller_item && !controller_item.selected) {
            YAHOO.util.Dom.addClass(item, 'bz_hidden_option');
            if (item.selected) {
                item.selected = false;
                bz_fireEvent(controlled_field, 'change');
            }
            item.disabled = true;
        }
    }
}

// A convenience function to generate the "id" tag of an <option>
// based on the numeric id that Bugzilla uses for that value.
function _value_id(field_name, id) {
    return 'v' + id + '_' + field_name;
}

/**
 * Autocompletion
 */

$(function() {
    function searchComplete() {
        var that = $(this);
        that.data('counter', that.data('counter') - 1);
        if (that.data('counter') === 0)
            that.removeClass('autocomplete-running');
        if (document.activeElement != this)
            that.devbridgeAutocomplete('hide');
    }

    var options_user = {
        appendTo: $('#main-inner'),
        forceFixPosition: true,
        paramName: 'match',
        deferRequestBy: 250,
        minChars: 2,
        noCache: true,
        tabDisabled: true,
        autoSelectFirst: true,
        preserveInput: true,
        triggerSelectOnValidInput: false,
        lookup: (query, done) => {
            // Note: `async` doesn't work for this `lookup` function, so use a `Promise` chain instead
            Bugzilla.API.get('user/suggest', { match: query })
                .then(({ users }) => users.map(({ name, real_name, requests, gravatar }) => ({
                    value: name,
                    data: { email: name, real_name, requests, gravatar },
                })))
                .catch(() => [])
                .then(suggestions => done({ suggestions }));
        },
        formatResult: function(suggestion) {
            const $input = this;
            const { email, real_name, requests, gravatar } = suggestion.data;
            const request_type = $input.getAttribute('data-request-type');
            const { blocked, pending } = requests ? (requests[request_type] || {}) : {};
            const image = gravatar ? `<img itemprop="image" alt="" src="${gravatar}">` : '';
            const description = blocked ? '<span class="icon" aria-hidden="true"></span> Requests blocked' :
                pending ? `${pending} pending ${request_type}${pending === 1 ? '' : 's'}` : '';

            return `<div itemscope itemtype="http://schema.org/Person">${image} ` +
                `<span itemprop="name">${real_name.htmlEncode()}</span> ` +
                `<span class="minor" itemprop="email">${email.htmlEncode()}</span> ` +
                `<span class="minor${blocked ? ' blocked' : ''}" itemprop="description">${description}</span></div>`;
        },
        onSelect: function (suggestion) {
            const $input = this;
            const { real_name, requests } = suggestion.data;
            const is_multiple = !!$input.getAttribute('data-multiple');
            const request_type = $input.getAttribute('data-request-type');
            const { blocked } = requests ? (requests[request_type] || {}) : {};

            if (blocked) {
                window.alert(`${real_name} is not accepting ${request_type} requests at this time. ` +
                    'If you’re in a hurry, ask someone else for help.');
            } else if (is_multiple) {
                const _values = $input.value.split(',').map(value => value.trim());

                _values.pop();
                _values.push(suggestion.value);
                $input.value = _values.join(', ') + ', ';
            } else {
                $input.value = suggestion.value;
            }

            $input.focus();
        },
        onSearchStart: function(params) {
            var that = $(this);

            // adding spaces shouldn't initiate a new search
            var query;
            if (that.data('multiple')) {
                var parts = that.val().split(/,\s*/);
                query = parts[parts.length - 1];
            }
            else {
                query = params.match;
            }
            if (query !== $.trim(query))
                return false;

            that.addClass('autocomplete-running');
            that.data('counter', that.data('counter') + 1);
            return true;
        },
        onSearchComplete: searchComplete,
        onSearchError: searchComplete
    };

    // init user autocomplete fields
    $('.bz_autocomplete_user')
        .each(function() {
            const $input = this;
            const is_multiple = !!$input.getAttribute('data-multiple');
            const options = Object.assign({}, options_user);

            options.delimiter = is_multiple ? /,\s*/ : undefined;
            // Override `this` in the relevant functions
            options.formatResult = options.formatResult.bind($input);
            options.onSelect = options.onSelect.bind($input);

            $input.dataset.counter = 0;
            $input.classList.add('bz_autocomplete');
            $(this).devbridgeAutocomplete(options);
        });

    // init autocomplete fields with array of values
    $('.bz_autocomplete_values')
        .each(function() {
            var that = $(this);
            that.devbridgeAutocomplete({
                appendTo: $('#main-inner'),
                forceFixPosition: true,
                lookup: function(query, done) {
                    var values = BUGZILLA.autocomplete_values[that.data('values')];
                    query = query.toLowerCase();
                    var activeValues = document.querySelector('#keywords').value.split(',');
                    activeValues.forEach((o,i,a) => a[i] = a[i].trim());
                    var matchStart =
                        $.grep(values, function(value) {
                            if(!(activeValues.includes(value)))
                                return value.toLowerCase().substr(0, query.length) === query;
                        });
                    var matchSub =
                        $.grep(values, function(value) {
                            if(!(activeValues.includes(value)))
                                return value.toLowerCase().indexOf(query) !== -1 &&
                                    $.inArray(value, matchStart) === -1;
                        });
                    var suggestions =
                        $.map($.merge(matchStart, matchSub), function(suggestion) {
                            return { value: suggestion };
                        });
                    done({ suggestions: suggestions });
                },
                tabDisabled: true,
                delimiter: /,\s*/,
                minChars: 0,
                autoSelectFirst: false,
                triggerSelectOnValidInput: false,
                formatResult: function(suggestion, currentValue) {
                    // disable <b> wrapping of matched substring
                    return suggestion.value.htmlEncode();
                },
                onSearchStart: function(params) {
                    var that = $(this);
                    // adding spaces shouldn't initiate a new search
                    var parts = that.val().split(/,\s*/);
                    var query = parts[parts.length - 1];
                    return query === $.trim(query);
                },
                onSelect: function() {
                    this.value = this.value + ', ';
                    this.focus();
                }
            });
            that.addClass('bz_autocomplete');
        });
});

/**
 * Force the browser to honour the selected option when a page is refreshed,
 * but only if the user hasn't explicitly selected a different option.
 */
function initDirtyFieldTracking() {
    // old IE versions don't provide the information we need to make this fix work
    // however they aren't affected by this issue, so it's ok to ignore them
    if (YAHOO.env.ua.ie > 0 && YAHOO.env.ua.ie <= 8) return;
    var selects = document.getElementById('changeform').getElementsByTagName('select');
    for (var i = 0, l = selects.length; i < l; i++) {
        var el = selects[i];
        var el_dirty = document.getElementById(el.name + '_dirty');
        if (!el_dirty) continue;
        if (!el_dirty.value) {
            var preSelected = bz_preselectedOptions(el);
            if (!el.multiple) {
                preSelected.selected = true;
            } else {
                el.selectedIndex = -1;
                for (var j = 0, m = preSelected.length; j < m; j++) {
                    preSelected[j].selected = true;
                }
            }
        }
        YAHOO.util.Event.on(el, "change", function(e) {
            var el = e.target || e.srcElement;
            var preSelected = bz_preselectedOptions(el);
            var currentSelected = bz_selectedOptions(el);
            var isDirty = false;
            if (!el.multiple) {
                isDirty = preSelected.index != currentSelected.index;
            } else {
                if (preSelected.length != currentSelected.length) {
                    isDirty = true;
                } else {
                    for (var i = 0, l = preSelected.length; i < l; i++) {
                        if (currentSelected[i].index != preSelected[i].index) {
                            isDirty = true;
                            break;
                        }
                    }
                }
            }
            document.getElementById(el.name + '_dirty').value = isDirty ? '1' : '';
        });
    }
}

/**
 * Comment preview
 */

var last_comment_text = '';

async function show_comment_preview(bug_id) {
    var Dom = YAHOO.util.Dom;
    var comment = document.getElementById('comment');
    var preview = document.getElementById('comment_preview');
    const $comment_body = document.querySelector('#comment_preview_text');

    if (!comment || !preview) return;
    if (Dom.hasClass('comment_preview_tab', 'active_comment_tab')) return;

    preview.style.width = (comment.clientWidth - 4) + 'px';
    preview.style.height = comment.offsetHeight + 'px';

    var comment_tab = document.getElementById('comment_tab');
    Dom.addClass(comment, 'bz_default_hidden');
    Dom.removeClass(comment_tab, 'active_comment_tab');
    comment_tab.setAttribute('aria-selected', 'false');

    var preview_tab = document.getElementById('comment_preview_tab');
    Dom.removeClass(preview, 'bz_default_hidden');
    Dom.addClass(preview_tab, 'active_comment_tab');
    preview_tab.setAttribute('aria-selected', 'true');

    Dom.addClass('comment_preview_error', 'bz_default_hidden');

    if (last_comment_text == comment.value)
        return;

    Dom.addClass('comment_preview_text', 'bz_default_hidden');
    Dom.removeClass('comment_preview_loading', 'bz_default_hidden');

    try {
        const { html } = await Bugzilla.API.post('bug/comment/render', { id: bug_id, text: comment.value });

        $comment_body.innerHTML = html;

        // Highlight code if possible
        if (Prism) {
            Prism.highlightAllUnder($comment_body);
        }

        Dom.addClass('comment_preview_loading', 'bz_default_hidden');
        Dom.removeClass('comment_preview_text', 'bz_default_hidden');
        last_comment_text = comment.value;
    } catch ({ message }) {
        Dom.addClass('comment_preview_loading', 'bz_default_hidden');
        Dom.removeClass('comment_preview_error', 'bz_default_hidden');
        Dom.get('comment_preview_error').innerHTML = YAHOO.lang.escapeHTML(message);
    }
}

function show_comment_edit() {
    var comment = document.getElementById('comment');
    var preview = document.getElementById('comment_preview');
    if (!comment || !preview) return;
    if (YAHOO.util.Dom.hasClass(comment, 'active_comment_tab')) return;

    var preview_tab = document.getElementById('comment_preview_tab');
    YAHOO.util.Dom.addClass(preview, 'bz_default_hidden');
    YAHOO.util.Dom.removeClass(preview_tab, 'active_comment_tab');
    preview_tab.setAttribute('aria-selected', 'false');

    var comment_tab = document.getElementById('comment_tab');
    YAHOO.util.Dom.removeClass(comment, 'bz_default_hidden');
    YAHOO.util.Dom.addClass(comment_tab, 'active_comment_tab');
    comment_tab.setAttribute('aria-selected', 'true');
}

/**
 * Comment form keyboard shortcuts
 */

window.addEventListener('DOMContentLoaded', () => {
  const on_mac = navigator.platform === 'MacIntel';
  const $comment = document.querySelector('#comment');
  const $save_button = document.querySelector('.save-btn, #commit');

  if (!$comment || !$save_button) {
    return;
  }

  $comment.addEventListener('keydown', event => {
    const { isComposing, key, altKey, ctrlKey, metaKey, shiftKey } = event;
    const accelKey = on_mac ? metaKey && !ctrlKey : ctrlKey;
    const has_value = /\S/.test($comment.value);

    if (isComposing) {
      return;
    }

    // Accel + Enter = Save
    if (has_value && key === 'Enter' && accelKey && !altKey && !shiftKey) {
      event.preventDefault();
      // Click the Save button to trigger the `submit` event handler
      $save_button.click();
    }
  });
}, { once: true });
