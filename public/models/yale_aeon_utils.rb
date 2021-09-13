class YaleAeonUtils

  def self.doc_type(settings, id)
    resource_id_map(settings[:document_type_map], id)
  end


  def self.web_request_form(settings, id)
    resource_id_map(settings[:web_request_form_map], id)
  end


  def self.resource_id_map(id_map, id)
    return '' unless id_map

    default = id_map.fetch(:default, '')

    if id
      val = id_map.select {|k,v| id.start_with?(k.to_s)}.values.first
      return val if val
    end

    return default
  end


  def self.local_access_restrictions(notes)
    notes.select {|n| n['type'] == 'accessrestrict' && n.has_key?('rights_restriction')}
         .map {|n| n['rights_restriction']['local_access_restriction_type']}
         .flatten.uniq.join(' ')
  end


  def self.access_restrictions_content(notes)
    notes.select {|n| n['type'] == 'accessrestrict'}
         .map {|n| n['subnotes'].map {|s| s['content']}.join(' ')}
         .join(' ')
  end
end
