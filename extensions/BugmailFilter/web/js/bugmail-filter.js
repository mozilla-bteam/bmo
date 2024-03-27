/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

function onFilterFieldChange() {
    if (document.getElementById('field').value == '~') {
        document.getElementById('field_contains_row').classList.remove('bz_default_hidden');
        document.getElementById('field_contains').focus();
        document.getElementById('field_contains').select();
    }
    else {
        document.getElementById('field_contains_row').classList.add('bz_default_hidden');
    }
}

function onFilterProductChange() {
    const $product = document.getElementById('product');
    const $component = document.getElementById('component');

    selectProduct($product, $component, null, null, '__Any__');
    $component.disabled = $product.value == '';
}

function setFilterAddEnabled() {
    document.getElementById('add_filter').disabled =
        (
            document.getElementById('field').value == '~'
            && document.getElementById('field_contains').value == ''
        )
        || document.getElementById('action').value == '';
}

function onFilterRemoveChange() {
  const $remove = document.getElementById('remove');

  if ($remove) {
    $remove.disabled = !document.querySelector('#filters_table input:checked');
  }
}

function showAllFlags(type) {
    document.querySelector(`[data-type="${type}"] .show_all`).classList.add('bz_default_hidden');
    document.querySelector(`[data-type="${type}"] .all_flags`).classList.remove('bz_default_hidden');
}

window.addEventListener('DOMContentLoaded', () => {
    document.getElementById('field').addEventListener('change', onFilterFieldChange);
    document.getElementById('field_contains').addEventListener('keyup', setFilterAddEnabled);
    document.getElementById('product').addEventListener('change', onFilterProductChange);
    document.getElementById('action').addEventListener('change', setFilterAddEnabled);
    onFilterFieldChange();
    onFilterProductChange();
    onFilterRemoveChange();
    setFilterAddEnabled();
});
