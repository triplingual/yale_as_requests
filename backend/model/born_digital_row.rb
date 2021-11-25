class BornDigitalRow < AeonGridRow
  def initialize(solr_doc, inherited_json)
    super()

    @request = AeonRequest.build(inherited_json)

    set('item_type', 'BornDigital')
    set('repo_code', inherited_json.dig('repository', '_resolved', 'repo_code'))
    set('collection_title', inherited_json.dig('resource','_resolved','title'))
    set('series_title', (ASUtils.wrap(inherited_json['ancestors']).find{|itm| itm['level'] == 'series'} || {}).dig('_resolved', 'display_string'))
    set('call_number', @request.dig('CallNumber'))
    set('restrictions', @request.dig('ItemInfo5'))
    set('published', !!solr_doc.dig('publish'))
    set('item_id', inherited_json['component_id'])
    set('item_title', solr_doc['title'])
  end
end