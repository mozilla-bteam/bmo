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

    var version_sel = $("#version").selectize({
        valueField: 'name',
        labelField: 'name',
        searchField: 'name',
        options: [],
    });

    product_sel.on("change", function () {
        bugzilla_ajax(
                {
                    url: 'rest/bug_modal/product_info?product=' + encodeURIComponent($('#product').val())
                },
                function(data) {
                    var selectize = $("#component")[0].selectize;
                    selectize.clear();
                    selectize.clearOptions();
                    selectize.load(function(callback) {
                        callback(data.components)
                    });

                    selectize = $("#version")[0].selectize;
                    selectize.clear();
                    selectize.clearOptions();
                    selectize.load(function(callback) {
                        callback(data.versions);
                    });
                },
                function() {
                    alert("Network issues. Please refresh the page and try again");
                }
            );     
    });

    $('.create-btn')
        .click(function(event) {
            event.preventDefault();
            if (document.newbugform.checkValidity && !document.newbugform.checkValidity())
                return;
            this.form.submit()
        });
    
});
