(function () {
  "use strict";
  function getFormData() {
    return (document.querySelector(
      'input[name="cookie-radio-preference"]:checked',
    ).value === "yes")
      ? true
      : false;
  }
  function setFormData(preference) {
    if (preference === "yes") {
      document
        .getElementById("cookie-radio-preference-yes")
        .setAttribute("checked", "");
      document
        .getElementById("cookie-radio-preference-no")
        .removeAttribute("checked");
    } else {
      document
        .getElementById("cookie-radio-preference-yes")
        .removeAttribute("checked");
      document
        .getElementById("cookie-radio-preference-no")
        .setAttribute("checked", "");
    }
  }
  function onFormSubmit(e) {
    e.preventDefault();
    MozConsentBanner.setConsentCookie(getFormData());
    showSuccessMessage();
  }
  function showSuccessMessage() {
    var e = document.getElementById("cookie-consent-form-submit-success");
    e.style.display = "block";
    e.focus();
  }

  window.addEventListener('DOMContentLoaded', () => {
    document
      .getElementById("cookie-consent-form")
      .addEventListener("submit", onFormSubmit);
    setFormData(MozConsentBanner.getConsentCookie());
  });
})();
