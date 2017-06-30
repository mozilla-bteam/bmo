var products = []
var product_info = []

function load_products(query, callback) {
    bugzilla_ajax(
            {
                url: 'rest/bug_modal/products'
            },
            function(data) {
                callback(data.products);
            },
            function() {
                callback();
            }
        );
}

$(document).ready(function() {
    var product_sel = $("#product").selectize({
        valueField: 'name',
        labelField: 'name',
        searchField: 'name',
        options: [],
        preload: true,
        create: false,
        load: load_products
    });
    var component_sel = $("#component").selectize({
        valueField: 'name',
        labelField: 'name',
        searchField: 'name',
        options: [],
    });

    product_sel.on("change", function () {
        component_sel.clearOptions();
        // call component_sel.addOption(data) for each component
        // call component_sel.refreshOptions() when done
    });

    $('.create-btn')
        .click(function(event) {
            event.preventDefault();
            if (document.newbugform.checkValidity && !document.newbugform.checkValidity())
                return;
            this.form.submit()
        });
    
});
