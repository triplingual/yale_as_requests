class AeonRequest

  def self.config_for(json)
    AppConfig[:aeon_fulfillment][json['repository']['_resolved']['repo_code']]
  end


  def self.born_digital?(json)
    !!config_for(json)[:requests_permitted_for_born_digital] &&
      json['jsonmodel_type'] == 'archival_object' &&
      restrictions(json).include?(RESTRICTION_TYPE_BORN_DIGITAL)
  end

  def self.restrictions(json)
    (json['notes'] || []).select {|n| n['type'] == 'accessrestrict' && n.has_key?('rights_restriction')}
      .map {|n| n['rights_restriction']['local_access_restriction_type']}
      .flatten.uniq
  end


  def self.build(json, opts = {})

    repo = opts[:repo] || json['repository']['_resolved']
    resource = opts[:resource] || json['resource']['_resolved']

    cfg = config_for(json)

    out = {}

    out['SystemID'] = cfg.fetch(:aeon_external_system_id, "ArchivesSpace")
    out['ReturnLinkURL'] = "#{AppConfig[:public_proxy_url]}#{json['uri']}"
    out['ReturnLinkSystemName'] = cfg.fetch(:aeon_return_link_label, "ArchivesSpace")
    out['Site'] = cfg.fetch(:aeon_site_code, '')


    # FIXME: ao specific
    out['identifier'] = json['component_id']

    out['publish'] = json['publish']

    # FIXME: I18n?
    out['level'] = json['level']

    # FIXME: strip_mixed_content
    out['title'] = json['title']
    out['uri'] = json['uri']

    out['collection_id'] = [0,1,2,3].map{|ix| resource["id_#{ix}"]}.compact.join('-')
    out['collection_title'] = resource['title']

    out['repo_code'] = repo['repo_code']
    out['repo_name'] = repo['name']

    # FIXME: creators?
    # out['creators'] = ???

    # FIXME: language?
    # out['language'] = json['language']

    out['physical_location_note'] = json['notes']
      .select { |note| note['type'] == 'physloc' and note['content'].present? }
      .map { |note| note['content'] }
      .flatten
      .join("; ")

    out['accessrestrict'] = json['notes']
      .select { |note| note['type'] == 'accessrestrict' and note['subnotes'] }
      .map { |note| note['subnotes'] }
      .flatten
      .map { |subnote| subnote['content'] }
      .flatten
      .join("; ")

    json['dates']
      .select { |date| date.has_key?('expression') }
      .group_by { |date| date['label'] }
      .each { |label, dates|
        out["#{label}_date"] = dates.map { |date| date['expression'] }.join("; ")
      }

    out['restrictions_apply'] = json['restrictions_apply']
    out['display_string'] = json['display_string']

    out['requests'] = json['instances'].map do |instance|
      # FIXME: all instances for now - this might be handled in lua land
      # next if @requested_instance_indexes.nil? || !@requested_instance_indexes.include?(instance.fetch('_index'))

      # this seems like fluff - it's an array folks
      # request_count = request_count + 1

      request = {}

      request["instance_is_representative"] = instance['is_representative']
      request["instance_last_modified_by"] = instance['last_modified_by']
      request["instance_instance_type"] = instance['instance_type']
      request["instance_created_by"] = instance['created_by']

      container = instance['sub_container']
      return request unless container

      request["instance_container_grandchild_indicator"] = container['indicator_3']
      request["instance_container_child_indicator"] = container['indicator_2']
      request["instance_container_grandchild_type"] = container['type_3']
      request["instance_container_child_type"] = container['type_2']
      request["instance_container_last_modified_by"] = container['last_modified_by']
      request["instance_container_created_by"] = container['created_by']

      request["instance_top_container_ref"] = container['top_container']['ref']

      top_container = container['top_container']['_resolved']

      request["instance_top_container_long_display_string"] = top_container['long_display_string']
      request["instance_top_container_last_modified_by"] = top_container['last_modified_by']
      request["instance_top_container_display_string"] = top_container['display_string']
      request["instance_top_container_restricted"] = top_container['restricted']
      request["instance_top_container_created_by"] = top_container['created_by']
      request["instance_top_container_indicator"] = top_container['indicator']
      request["instance_top_container_barcode"] = top_container['barcode']
      request["instance_top_container_type"] = top_container['type']
      request["instance_top_container_uri"] = top_container['uri']

      collection = top_container['collection']
      request["instance_top_container_collection_identifier"] = collection.map { |c| c['identifier'] }.join("; ")
      request["instance_top_container_collection_display_string"] = collection.map { |c| c['display_string'] }.join("; ")

      series = top_container['series']
      request["instance_top_container_series_identifier"] = series.map { |s| s['identifier'] }.join("; ")

      request["instance_top_container_series_display_string"] = series.map { |s| s['display_string'] }.join("; ")

      request.delete_if{|k,v| v.nil? || v.is_a?(String) && v.empty?}

      request

    end


    # adapted from the original record mapper
    # not sure if it is used at yale so removing for now
    # untested!
    # if (udf_setting = cfg[:user_defined_fields])
    #   if user_defined_fields = json['user_defined']
    #     if udf_setting == true
    #       is_whitelist = false
    #       fields = []
    #     else
    #       if udf_setting.is_a?(Array)
    #         is_whitelist = true
    #         fields = udf_setting
    #       else
    #         is_whitelist = udf_setting[:list_type].intern == :whitelist
    #         fields = udf_setting[:values] || udf_setting[:fields] || []
    #       end
    #     end

    #     user_defined_fields.each do |field_name, value|
    #       if (is_whitelist ? fields.include?(field_name) : fields.exclude?(field_name))
    #         out["user_defined_#{field_name}"] = value
    #       end
    #     end
    #   end
    # end

    out
  end



  # from yale_aeon_utils

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
