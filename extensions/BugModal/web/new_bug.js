$(document).ready(function() {
    bugzilla_ajax(
            {
                url: 'rest/bug_modal/products'
            },
            function(data) {
                $('#product').empty()
                $('#product').append($('<option>', { value: 'Select Product', text: 'Select Product' }));
                // populate select menus
                $.each(data.products, function(key, value) {
                    $('#product').append($('<option>', { value: value.name, text: value.name }));
                });
            },
            function() {}
        );

    $('#component').empty()
    $('#component').append($('<option>', { value: 'Select Component', text: 'Select Component' }));
    $('#version').empty()
    $('#version').append($('<option>', { value: 'Select Version', text: 'Select Version' }));

    $('#product')
    .change(function(event) {
        $('#product-throbber').show();
        $('#component').attr('disabled', true);
        $('#version').attr('disabled', true);
        $("#product option[value='Select Product']").remove();
        bugzilla_ajax(
            {
                url: 'rest/bug_modal/product_info?product=' + encodeURIComponent($('#product').val())
            },
            function(data) {
                $('#product-throbber').hide();
                $('#component').attr('disabled', false);
                $('#component').empty();
                $('#component').append($('<option>', { value: 'Select Component', text: 'Select Component' }));
                $('#comp_desc').text('Select a component to read its description.');
                $.each(data.components, function(key, value) {  
                    $('#component').append('<option value=' + value.name + ' desc=' + value.description.split(' ').join('_') + '>' + value.name + '</option>');
                });
                $('#version').attr('disabled', false);
                $('#version').empty();
                $('#version').append($('<option>', { value: 'Select Version', text: 'Select Version' }));
                $.each(data.versions, function(key, value) {  
                    $('#version').append('<option value=' + value.name.split(' ').join('_') + '>' + value.name + '</option>');
                });
            },
            function() {}
        );
    });
    $('#component')
    .change(function(event) {
        $("#component option[value='Select Component']").remove();
        $('#comp_desc').text($('#component').find(":selected").attr('desc').split('_').join(' '));
    });

    $('#version')
    .change(function(event) {
        $("#version option[value='Select Version']").remove();
    });

    $('.create-btn')
        .click(function(event) {
            event.preventDefault();
            if (document.newbugform.checkValidity && !document.newbugform.checkValidity())
                return;
            this.form.submit()
        });
    
});
