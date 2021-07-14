$(document).ready(function() {
    $('#disabled-button-wrapper').tooltip({html:true});

    $('#aeon_request_selector_modal').on('click', 'button', function() {
        $('#aeon_request_selector_modal').modal('hide');
    });

    $('#aeon_request_button').on('click', function() {
        $('#aeon_request_selector_modal .modal-body').empty();

        $('#aeon_request_selector_modal').modal('show');

        $.ajax({
            url: APP_PATH + 'aeon/aeon-request-popup',
            method: 'post',
            data: {
                uri: $(this).data('uri'),
            },
            success: function(html) {
                $('#aeon_request_selector_modal .modal-body').html(html);
            },
            error: function(jqXHR, textStatus, errorThrown) {
                $('#aeon_request_selector_modal .modal-body').html(errorThrown);

                if (jqXHR.responseText) {
                    $('#aeon_request_selector_modal .modal-body').append('<div>' + jqXHR.responseText + '</div>');
                }
            }
        })
    });
});
