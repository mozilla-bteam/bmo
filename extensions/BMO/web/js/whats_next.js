var auto_refresh_interval_id = null;

function updateAutoRefresh() {
  var auto_refresh_element = document.getElementById('auto_refresh');
  if (auto_refresh_element.checked) {
    setCookie('whats_next_auto_refresh', 1);
    auto_refresh_interval_id = setInterval(() => {
      window.location.reload();
    }, 600000);
  }
  else {
    setCookie('whats_next_auto_refresh', 0);
    clearInterval(auto_refresh_interval_id);
  }
}

function setCookie(name, value) {
  document.cookie = name + "=" + (value ? 1 : 0)  + "; path=/";
}

function getCookie(name) {
  var nameEQ = name + "=";
  var ca = document.cookie.split(';');
  for(var i=0; i < ca.length; i++) {
    var c = ca[i];
    while (c.charAt(0)==' ') {
      c = c.substring(1, c.length);
    }
    if (c.indexOf(nameEQ) == 0) {
      return c.substring(nameEQ.length, c.length);
    }
  }
  return null;
}

window.addEventListener('load', () => {
  var auto_refresh_element = document.getElementById('auto_refresh');
  if (getCookie('whats_next_auto_refresh') == 1) {
    auto_refresh_element.checked =  true;
  }
  updateAutoRefresh();
  auto_refresh_element.onchange(updateAutoRefresh);
});
