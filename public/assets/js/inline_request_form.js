$(function() {
  var setup_inline_request_form = function(uri) {
    $('#aeon_request_selector_modal').remove();
    $(document.body).append($('#aeon_request_modal_template').html());

    $('#aeon_request_selector_modal .modal-body').empty();
    $('#aeon_request_selector_modal').modal('show');

    loadAeonRequestForm(uri, '');
  };

  window.setup_inline_request_form = setup_inline_request_form;
});

function apply_request_buttons_to_infinite() {
    $(document).on('waypointloaded', '.waypoint', function () {

        $(this).find('.information').addClass('row');
        $(this).find('.information h3').addClass('col-sm-9');

        $(this).find('.infinite-item[data-requestable]').each(function () {
            var section = $(this);
            var requestButton = $('<div class="col-sm-3"></div>');

            var link = $('<a class="btn btn-default btn-sm" ' +
                         '   style="margin-bottom: 0.5em;"' +
                         '   href="javascript:void(0);">' +
                         '     <i class="fa fa-external-link fa-external-link-alt"></i>' +
                         '     Request' +
                         '</a>');


            link.on('click', function () {
                setup_inline_request_form(section.data('uri'));
            });

            requestButton.append(link);

            section.find('.information').append(requestButton);
        });
    });

}
