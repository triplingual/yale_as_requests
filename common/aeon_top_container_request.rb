class AeonTopContainerRequest

  def self.build(json, request, opts = {})
    out = request

    out['publish'] = json['is_linked_to_published_record']

    if (collection = json['collection'].first)
      out['collection_id'] = collection['identifier']
      out['collection_title'] = collection['display_string']
    end

    restrictions_notes = json['active_restrictions'].map {|a| a['linked_records']['_resolved']['notes']}.flatten
    out['accessrestrict'] = AeonRequest.access_restrictions_content(restrictions_notes)
    out['ItemInfo5'] = out['accessrestrict']
    out['ItemInfo8'] = AeonRequest.local_access_restrictions(restrictions_notes)

    out['ItemInfo12'] = out['collection_title']

    out['DocumentType'] = AeonRequest.doc_type(json, out['collection_id'])
    out['WebRequestForm'] = AeonRequest.web_request_form(json, out['collection_id'])

    out['CallNumber'] = json['collection'].map {|c| c['identifier']}.join('; ')
    out['ItemInfo14'] = json['collection'].map {|c| c['ref']}.join('; ')

    if cp = json['container_profile']
      out['SubLocation'] = cp['_resolved']['name']
    end

    if series = json['series'].first
      out['identifier'] = series['identifier']
      out['publish'] = series['publish']
      out['level'] = series['level_display_string']
      # FIXME: strip_mixed_content
      out['title'] = series['display_string']
      out['uri'] = series['ref']
    end

    out['ItemTitle'] = json['collection'].map { |c| c['display_string'] }.join("; ")


    out['requests'] = [ AeonRequest.build_top_container(json, {}) ]

    out
  end

end
