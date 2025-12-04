// Replace download links based on the user’s platform
window.addEventListener('DOMContentLoaded', () => {
  // Android
  if (/\bAndroid\b/.test(navigator.userAgent)) {
    document.querySelector('#downloads-firefox-desktop').hidden = true;
    document.querySelector('#downloads-firefox-android').hidden = false;
  }

  // iOS
  if (/\b(?:iPhone|iPad|iPod)\b/.test(navigator.userAgent)) {
    document.querySelector('#downloads-firefox-desktop').hidden = true;
    document.querySelector('#downloads-firefox-ios').hidden = false;
  }
});
