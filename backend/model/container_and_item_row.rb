class ContainerAndItemRow < AeonGridRow

  def initialize(solr_doc, inherited_json, top_container_uri)
    super()

    @request = AeonRequest.build(inherited_json)

    @request['requests'] = ASUtils.wrap(@request.fetch('requests'))
                                  .select{|req| req.fetch('instance_top_container_uri', nil) == top_container_uri}

    target_instance = inherited_json['instances'].find{|instance| instance.dig('sub_container', 'top_container', 'ref') == top_container_uri} || {}
    container_location = ASUtils.wrap(target_instance.dig('sub_container', 'top_container', '_resolved', 'container_locations')).find{|cl| cl['status'] == 'current'} || {}

    set('item_type', 'Container')
    set('repo_code', inherited_json.dig('repository', '_resolved', 'repo_code'))
    set('collection_title', inherited_json.dig('resource','_resolved','title'))
    set('series_title', (ASUtils.wrap(inherited_json['ancestors']).find{|itm| itm['level'] == 'series'} || {}).dig('_resolved', 'display_string'))
    set('call_number', @request.dig('CallNumber'))
    set('container_title', target_instance.dig('sub_container', 'top_container', '_resolved', 'display_string'))
    set('container_barcode', target_instance.dig('sub_container', 'top_container', '_resolved', 'barcode'))
    set('location', container_location.dig('_resolved', 'title'))
    set('restrictions', @request.dig('ItemInfo5'))
    set('published', !!solr_doc.dig('publish'))
    set('item_id', inherited_json['component_id'])
    set('item_title', solr_doc['title'])
  end

end