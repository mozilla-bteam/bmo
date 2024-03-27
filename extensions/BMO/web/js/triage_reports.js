function onSelectProduct() {
  var component = document.getElementById('component');
  if (document.getElementById('product').value == '') {
    bz_clearOptions(component);
    return;
  }
  selectProduct(document.getElementById('product'), component);
  // selectProduct only supports __Any__ on both elements
  // we only want it on component, so add it back in
  try {
    component.add(new Option('__Any__', ''), component.options[0]);
  } catch(e) {
    // support IE
    component.add(new Option('__Any__', ''), 0);
  }
  component.value = '';
}

function onCommenterChange() {
  document.getElementById('commenter_is').classList
    .toggle('hidden', document.getElementById('commenter').value !== 'is');
}

function onLastChange() {
  document.getElementById('last_is_span').classList
    .toggle('hidden', document.getElementById('last').value !== 'is');
}

function onGenerateReport() {
  const $component = document.getElementById('component');
  const $filter_commenter = document.getElementById('filter_commenter');
  const $filter_last = document.getElementById('filter_last');

  if (document.getElementById('product').value == '') {
    alert('You must select a product.');
    return false;
  }
  if ($component.value == '' && !$component.options[0].selected) {
    alert('You must select at least one component.');
    return false;
  }
  if (!($filter_commenter.checked || $filter_last.checked)) {
    alert('You must select at least one comment filter.');
    return false;
  }
  if ($filter_commenter.checked
      && document.getElementById('commenter').value == 'is'
      && document.getElementById('commenter_is').value == '')
  {
    alert('You must specify the last commenter\'s email address.');
    return false;
  }
  if ($filter_last.checked
      && document.getElementById('last').value == 'is'
      && document.getElementById('last_is').value == '')
  {
    alert('You must specify the "comment is older than" date.');
    return false;
  }
  return true;
}

window.addEventListener('DOMContentLoaded', () => {
  onSelectProduct();
  onCommenterChange();
  onLastChange();

  var component = document.getElementById('component');
  if (selected_components.length == 0)
    return;
  component.options[0].selected = false;
  for (var i = 0, n = selected_components.length; i < n; i++) {
    var index = bz_optionIndex(component, selected_components[i]);
    if (index != -1)
      component.options[index].selected = true;
  }
});
