require 'record_inheritance'
require_relative '../../common/aeon_request'

class ArchivesSpaceService < Sinatra::Base

  RecordInheritance.prepare_schemas

  RESOLVE_PARAMS = [
    'repository',
    'resource',
    'top_container',
    'top_container::container_locations',
    'top_container::container_profile',
    'ancestors',
    'linked_agents',
    'container_profile',
    'container_locations',
    'active_restrictions::linked_records',
  ]

  Endpoint.get('/plugins/aeon_request')
    .description("Map records into an aeon request")
    .params(["uris", [String], "A list of record uris to map"])
    .permissions([])
    .returns([200, "OK"]) \
  do
    out = []

    refs = {}
    params[:uris].each do |uri|
      parsed_uri = JSONModel.parse_reference(uri)
      parsed_repo = JSONModel.parse_reference(parsed_uri[:repository])
      refs[parsed_repo[:id]] ||= {}
      refs[parsed_repo[:id]][parsed_uri[:type]] ||= []
      refs[parsed_repo[:id]][parsed_uri[:type]] << parsed_uri[:id]
    end

    refs.each do |repo_id, types|
      RequestContext.open(:repo_id => repo_id) do
        types.each do |type, ids|
          model = find_model_by_jsonmodel_type(type)
          objs = model.filter(:id => ids).all
          jsons = URIResolver.resolve_references(model.sequel_to_jsonmodel(objs), RESOLVE_PARAMS)
          if RecordInheritance.has_type?(type)
            jsons = jsons.map do |json|
              RecordInheritance.merge(json, :remove_ancestors => true)
            end
          end
          out += jsons
        end
      end
    end

    json_response(out.map{|json| AeonRequest.build(json)})
  end


  Container = Struct.new(:top_container_uri, :top_container_json, :request)
  BornDigitalItem = Struct.new(:archival_object_uri, :archival_object_json, :request)
  ItemWithTopContainer = Struct.new(:archival_object_uri, :top_container_uri, :archival_object_json, :top_container_json, :request)

  Endpoint.get('/plugins/yale_as_requests/search')
          .description("Return results to the Aeon Client")
          .params(['q' , String, "Query string"])
          .permissions([]) # FIXME
          .returns([200, "{}"]) \
  do
    base_search_params = {
      :page => 1,
      :page_size => 1000,
    }

    # find top containers
    container_query = AdvancedQueryBuilder.new
                        .and('barcode_u_sstr', params[:q], 'text', true)
                        .or('title', params[:q])

    search_params = base_search_params.merge({
                                               :type => ['top_container'],
                                               :aq => container_query.build,
                                             })
    top_containers = Search.search(search_params, nil).fetch('results', [])
                           .map{|result|
                             container_json = ASUtils.json_parse(result.fetch('json'))
                             Container.new(result.fetch('id'),
                                           container_json,
                                           AeonRequest.build(container_json))
                            }

    # find archival objects
    ao_query = AdvancedQueryBuilder.new
                                   .and('title', params[:q], 'text', true)
                                   .or('component_id', params[:q], 'text', true)
                                   .or('ref_id', params[:q], 'text', true)
                                   .or('id', params[:q], 'text', true)
                                   .and('types', 'pui', 'text', true, true)

    search_params = base_search_params.merge({
                                               :type => ['archival_object'],
                                               :aq => ao_query.build,
                                             })
    matching_aos = Search.search(search_params, nil).fetch('results', [])

    born_digital = []
    ao_to_top_container = []

    matching_aos.each do |result|
      result_json = ASUtils.json_parse(result.fetch('json'))
      ao_json = URIResolver.resolve_references(JSONModel(:archival_object).from_hash(result_json, false, true), RESOLVE_PARAMS)

      # identify those that are born digital
      inherited_json = RecordInheritance.merge(ao_json, :remove_ancestors => true)
      local_access_restriction_types = inherited_json['notes'].select {|n| n['type'] == 'accessrestrict' && n.has_key?('rights_restriction')}
                                                              .map {|n| n['rights_restriction']['local_access_restriction_type']}
                                                              .flatten.uniq

      if local_access_restriction_types.include?('BornDigital')
        born_digital << BornDigitalItem.new(result.fetch('id'), inherited_json, AeonRequest.build(inherited_json))

        next
      end

      # map those with container instances
      ASUtils.wrap(result['top_container_uri_u_sstr']).each do |top_container_uri|
        request = AeonRequest.build(ao_json)

        request['requests'] = ASUtils.wrap(request.fetch('requests'))
                                .select{|req| req.fetch('instance_top_container_uri', nil) == top_container_uri}

        ao_to_top_container << ItemWithTopContainer.new(result.fetch('id'),
                                                        top_container_uri,
                                                        result_json,
                                                        nil,
                                                        request)
      end
    end

    unless ao_to_top_container.empty?
      containers_by_uri = Search
        .records_for_uris(ao_to_top_container.map{|item| item.top_container_uri}.uniq)
        .fetch('results', [])
        .map{|result| [result.fetch('id'), ASUtils.json_parse(result.fetch('json'))]}
        .to_h

      ao_to_top_container.each do |item|
        item.top_container_json = containers_by_uri.fetch(item.top_container_uri)
      end
    end

    json_response(:top_containers => top_containers.map(&:to_h),
                  :top_containers_with_archival_objects => ao_to_top_container.map(&:to_h),
                  :born_digital_archival_objects => born_digital.map(&:to_h))
  end


  private

  def find_model_by_jsonmodel_type(type)
    ASModel.all_models.find {|model|
      jsonmodel = model.my_jsonmodel(true)
      jsonmodel && jsonmodel.record_type == type
    }
  end

end
