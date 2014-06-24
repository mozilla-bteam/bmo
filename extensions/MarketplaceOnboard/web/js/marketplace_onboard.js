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
        var top_required_fields = {
            "business_name": "Please enter a value for the in-country business name\n",
            "region": "Please select a value for the launch area\n",
            "language": "Please select a value for language\n",
            "launch_date": "Please enter a value for anticipated launch date\n",
            "content_restrictions": "Please select a value for content restrictions\n",
            "content_laws": "Please select a value for content laws\n",
            "content_rating_system": "Please select a value describing if you have a content rating system\n",
            "want_for_launch": "Please select a value describing if you will want this for the launch\n",
        };

        var alert_text = '';
        for (field in top_required_fields) {
            if (!MOB.isFilledOut(field)) {
                alert_text += top_required_fields[field];
            }
        }

        if (MOB.fieldValue('region') == 'Other' && !MOB.fieldValue('region_other')) {
            alert_text += "Please enter a value for the other region\n";
        }

        if (MOB.fieldValue('language') == 'Other' && !MOB.fieldValue('language_other')) {
            alert_text += "Please enter a value for the other language\n";
        }

        if (MOB.fieldValue('content_restrictions') == 'Yes') {
            if (!MOB.isFilledOut('content_policy')) {
                alert_text += "Please enter a value for content policy\n";
            }
            if (!MOB.isFilledOut('content_policy_mandatory')) {
                alert_text += "Please select whether the content policy is mandatory or suggested\n";
            }
        }

        if (MOB.fieldValue('content_laws') == 'Yes') {
            if (!MOB.isFilledOut('content_laws_info')) {
                alert_text += "Please enter a value for content law regulatory bodies\n";
            }
        }

        if (MOB.fieldValue('content_rating_system') == 'Yes') {
            if (!MOB.isFilledOut('content_rating_system_info')) {
                alert_text += "Please enter a value for content rating system information\n";
            }
            if (!MOB.isFilledOut('content_rating_system_type')) {
                alert_text += "Please enter a value for what type of content the rating system applies to\n";
            }
            if (!MOB.isFilledOut('age_restrictions')) {
                alert_text += "Please select a value for requiring age restrictions on accounts\n";
            }
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
