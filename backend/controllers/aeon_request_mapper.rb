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
    'ancestors::linked_agents',
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


  Endpoint.get('/plugins/yale_as_requests/search')
          .description("Return results to the Aeon Client")
          .params(['q' , String, "Query string"])
          .permissions([:view_all_records])
          .returns([200, "{}"]) \
  do
    base_search_params = {
      :page => 1,
      :page_size => AppConfig.has_key?(:aeon_client_max_results) ? AppConfig[:aeon_client_max_results] : 1000,
    }

    if AppConfig.has_key?(:aeon_client_repo_codes) && !ASUtils.wrap(AppConfig[:aeon_client_repo_codes]).empty?
      repo_query = AdvancedQueryBuilder.new

      repo_lookup = Repository.map {|repo| [repo.repo_code, repo.uri]}.to_h

      ASUtils.wrap(AppConfig[:aeon_client_repo_codes]).each do |repo_code|
        if repo_lookup.has_key?(repo_code)
          repo_query = repo_query.or('repository', repo_lookup.fetch(repo_code), 'text', true)
        else
          raise "repository not found for #{repo_code}"
        end
      end

      base_search_params[:filter] = repo_query.build
    end

    # find top containers
    container_query = AdvancedQueryBuilder.new
                        .and('barcode_u_sstr', params[:q], 'text', true)
                        .or('title', params[:q])

    search_params = base_search_params.merge({
                                               :type => ['top_container'],
                                               :aq => container_query.build,
                                             })

    aeon_grid_rows = Search.search(search_params, nil).fetch('results', [])
                           .map{|result| ContainerRow.new(result) }

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

    Search.search(search_params, nil).fetch('results', []).each_slice(16) do |matching_aos|
      ao_jsonmodels = matching_aos.map {|result|
        JSONModel(:archival_object).from_hash(ASUtils.json_parse(result.fetch('json')),
                                              false, true)
      }

      merged_record_hashes = RecordInheritance.merge(URIResolver.resolve_references(ao_jsonmodels, RESOLVE_PARAMS))

      matching_aos.zip(merged_record_hashes).each do |result, inherited_json|
        # identify those that are born digital
        local_access_restriction_types = inherited_json['notes'].select {|n| n['type'] == 'accessrestrict' && n.has_key?('rights_restriction')}
                                           .map {|n| n['rights_restriction']['local_access_restriction_type']}
                                           .flatten.uniq

        if local_access_restriction_types.include?('BornDigital')
          aeon_grid_rows << BornDigitalRow.new(result, inherited_json)

          next
        end

        # map those with container instances
        ASUtils.wrap(result['top_container_uri_u_sstr']).each do |top_container_uri|
          aeon_grid_rows << ContainerAndItemRow.new(result, inherited_json, top_container_uri)
        end
      end
    end

    json_response(:columns => AeonGridRow.column_definitions,
                  :requests => aeon_grid_rows.map{|row| row.to_aeon_grid_row})
  end


  private

  def find_model_by_jsonmodel_type(type)
    ASModel.all_models.find {|model|
      jsonmodel = model.my_jsonmodel(true)
      jsonmodel && jsonmodel.record_type == type
    }
  end

end
