class ContainerRow < AeonGridRow
  def initialize(solr_doc)
    super()

    top_container_json = ASUtils.json_parse(solr_doc.fetch('json'))
    @request = AeonRequest.build(top_container_json)

    set('item_type', 'Container')
    set('repo_code', top_container_json.dig('repository', '_resolved', 'repo_code'))
    set('collection_title', ASUtils.wrap(top_container_json.dig('collection')).map{|c| c['display_string']}.join('; '))
    set('series_title', ASUtils.wrap(top_container_json.dig('series')).map{|s| s['display_string']}.join('; '))
    set('call_number', @request.dig('CallNumber'))
    set('container_title', top_container_json.dig('display_string'))
    set('container_barcode', top_container_json.dig('barcode'))
    set('location', solr_doc.dig('location_display_string_u_sstr', 0))
    set('restrictions', @request.dig('ItemInfo5'))
    set('published', !!solr_doc.dig('publish'))
  end
end