var initial = {}
var comp_desc = {}
var product_name = '';

var component_load = function(product) {
    $('#product-throbber').show();
    $('#component').attr('disabled', true);
    bugzilla_ajax(
        {
            url: 'rest/bug_modal/product_info?product=' + encodeURIComponent(product)
        },
        function(data) {
            $('#product-throbber').hide();
            $('#component').attr('disabled', false);
            $('#comp_desc').text('Select a component to read its description.');
            var selectize = $("#component")[0].selectize;
            selectize.clear();
            selectize.clearOptions();
            selectize.load(function(callback) {
                callback(data.components)
            });

            for (var i in data.components)
                comp_desc[data.components[i]["name"]] = data.components[i]["description"];

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
}

function changedesc(element) {
    if (element.checked) {
        $('#file-desc' + $(element).attr('data-no')).css('display', 'none');
        $('#file-desc-edit' + $(element).attr('data-no')).css('display', 'inline-block');
    }
    else {
        $('#file-desc' + $(element).attr('data-no')).css('display', 'inline-block');
        $('#file-desc-edit' + $(element).attr('data-no')).css('display', 'none');
        $('input[name="description' + $(element).attr('data-no') + '"]').val($('#file-desc' + $(element).attr('data-no')).text());
    }
}

$(document).ready(function() {
    var product_name = window.location.hash? window.location.hash.substr(1) : null;
    bugzilla_ajax(
            {
                url: 'rest/bug_modal/initial_field_values'
            },
            function(data) {
                initial = data
                if (product_name) {
                    for (product in initial.products) {
                        if (initial.products[product].name.toLowerCase() === product_name.toLowerCase()) {
                            $("#product_wrap").html('<input name="product" type="hidden" id="product"><h3 style="padding-left:20px;" id="product_name_heading">Hello</h3>')
                            $("#product").val(initial.products[product].name);
                            $("#product_name_heading").text(initial.products[product].name);
                            component_load(initial.products[product].name);
                            return;
                        }
                    }
                }
                var $product_sel = $("#product").selectize({
                    valueField: 'name',
                    labelField: 'name',
                    placeholder: 'Product',
                    searchField: 'name',
                    options: [],
                    preload: true,
                    create: false,
                    load: function(query, callback) {
                        callback(initial.products);
                    }
                });
            },
            function() {
                alert("Network issues. Please refresh the page and try again");
            }
        );
    var component_sel = $("#component").selectize({
        valueField: 'name',
        labelField: 'name',
        placeholder: 'Component',
        searchField: 'name',
        options: [],
    });

    var version_sel = $("#version").selectize({
        valueField: 'name',
        labelField: 'name',
        placeholder: 'Version',
        searchField: 'name',
        options: [],
    });

    var keywords_sel = $("#keywords").selectize({
        delimiter: ', ',
        valueField: 'name',
        labelField: 'name',
        placeholder: 'Keywords',
        searchField: 'name',
        options: [],
        preload: true,
        create: false,
        load: function(query, callback) {
            callback(initial.keywords);
        }
    });
    
    $("#product").on("change", function () {
        component_load($("#product").val());
    });

    component_sel.on("change", function () {
        var selectize = $("#component")[0].selectize;
        $('#comp_desc').text(comp_desc[selectize.getValue()]);
    });

    $('.create-btn')
        .click(function(event) {
            event.preventDefault();
            if (document.newbugform.checkValidity && !document.newbugform.checkValidity()) {
                alert("Required fields are empty");
                return;
            }
            else {
                this.form.submit()
            }
        });

    $('#data').on("change", function () {
        if (!$('#data').val()) {
            return
        } else {
            document.getElementById('reset').style.display = "inline-block";
            $("#description").prop('required',true);
        }
    });
    $('#reset')
        .click(function(event) {
            event.preventDefault();
            document.getElementById('data').value = "";
            document.getElementById('reset').style.display = "none";
            $("#description").prop('required',false);
            $('#file-desc').html('')
        });
    $('#comment-edit-tab')
        .click(function() {
            $('#comment-preview-tab').css("background-color", "#fff");
            $(this).css("background-color", "#eee");
        });
    $('#comment-preview-tab')
        .click(function() {
            $('#comment-edit-tab').css("background-color", "#fff");
            $(this).css("background-color", "#eee");
        });
    $('#comment-edit-tab').click();
    window.onhashchange = function() {
        location.reload();
    }

    $('#data').change(function (event) {
        $('#file-desc').html('<hr>');
        for (var i = 0; i < $(this)[0].files.length; i++) {
            $('#file-desc').append('<span id="file-desc' + i + '">' + $(this)[0].files[i].name + '</span><span style="display:none" id="file-desc-edit' + i + '"><input type= "text" id= "description' + i + '" name= "description' + i + '" size= "60" maxlength= "200" value="' + $(this)[0].files[i].name + '"></span>');
            $('#file-desc').append('<input style="display:inline-block" type="checkbox" data-no="' + i + '" onchange="changedesc(this)" id="file-check' + i + '">Edit desc.<hr>');
        }
    });
});
