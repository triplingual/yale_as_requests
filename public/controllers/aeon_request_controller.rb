class AeonRequestController < ApplicationController
  def popup
    uri = params[:uri]

    return render status: 400, text: 'uri param required' if uri.nil?

    record = archivesspace.get_record(params[:uri], {
      'resolve[]' => ['repository:id', 'resource:id@compact_resource', 'top_container_uri_u_sstr:id', 'linked_instance_uris:id', 'digital_object_uris:id'],
    })
    mapper = AeonRecordMapper.mapper_for(record)

    return render status: 400, text: 'Action not supported for record' if mapper.hide_button?
    return render status: 400, text: 'Action not available for record' unless mapper.show_action?

    render partial: 'aeon/aeon_request_popup', locals: {
      record: record,
      mapper: mapper,
    }
  end
end
