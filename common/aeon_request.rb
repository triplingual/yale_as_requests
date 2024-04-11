require 'nokogiri'

require_relative 'aeon_archival_object_request'
require_relative 'aeon_top_container_request'

class AeonRequest

  def self.request_for(json)
    {
      'archival_object' => AeonArchivalObjectRequest,
      'top_container' => AeonTopContainerRequest,
    }[json['jsonmodel_type']]
  end

  def self.config_for(json)
    repo_code = json.dig('repository','_resolved','repo_code')

    raise "No resolved repository on record: #{json['uri']}" if repo_code.nil?

    # force lowercase as per original aeon_fulfillment plugin
    repo_code = repo_code.downcase

    if AppConfig[:aeon_fulfillment].has_key?(repo_code)
      AppConfig[:aeon_fulfillment].fetch(repo_code)
    else
      raise "No AppConfig[:aeon_fulfillment] entry for repo: #{repo_code}"
    end
  end

  def self.build(json, opts = {})
    out = {}

    cfg = config_for(json)

    out['repo_code'] = json['repository']['_resolved']['repo_code']
    out['repo_name'] = json['repository']['_resolved']['name']

    out['SystemID'] = cfg.fetch(:aeon_external_system_id, "ArchivesSpace")
    out['ReturnLinkURL'] = "#{AppConfig[:public_proxy_url]}#{json['uri']}"
    out['ReturnLinkSystemName'] = cfg.fetch(:aeon_return_link_label, "ArchivesSpace")
    out['Site'] = cfg.fetch(:aeon_site_code, '')

    out['EADNumber'] = out['ReturnLinkURL']

    out['uri'] = json['uri']

    # FIXME: creators?
    # out['creators'] = ???

    # FIXME: language?
    # out['language'] = json['language']

    out['display_string'] = json['display_string']

    request_for(json).build(json, out, opts)
  end


  def self.build_requests(instances, opts = {})
    instances.map do |instance|
      request = {}

      request["instance_is_representative"] = instance['is_representative']
      request["instance_last_modified_by"] = instance['last_modified_by']
      request["instance_instance_type"] = instance['instance_type']
      request["instance_created_by"] = instance['created_by']

      container = instance['sub_container']
      next request unless container

      request["instance_container_grandchild_indicator"] = container['indicator_3']
      request["instance_container_child_indicator"] = container['indicator_2']
      request["instance_container_grandchild_type"] = container['type_3']
      request["instance_container_child_type"] = container['type_2']
      request["instance_container_last_modified_by"] = container['last_modified_by']
      request["instance_container_created_by"] = container['created_by']

      request["instance_top_container_ref"] = container['top_container']['ref']

      request['ItemFolder'] = ['2', '3'].map {|lvl|
        (container["type_#{lvl}"] || '').downcase == 'folder' ? container["indicator_#{lvl}"] : nil
      }.compact.join('; ')

      request['ItemISxN'] = ['2', '3'].map {|lvl|
        (container["type_#{lvl}"] || '').downcase == 'item_barcode' ? container["indicator_#{lvl}"] : nil
      }.compact.join('; ')

      # if opts[:resolved_top_containers] take this JSON as it is fully resolved
      top_container_ref = container['top_container']['ref']
      resolved_top_container = opts.fetch(:resolved_top_containers, {})
                                   .fetch(top_container_ref, container['top_container']['_resolved'])

      AeonRequest.build_top_container(resolved_top_container, request)

      request.delete_if{|k,v| v.nil? || v.is_a?(String) && v.empty?}

      request
    end
  end

  def self.build_top_container(json, request)
    # tidy up series display strings before we start
    json['series'].each { |s| s['display_string'] = AeonRequest.strip_mixed_content(s['display_string']) }

    request["instance_top_container_long_display_string"] = json['long_display_string']
    request["instance_top_container_last_modified_by"] = json['last_modified_by']
    request["instance_top_container_display_string"] = json['display_string']
    request["instance_top_container_restricted"] = json['restricted']
    request["instance_top_container_created_by"] = json['created_by']
    request["instance_top_container_indicator"] = json['indicator']
    request["instance_top_container_barcode"] = json['barcode']
    request["instance_top_container_type"] = json['type']
    request["instance_top_container_uri"] = json['uri']

    request["instance_top_container_collection_identifier"] = json['collection'].map { |c| c['identifier'] }.join("; ")
    request["instance_top_container_collection_display_string"] = json['collection'].map { |c| c['display_string'] }.join("; ")

    request["instance_top_container_series_identifier"] = json['series'].map { |s| s['identifier'] }.join("; ")
    request["instance_top_container_series_display_string"] = json['series'].map { |s| s['display_string'] }.join("; ")

    request["ReferenceNumber"] = request["instance_top_container_barcode"]

    request['TopContainerRestriction'] = json['restricted'] ? 'Y' : 'N'

    request['ItemVolume'] = json['display_string'][0, (json['display_string'].index(':') || json['display_string'].length)]
    request['TopContainerURI'] = json['uri']
    request["ItemSeries"] = json['series'].map{|s| s['level_display_string'] + ' ' + s['identifier'] + '. ' + s['display_string']}.join('; ')

    if (loc = json['container_locations'].find{|cl| cl['status'] == 'current'})
      if (resolved_location = loc['_resolved'])
        request["Location"] = resolved_location['title'].sub(/\[\d{5}, /, '[')
        request['instance_top_container_long_display_string'] = request['Location']
      end

      # Location URI
      request["LocationURI"] = loc['ref']
    else
      # added this so that we don't wind up with the default Aeon mapping here, which maps the top container long display name to the location.
      request['instance_top_container_long_display_string'] = nil
    end

    request
  end

  # adapted from the original record mapper
  # not sure if it is used at yale so removing for now
  # untested!
  def self.build_user_defined_fields(udf)
    if (udf_setting = cfg[:user_defined_fields])
      if user_defined_fields = json['user_defined']
        if udf_setting == true
          is_whitelist = false
          fields = []
        else
          if udf_setting.is_a?(Array)
            is_whitelist = true
            fields = udf_setting
          else
            is_whitelist = udf_setting[:list_type].intern == :whitelist
            fields = udf_setting[:values] || udf_setting[:fields] || []
          end
        end

        user_defined_fields.each do |field_name, value|
          if (is_whitelist ? fields.include?(field_name) : fields.exclude?(field_name))
            out["user_defined_#{field_name}"] = value
          end
        end
      end
    end
  end


  # from yale_aeon_utils

  def self.doc_type(json, id)
    resource_id_map(config_for(json)[:document_type_map], id)
  end


  def self.web_request_form(json, id)
    resource_id_map(config_for(json)[:web_request_form_map], id)
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
         .join('; ')
  end


  # nicked verbatim from the pui
  def self.strip_mixed_content(in_text)
    return if !in_text

    # Don't fire up nokogiri if there's no mixed content to parse
    unless in_text.include?("<")
      return in_text
    end

    in_text = in_text.gsub(/ & /, ' &amp; ')
    @frag = Nokogiri::XML.fragment(in_text)

    @frag.content
  end

end
