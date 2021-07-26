$(function() {
  var setup_inline_request_form = function(uri) {
    const modal = $('#inline_request_modal');
    modal.find('.action-btn').remove();

    $('#inline-aeon-request-form').html('Retrieving request information ...');

    modal.modal('show');

    $.ajax(APP_PATH + "plugin/yale_aeon_mappings/inline_aeon_request_form", {
      data: {
        uri: uri
      },
      type: "GET",
    }).done(function(form) {
      const request_form = $('#inline-aeon-request-form');
      request_form.html(form);
      new AeonRequestForm(request_form.find('form:first'));
    }).fail(function() {
      $('#inline-aeon-request-form').html('Unable to retrieve request information');
      $('#inline_request_modal').find('.action-btn').attr('disabled', true);
    });
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
