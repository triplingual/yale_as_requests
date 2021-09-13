(function(exp) {
    const AeonRequestForm = function($form) {
        this.$form = $form;
        this.$modal = $form.closest('.modal');
        this.init();
    };

    AeonRequestForm.prototype.init = function() {
        const self = this;

        self.$form.on('click', '.aeon_select_all', function() {
            $('#aeonRequestTable').find('tbody :checkbox:not(:checked)').trigger('click');
        });

        self.$form.on('click', '.aeon_clear_all', function() {
            $('#aeonRequestTable').find('tbody :checkbox:checked').trigger('click');
        });

        self.$form.on('click', '.aeon_instance_ckbx', function() {
            if (self.$form.find('table tbody :checkbox:checked').length > 0) {
                self.$form.prop('disabled', false);
                self.$form.find('#aeonFormSubmit').prop('disabled', false);
            } else {
                self.$form.prop('disabled', true);
                self.$form.find('#aeonFormSubmit').prop('disabled', true);
            }
        });

        self.$form.on('submit', function(event) {
            event.preventDefault();

            if (!self.$form.is(':disabled')) {
                $.ajax({
                    url: self.$form.attr('action'),
                    method: 'post',
                    data: new FormData(self.$form[0]),
                    processData: false,
                    contentType: false,
                    success: function(html) {
                        $('#aeonRequestFormWrapper').remove();
                        $(document.body).append('<div id="aeonRequestFormWrapper">');
                        $('#aeonRequestFormWrapper').html(html);
                        $('#aeonRequestFormWrapper form').submit();
                        self.$modal.modal('hide');
                    },
                    error: function(jqXHR, textStatus, errorThrown) {
                        $('#aeonFormSubmit').prop('disabled', false);
                        self.$modal.find('.modal-body').html(errorThrown);

                        if (jqXHR.responseText) {
                            self.$modal.find('.modal-body').append('<div>' + jqXHR.responseText + '</div>');
                        }
                    }
                });

                self.$form.find('#aeonFormSubmit').prop('disabled', true);
            }
        });

        if ($('#aeonRequestTable').find('tbody :checkbox').length === 1) {
            self.$form.find('.aeon_select_all').trigger('click');
        }
    }

    exp.AeonRequestForm = AeonRequestForm;
})(window);

$(document).ready(function() {
    $('#disabled-button-wrapper').tooltip({html:true});

    $('#aeon_request_button').on('click', function() {
        $('#aeon_request_selector_modal .modal-body').empty();

        $('#aeon_request_selector_modal').modal('show');

        $.ajax({
            url: APP_PATH + 'aeon/aeon-request-popup',
            method: 'post',
            data: {
                uri: $(this).data('uri'),
            },
            success: function (html) {
                $('#aeon_request_selector_modal .modal-body').html(html);
                new AeonRequestForm($('#aeon_request_selector_modal .modal-body form'));
            },
            error: function (jqXHR, textStatus, errorThrown) {
                $('#aeon_request_selector_modal .modal-body').html(errorThrown);
            }
        });
    });
});
