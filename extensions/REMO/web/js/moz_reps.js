/*global $ */

$(document).ready(function() {
  'use strict';

  var first_time = $("#first_time");
  first_time.prop("checked", true);
  first_time.change(function(evt) {
    if (!this.checked) {
      $("#prior_bug").removeClass("bz_default_hidden");
      $("#dependson").attr("required", true);
    }
    else {
      $("#prior_bug").addClass("bz_default_hidden");
      $("#dependson").removeAttr("required");
    }
  });

  $("#underage").change(function(evt) {
    if (this.checked) {
      $('#underage_warning').removeClass('bz_default_hidden');
      $('#submit').prop("disabled", true);
    }
    else {
      $('#underage_warning').addClass('bz_default_hidden');
      $('#submit').prop("disabled", false);
    }
  });

  $('#submit').click(function () {
    var cc = document.getElementById('cc');
    if (cc.value) {
      cc.setCustomValidity('');
    }
    else {
      cc.setCustomValidity('Please enter at least one Mozilla contributor who can vouch your application');
    }

    $('#short_desc').val(
      "Application Form: " + $('#first_name').val() + ' ' + $('#last_name').val()
    );

    $("tmRequestForm").submit();
  });
});