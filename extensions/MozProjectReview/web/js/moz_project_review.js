/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

$(function() {
    'use strict';
    var required_fields = {
        "initial_questions": {
            "short_desc": "Please enter a value for project or feature name in the initial questions section",
            "description": "Please enter a value for description in the initial questions section",
            "key_initiative": "Please select a value for key initiative in the initial questions section",
            "contract_type": "Please select a value for contract type in the initial questions section",
            "mozilla_data": "Please select a value for mozilla data in the initial questions section",
            "vendor_cost": "Please select a value for vendor cost in the initial questions section"
        },
        "key_initiative_other": {
            "key_initiative_other": "Please enter a value for other key initiative in the initial questions section"
        },
        "legal_questions": {
            "legal_priority": "Please select a value for priority in the legal questions section",
            "legal_timeframe": "Please select a value for timeframe in the legal questions section",
            "legal_other_party": "Please enter a value for vendor name in the legal questions section",
            "legal_terminate_contract": "Please select a value for right to terminate contract in the legal questions section",
            "legal_sow_vendor_address": "Please enter a value for SOW vendor address",
            "legal_sow_vendor_email": "Please enter a value for SOW vendor email for notices",
            "legal_sow_vendor_contact": "Please enter a value for SOW vendor contact and email address",
            "legal_sow_vendor_services": "Please enter a value for SOW vendor services description",
            "legal_sow_vendor_deliverables": "Please enter a value for SOW vendor deliverables description",
            "legal_sow_start_date": "Please enter a value for SOW vendor start date",
            "legal_sow_end_date": "Please enter a value for SOW vendor end date",
            "legal_sow_vendor_payment": "Please enter a value for SOW vendor payment amount",
            "legal_sow_vendor_payment_basis": "Please enter a value for SOW vendor payment basis",
            "legal_sow_vendor_payment_schedule": "Please enter a value for SOW vendor payment schedule",
            "legal_sow_vendor_total_max": "Please enter a value for SOW vendor maximum total to be paid",
            "legal_sow_vendor_product_line": "Please enter a value for SOW vendor product line",
            "legal_vendor_services_where": "Please select a value for the vendor services location"
        },
        "legal_vendor_single_country": {
            "legal_vendor_single_country": "Please enter a value for vendor services location country"
        },
        "finance_questions": {
            "finance_purchase_inbudget": "Please enter a value for in budget in the finance questions section",
            "finance_purchase_what": "Please enter a value for what in the finance questions section",
            "finance_purchase_why": "Please enter a value for why in the finance questions section",
            "finance_purchase_risk": "Please enter a value for risk in the finance questions section",
            "finance_purchase_alternative": "Please enter a value for alternative in the finance questions section",
            "finance_purchase_urgency": "Please select a value for purchase timeframe in the finance questions section",
            "finance_purchase_cost": "Please enter a value for total cost in the finance questions section"
        },
    };

    var select_inputs = [
        'contract_type',
        'key_initiative',
        'legal_vendor_services_where',
        'vendor_cost',
    ];

    function init() {
        // Bind the updateSections function to each of the inputs desired
        for (var i = 0, l = select_inputs.length; i < l; i++) {
            $('#' + select_inputs[i]).change(updateSections);
        }
        updateSections();
        $('#mozProjectForm').submit(validateAndSubmit);
    }

    function updateSections(e) {
        if ($('#key_initiative').val() == 'Other') {
            $('#key_initiative_other').show();
            if ($(e.target).attr('id') == 'key_initiative') $('#key_initiative_other').focus();
        } else {
            $('#key_initiative_other').hide();
        }

        if ($('#vendor_cost').val() == '< $25,000 PO Needed'
            || $('#vendor_cost').val() == '> $25,000')
        {
            $('#finance_questions').show();
        } else {
            $('#finance_questions').hide();
        }

        if ($('#legal_vendor_services_where').val() == 'A single country') {
            $('#legal_vendor_single_country').show();
            if ($(e.target).attr('id') == 'legal_vendor_services_where') $('#legal_vendor_single_country').focus();
        } else {
            $('#legal_vendor_single_country').hide();
        }

        var no_sec_review = [
            'Independent Contractor Agreement',
            'Hardware Purchase',
            'Connected Devices Commercial Deal',
            'Firefox Desktop or Mobile Distribution/Bundling Deal',
            'Search Provider Deal',
            'NDA'
        ];
        var contract_type = $('#contract_type').val();
        if (contract_type && $.inArray(contract_type, no_sec_review) == -1) {
            $('#sec_review_questions').show();

        } else {
            $('#sec_review_questions').hide();
        }
    }

    function validateAndSubmit(e) {
        var alert_text = '',
            section    = '',
            field      = '';
        for (section in required_fields) {
            if ($('#' + section).is(':visible')) {
                for (field in required_fields[section]) {
                    if (!isFilledOut(field)) {
                        alert_text += required_fields[section][field] + "\n";
                    }
                }
            }
        }

        if (alert_text) {
            alert(alert_text);
            return false;
        }

        return true;
    }

    //Takes a DOM element id and makes sure that it is filled out
    function isFilledOut(id)  {
        if (!id) return false;
        var str = $('#' + id).val();
        if (!str || str.length == 0) return false;
        return true;
    }

    // date pickers
    $('.date-field').datetimepicker({
        format: 'Y-m-d',
        datepicker: true,
        timepicker: false,
        scrollInput: false,
        lazyInit: false,
        closeOnDateSelect: true
    });
    $('.date-field-img')
        .click(function(event) {
            var id = $(event.target).attr('id').replace(/-img$/, '');
            $('#' + id).datetimepicker('show');
        })

    init();
});
