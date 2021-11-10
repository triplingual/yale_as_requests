require 'record_inheritance'

require_relative '../../common/aeon_request'
require_relative '../../common/aeon_archival_object_request'

class ArchivesSpaceService < Sinatra::Base

  RecordInheritance.prepare_schemas

  Endpoint.get('/plugins/aeon_request')
    .description("Map records into an aeon request")
    .params(["uris", [String], "A list of record uris to map"])
    .permissions([])
    .returns([200, "OK"]) \
  do

    resolve = [
               'repository',
               'resource',
               'top_container',
               'top_container::container_locations',
               'top_container::container_profile',
               'ancestors',
               'linked_agents',
              ]

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
          jsons = URIResolver.resolve_references(model.sequel_to_jsonmodel(objs), resolve)
          if RecordInheritance.has_type?(type)
            jsons = jsons.map do |json|
              RecordInheritance.merge(json, :remove_ancestors => true)
            end
          end
          out += jsons
        end
      end
    end

    json_response(out.map{|json| AeonArchivalObjectRequest.build(json, AeonRequest.build(json))})
  end


  def find_model_by_jsonmodel_type(type)
    ASModel.all_models.find {|model|
      jsonmodel = model.my_jsonmodel(true)
      jsonmodel && jsonmodel.record_type == type
    }
  end

end
