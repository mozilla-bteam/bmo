function SetCheckboxes(value) {
  let elements = document.querySelectorAll("input[type='checkbox'][name^='id_']");
  for (let item of elements) {
    item.checked = value;
  }
}

document.addEventListener("DOMContentLoaded", () => {
  let checkboxes = document.querySelectorAll("input[type='checkbox'][name^='id_']");

  for (let checkbox of checkboxes) {
    checkbox.addEventListener('changed', event => {
      let count = document.querySelectorAll("input[type='checkbox'][name^='id_']:checked").length;
      let background_checkbox = document.getElementById('background');
      if (!background_checkbox) return;
      /* This is just for the frontend. Changing 10 here wouldn't change the max number of foreground bug edits.
       * see process_bug.cgi.
      */
      if (count > 10) {
        background_checkbox.checked = true;
        background_checkbox.disabled = true;
      }
      else {
        background_checkbox.disabled = false;
      }
    });
  }

  let check_all = document.getElementById("check_all");
  let uncheck_all = document.getElementById("uncheck_all");
  if (check_all) {
    check_all.addEventListener("click", event => {
      SetCheckboxes(true);
      event.preventDefault();
    });
  }
  if (uncheck_all) {
    uncheck_all.addEventListener("click", event => {
      SetCheckboxes(false);
      event.preventDefault();
    });
  }
});
