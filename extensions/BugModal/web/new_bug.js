$(document).ready(function() {
        bugzilla_ajax(
                {
                    url: 'rest/bug_modal/products'
                },
                function(data) {
                    $('#product').empty()
                    // populate select menus
                    $.each(data.products, function(key, value) {
                        $('#product').append($('<option>', { value: value.name, text: value.name }));
                    });
                },
                function() {}
            );

        $('#product')
        .change(function(event) {
            $('#product-throbber').show();
            $('#component').attr('disabled', true);
            
            bugzilla_ajax(
                {
                    url: 'rest/bug_modal/components?product=' + encodeURIComponent($('#product').val())
                },
                function(data) {
                    $('#product-throbber').hide();
                    $('#component').attr('disabled', false);
                    $('#component').empty();
                    $.each(data.components, function(key, value) {  
                        $('#component').append($('<option>', { value: value.name, text: value.name }));
                    });
                },
                function() {}
            );
        });
        
    });
