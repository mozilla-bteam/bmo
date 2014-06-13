/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

var Dom = YAHOO.util.Dom;
var Event = YAHOO.util.Event;

var MOB = {
    required_fields: {
        "country": "Please select a value for the in-country name",
        "launch_area": "Please select a value for the launch area",
        "language": "Please select a value for language",
        "launch_date": "Please enter a value for anticipated launch date",
        "user_info": "Please enter information about yourself",
        "content_restrictions": "Please select a value for content restrictions",
        "content_policy_mandatory": "Please select a value describing if the content policy is mandatory",
        "standards_bodies": "Please select a value describing if there are standards bodies",
        "standards_bodies_info": "Please enter some information about the standards bodies",
        "content_rating_system": "Please select a value describing if you have a content rating system",
        "want_for_launch": "Please select a value describing if you will want this for the launch",
    },

    init: function () {},

    fieldValue: function (id) {
        var field = Dom.get(id);
        if (!field) return '';
        if (field.type == 'text'
            || field.type == 'textarea')
        {
            return field.value;
        }
        return field.options[field.selectedIndex].value;
    },

    showSection: function (select_field, section_id) {
        if (MOB.fieldValue(select_field) == 'Yes') {
            Dom.removeClass(section_id, 'bz_default_hidden');
        }
        else {
            Dom.addClass(section_id ,'bz_default_hidden');
        }
    },

    validateAndSubmit: function () {
        var alert_text = '';
        var section = '';
        for (field in MOB.required_fields) {
            if (!MOB.isFilledOut(field)) {
                alert_text += this.required_fields[field] + "\n";
            }
        }
        if (MOB.fieldValue('country') == 'Other' && !MOB.fieldValue('country_other')) {
            alert_text += 'Please enter a value for the other country';
        }
        if (MOB.fieldValue('launch_area') == 'Other' && !MOB.fieldValue('launch_area_other')) {
            alert_text += 'Please enter a value for the other launch area';
        }
        if (MOB.fieldValue('language') == 'Other' && !MOB.fieldValue('language_other')) {
            alert_text += 'Please enter a value for the other language';
        }
        if (MOB.fieldValue('currency') == 'Other' && !MOB.fieldValue('currency_other')) {
            alert_text += 'Please enter a value for the other currency';
        }
        if (alert_text) {
            alert(alert_text);
            return false;
        }
        return true;
    },

    //Takes a DOM element id and makes sure that it is filled out
    isFilledOut: function (elem_id)  {
        var str = MOB.fieldValue(elem_id);
        return str.length > 0 ? true : false;
    },

    showPage: function (page_number) {
        var pages = Dom.getElementsByClassName('page');
        for (var i = 0, l = pages.length; i < l; i++) {
            var page = pages[i];
            if (page.id == 'page_' + page_number) {
                Dom.removeClass(page, 'bz_default_hidden');
            }
            else {
                Dom.addClass(page, 'bz_default_hidden');
            }
        }
    },

    toggleOther: function (select_field, text_field) {
        text_field_id = text_field + '_other';
        if (MOB.fieldValue(select_field.id) == 'Other') {
            Dom.removeClass(text_field_id, 'bz_default_hidden');
            Dom.get(text_field_id).disabled = false;
        }
        else {
            Dom.addClass(text_field_id, 'bz_default_hidden');
            Dom.get(text_field_id).disabled = true;
        }
    }
};

Event.onDOMReady(function () {
    MOB.init();
});
