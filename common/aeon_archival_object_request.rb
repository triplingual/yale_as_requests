class AeonArchivalObjectRequest

  def self.map_request_values(json, mapped, from, to, &block)
    mapped['requests'].each do |r|
      if block_given?
        r[to] = if from == :all
                  tc = json['instances']
                    .find{|i| i['sub_container'] && i['sub_container']['top_container']['ref'] == r['instance_top_container_ref']}['sub_container']['top_container']['_resolved']
                  yield [r, tc]
                else
                  r[from]
                end
      else
        r[to] = r[from]
      end
    end
  end

  # kind of replicating some pui madness - gross
  def self.citation(json, mapped)
    cite = ''
    if note = json['notes'].find{|n| n['type'] == 'prefercite'}
      cite = note['subnotes'].map{|sn| sn['content']}.join('; ')
    else
      cite = "#{json['component_id']}, " if json['component_id']
      cite += mapped['title']

      cite += ', '
      cite += json['instances'].select{|i| i['sub_container']}.map{|i|
        sc = i['sub_container']
        tc = sc['top_container']['_resolved']
        (tc['type'] ? I18n.t("enumerations.container_type.#{tc['type']}", :default => tc['type']) : 'Container') + ': ' + tc['indicator'] +
        ['2', '3'].select{|l| sc["indicator_#{l}"]}.map{|l|
          ', ' + (sc["type_#{l}"] ? I18n.t("enumerations.container_type.#{sc["type_#{l}"]}", :default => sc["type_#{l}"]) : 'Container') +
          ': ' + sc["indicator_#{l}"]
        }.join +
        ' - ' + tc['onsite_status'].capitalize
      }.join('; ')

      cite += ". #{mapped['collection_title']}, #{mapped['collection_id']}. #{mapped['repo_name']}."
    end

    "#{cite}  #{AppConfig[:public_proxy_url]}#{json['uri']}  Accessed  #{Time.now.strftime("%B %d, %Y")}"
  end


  def self.build(json, request)
    out = request

    out['EADNumber'] = request['ReturnLinkURL']

    out['repository_processing_note'] = json['repository_processing_note'] if json['repository_processing_note']

    out['ItemInfo14'] = json['resource']['ref']

    creator = json['linked_agents'].find{|a| a['role'] == 'creator'}
    out['ItemAuthor'] = ['_resolved']['title'] if creator

    out['ItemInfo5'] = AeonRequest.access_restrictions_content(json['notes'])

    out['ItemInfo6'] = json['notes'].select {|n| n['type'] == 'userestrict'}
      .map {|n| n['subnotes'].map {|s| s['content']}.join(' ')}
      .join(' ')

    out['ItemInfo7'] = json['extents'].select {|e| !e.has_key?('_inherited')}
      .map {|e| "#{e['number']} #{e['extent_type']}"}.join('; ')

    out['ItemInfo8'] = AeonRequest.local_access_restrictions(json['notes'])

    map_request_values(json, out, 'instance_top_container_restricted', 'ItemInfo1') {|v| v == true ? 'Y' : 'N'}
    map_request_values(json, out, 'instance_top_container_uri', 'ItemInfo10')
    map_request_values(json, out, 'instance_top_container_display_string', 'ItemVolume') {|v| v[0, (v.index(':') || v.length)]}


    map_request_values(json, out, :all, 'ItemEdition') do |req, _|
      edition = ''
      ['child', 'grandchild'].map {|lvl|
        (req["instance_container_#{lvl}_type"] || '').downcase == 'folder' ? req["instance_container_#{lvl}_indicator"] : nil
      }.compact.join('; ')
    end

    map_request_values(json, out, :all, 'ItemISxN') do |req, _|
      edition = ''
      ['child', 'grandchild'].map {|lvl|
        (req["instance_container_#{lvl}_type"] || '').downcase == 'item_barcode' ? req["instance_container_#{lvl}_indicator"] : nil
      }.compact.join('; ')
    end

    map_request_values(json, out, :all, 'ItemIssue') do |req, top_container|
      top_container['series']
        .select{|s| s['identifier']}
        .map{|s| s['level_display_string'] + ' ' + s['identifier'] + '. ' + s['display_string']}.join('; ')
    end

    map_request_values(json, out, 'instance_top_container_barcode', 'ReferenceNumber')

    map_request_values(json, out, :all, 'ItemInfo11') do |req, top_container|
      loc = top_container['container_locations'].find{|l| l['status'] == 'current'}
      loc ? loc['ref'] : ''
    end

    map_request_values(json, out, :all, 'Location') do |req, top_container|
      loc = top_container['container_locations'].find{|l| l['status'] == 'current'}
      loc ? loc['_resolved']['title'].sub(/\[\d{5}, /, '[') : ''
    end

    map_request_values(json, out, :all, 'SubLocation') do |req, top_container|
      cp = top_container['container_profile']
      cp ? cp['_resolved']['name'] : ''
    end

    # FIXME: this seems odd - leaving out for now
    # map_request_values(json, out, 'Location', 'instance_top_container_long_display_string')

    out['component_id'] = json['component_id']
    out['ItemTitle'] = out['collection_title']
    out['DocumentType'] = AeonRequest.doc_type(AeonRequest.config_for(json), out['collection_id'])
    out['WebRequestForm'] = AeonRequest.web_request_form(AeonRequest.config_for(json), out['collection_id'])
    out['ItemSubTitle'] = out['title']
    out['ItemCitation'] = citation(json, out)

    out['ItemDate'] = json['dates'].map {|d|
      I18n.t("enumerations.date_label.#{d['label']}") + '  ' + (d['expression'] || ([d['begin'], d['end']].compact.join(' - ')))
    }.join(', ')

    out['ItemInfo13'] = out['component_id']

    json['external_ids'].select{|ei| ei['source'] == 'local_surrogate_call_number'}.map do |ei|
      out['collection_id'] += '; ' + ei['external_id']
    end

    out['CallNumber'] = out['collection_id']

    out
  end
end
