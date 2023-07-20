async function verifyMfaTotpCode(event) {
  event.preventDefault();
  document.getElementById("verify_totp_error").classList.add("bz_default_hidden");
  const code = document.getElementById('code');
  try {
    await Bugzilla.API.post('user/mfa/verify_totp_code', {
      mfa_token: code.dataset.token,
      mfa_code:  code.value
    });
    document.getElementById("verify_totp_form").submit();
  }
  catch ({message}) {
    var totp_error = document.getElementById("verify_totp_error");
    totp_error.innerText = message;
    totp_error.classList.remove("bz_default_hidden");
  };
}

window.addEventListener('DOMContentLoaded', () => {
  document.getElementById("verify_totp_form")
    .addEventListener('submit', verifyMfaTotpCode);
});
