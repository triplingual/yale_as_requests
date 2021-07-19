$(document).ready(function() {
    $('#disabled-button-wrapper').tooltip({html:true});

    // $('#aeon_request_selector_modal').on('click', 'button', function() {
    //     $('#aeon_request_selector_modal').modal('hide');
    // });

    function setupRequestBuilder() {
        const $form = $('#aeon_request_selector_modal .modal-body form');
        $form.on('click', '#aeonToggleAll', function() {
            const checkIt = $(this).is(':checked');
            if (checkIt) {
                $form.find('table tbody :checkbox:not(:checked)').trigger('click');
            } else {
                $form.find('table tbody :checkbox:checked').trigger('click');
            }
        });

        $form.on('click', '.aeon_instance_ckbx', function() {
            if ($form.find('table tbody :checkbox:checked').length > 0) {
                $form.prop('disabled', false);
                $('#aeonFormSubmit').prop('disabled', false);
            } else {
                $form.prop('disabled', true);
                $('#aeonFormSubmit').prop('disabled', true);
            }
        });

        $form.on('submit', function(event) {
            event.preventDefault();

            if (!$form.is(':disabled')) {
                $.ajax({
                    url: $form.attr('action'),
                    method: 'post',
                    data: new FormData($form[0]),
                    processData: false,
                    contentType: false,
                    success: function(html) {
                        $('#aeonRequestFormWrapper').remove();
                        $(document.body).append('<div id="aeonRequestFormWrapper">');
                        $('#aeonRequestFormWrapper').html(html);
                        $('#aeonRequestFormWrapper form').submit();
                        $('#aeon_request_selector_modal').modal('hide');
                    },
                    error: function(jqXHR, textStatus, errorThrown) {
                        $('#aeonFormSubmit').prop('disabled', false);
                        $('#aeon_request_selector_modal .modal-body').html(errorThrown);

                        if (jqXHR.responseText) {
                            $('#aeon_request_selector_modal .modal-body').append('<div>' + jqXHR.responseText + '</div>');
                        }
                    }
                });

                $('#aeonFormSubmit').prop('disabled', true);
            }
        });
    }

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
                setupRequestBuilder();
            },
            error: function(jqXHR, textStatus, errorThrown) {
                $('#aeon_request_selector_modal .modal-body').html(errorThrown);

                if (jqXHR.responseText) {
                    $('#aeon_request_selector_modal .modal-body').append('<div>' + jqXHR.responseText + '</div>');
                }
            }
        });
    });
});
