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

  AeonClientGridRow = Struct.new(:item_type, :repo_code, :collection_title, :series_title, :call_number, :container_title, :container_barcode, :location, :restrictions, :published, :item_id, :item_title, :request_json) do
    def self.column_definitions
      [
        {
           "title" => "Type",
           "request_field" => "item_type",
           "width" => 100,
           "type" => "string",
        },
        {
          "title" => "Repository",
          "request_field" => "repo_code",
          "width" => 100,
          "type" => "string",
        },
        {
          "title" => "Collection",
          "request_field" => "collection_title",
          "width" => 100,
          "type" => "string",
        },
        {
          "title" => "Series",
          "request_field" => "series_title",
          "width" => 100,
          "type" => "string",
        },
        {
          "title" => "Call Number",
          "request_field" => "call_number",
          "width" => 100,
          "type" => "string",
        },
        {
          "title" => "Container Title",
          "request_field" => "container_title",
          "width" => 100,
          "type" => "string",
        },
        {
          "title" => "Container Barcode",
          "request_field" => "container_barcode",
          "width" => 100,
          "type" => "string",
        },
        {
          "title" => "Location",
          "request_field" => "location",
          "width" => 100,
          "type" => "string",
        },
        {
          "title" => "Restrictions",
          "request_field" => "restrictions",
          "width" => 100,
          "type" => "string",
        },
        {
          "title" => "Location",
          "request_field" => "location",
          "width" => 100,
          "type" => "string",
        },
        {
          "title" => "Item ID",
          "request_field" => "item",
          "width" => 100,
          "type" => "string",
        },
        {
          "title" => "Item Title",
          "request_field" => "item_title",
          "width" => 100,
          "type" => "string",
        },
        {
          "title" => "Request JSON",
          "request_field" => "request_json",
          "width" => 100,
          "type" => "string",
        },
      ]
    end

    def to_h
      super.to_h.map{|k, v| [k, v.to_s]}.to_h
    end
  end

  Container = Struct.new(:top_container_uri, :solr_doc) do
    def to_aeon_grid_row
      top_container_json = ASUtils.json_parse(solr_doc.fetch('json'))
      request = AeonRequest.build(top_container_json)

      AeonClientGridRow.new('Container',
                            top_container_json.dig('repository', '_resolved', 'repo_code'),
                            ASUtils.wrap(top_container_json.dig('collection')).map{|c| c['display_string']}.join('; '),
                            ASUtils.wrap(top_container_json.dig('series')).map{|s| s['display_string']}.join('; '),
                            request.dig('CallNumber'),
                            top_container_json.dig('display_string'),
                            top_container_json.dig('barcode'),
                            solr_doc.dig('location_display_string_u_sstr'),
                            request.dig('ItemInfo5'),
                            !!solr_doc.dig('publish'),
                            '',
                            '',
                            request.to_json)
                       .to_h
    end
  end

  BornDigitalItem = Struct.new(:archival_object_uri, :solr_doc, :inherited_json) do
    def to_aeon_grid_row
      request = AeonRequest.build(inherited_json)

      AeonClientGridRow.new('BornDigital',
                            inherited_json.dig('repository', '_resolved', 'repo_code'),
                            inherited_json.dig('resource','_resolved','title'),
                            (ASUtils.wrap(inherited_json['ancestors']).find{|itm| itm['level'] == 'series'} || {}).dig('_resolved', 'display_string'),
                            request.dig('CallNumber'),
                            '',
                            '',
                            '',
                            request.dig('ItemInfo5'),
                            !!solr_doc.dig('publish'),
                            inherited_json['component_id'],
                            solr_doc['title'],
                            request.to_json)
                       .to_h
    end
  end

  ItemWithTopContainer = Struct.new(:archival_object_uri, :solr_doc, :inherited_json, :top_container_uri) do
    def to_aeon_grid_row
      request = AeonRequest.build(inherited_json)

      request['requests'] = ASUtils.wrap(request.fetch('requests'))
                                   .select{|req| req.fetch('instance_top_container_uri', nil) == top_container_uri}

      target_instance = inherited_json['instances'].find{|instance| instance.dig('sub_container', 'top_container', 'ref') == top_container_uri} || {}
      container_location = ASUtils.wrap(target_instance.dig('sub_container', 'top_container', '_resolved', 'container_locations')).find{|cl| cl['status'] == 'current'} || {}

      AeonClientGridRow.new('Container',
                            inherited_json.dig('repository', '_resolved', 'repo_code'),
                            inherited_json.dig('resource','_resolved','title'),
                            (ASUtils.wrap(inherited_json['ancestors']).find{|itm| itm['level'] == 'series'} || {}).dig('_resolved', 'display_string'),
                            request.dig('CallNumber'),
                            target_instance.dig('sub_container', 'top_container', '_resolved', 'display_string'),
                            target_instance.dig('sub_container', 'top_container', '_resolved', 'barcode'),
                            container_location.dig('_resolved', 'title'),
                            request.dig('ItemInfo5'),
                            !!solr_doc.dig('publish'),
                            inherited_json['component_id'],
                            solr_doc['title'],
                            request.to_json)
                       .to_h
    end
  end

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
                             Container.new(result.fetch('id'),
                                           result)
                                      .to_aeon_grid_row
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
      inherited_json = RecordInheritance.merge(ao_json)

      # identify those that are born digital
      local_access_restriction_types = inherited_json['notes'].select {|n| n['type'] == 'accessrestrict' && n.has_key?('rights_restriction')}
                                                              .map {|n| n['rights_restriction']['local_access_restriction_type']}
                                                              .flatten.uniq

      if local_access_restriction_types.include?('BornDigital')
        born_digital << BornDigitalItem.new(result.fetch('id'), result, inherited_json).to_aeon_grid_row

        next
      end

      # map those with container instances
      ASUtils.wrap(result['top_container_uri_u_sstr']).each do |top_container_uri|
        ao_to_top_container << ItemWithTopContainer.new(result.fetch('id'),
                                                        result,
                                                        inherited_json,
                                                        top_container_uri)
                                                   .to_aeon_grid_row
      end
    end

    json_response(:columns => AeonClientGridRow.column_definitions,
                  :requests => top_containers + ao_to_top_container + born_digital)
  end


  private

  def find_model_by_jsonmodel_type(type)
    ASModel.all_models.find {|model|
      jsonmodel = model.my_jsonmodel(true)
      jsonmodel && jsonmodel.record_type == type
    }
  end

end
