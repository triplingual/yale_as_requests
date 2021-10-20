class AeonRequestController < ApplicationController
  def popup
    uri = params[:uri]

    return render status: 400, text: 'uri param required' if uri.nil?

    record = archivesspace.get_record(params[:uri], {
      'resolve[]' => ['repository:id', 'resource:id@compact_resource', 'top_container_uri_u_sstr:id', 'linked_instance_uris:id', 'digital_object_uris:id'],
    })
    mapper = AeonRecordMapper.mapper_for(record)

    request_type = params[:request_type].to_s.empty? ? nil : params[:request_type]

    return render status: 400, text: 'Action not supported for record' if mapper.hide_button?
    return render status: 400, text: 'Action not available for record' unless mapper.show_action?

    if request_type
      return render status: 400, text: 'Request type not available for record' unless mapper.available_request_types.any?{|rt| rt.fetch(:request_type) == request_type}
    end

    render partial: 'aeon/aeon_request_popup', locals: {
      record: record,
      mapper: mapper,
      request_type: request_type,
    }
  end

  def build
    uri = params[:uri]

    return render status: 400, text: 'uri param required' if uri.nil?

    record = archivesspace.get_record(params[:uri], {
      'resolve[]' => ['repository:id', 'resource:id@compact_resource', 'top_container_uri_u_sstr:id', 'linked_instance_uris:id', 'digital_object_uris:id'],
    })

    mapper = AeonRecordMapper.mapper_for(record)

    return render status: 400, text: 'Action not supported for record' if mapper.hide_button?
    return render status: 400, text: 'Action not available for record' unless mapper.show_action?

    request_type_config = mapper.available_request_types.detect{|rt| rt.fetch(:request_type) == params[:request_type]}

    return render status: 400, text: "Unknown request type: #{params[:request_type]}" if request_type_config.nil?

    mapper.requested_instance_indexes = (params[:instance_idx] || []).map{|idx| Integer(idx)}
    mapper.request_type = request_type_config.fetch(:request_type)

    render partial: 'aeon/aeon_request', locals: {
      record: record,
      mapper: mapper,
      request_type_config: request_type_config,
    }
  end
end
