/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

async function verifyMfaTotpCode(event) {
  event.preventDefault();
  document.getElementById("verify-totp-error").classList.add("bz_default_hidden");
  const code = document.getElementById('code');
  try {
    await Bugzilla.API.post('user/mfa/verify_totp_code', {
      mfa_token: code.dataset.token,
      mfa_code:  code.value
    });
    document.getElementById("verify-totp-form").submit();
  }
  catch ({message}) {
    var totp_error = document.getElementById("verify-totp-error");
    totp_error.innerText = message;
    totp_error.classList.remove("bz_default_hidden");
  };
}

window.addEventListener('DOMContentLoaded', () => {
  document.getElementById("verify-totp-form")
    .addEventListener('submit', verifyMfaTotpCode);
});
