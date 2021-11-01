class AeonArchivalObjectMapper < AeonRecordMapper

    register_for_record_type(ArchivalObject)

    def initialize(archival_object)
        super(archival_object)
    end

    def system_information
        mapped = super

        # Should ask that AUG update the Aeon database at the time this mapping goes into place.
        # If so, they'd just need to move over data from ItemInfo2 to EADNumber for the ArchivesSpace requests up until that date.
        mapped['EADNumber'] = mapped['ReturnLinkURL']

        # Site (repo_code)
        # handled by :site in config

        mapped
    end

    # Override of #show_action? from AeonRecordMapper
    def show_action?
        return false if !super
        return self.requestable_based_on_archival_record_level?
    end

    # Override for AeonRecordMapper json_fields method.
    def json_fields
        mappings = super

        json = self.record.json
        if !json
            return mappings
        end

        if json['repository_processing_note'] && json['repository_processing_note'].present?
            mappings['repository_processing_note'] = json['repository_processing_note']
        end

        # These apply to all requests because their data comes from the ao

        # ItemInfo14 (previously EADNumber) (resource.ref)
        mappings['ItemInfo14'] = json['resource']['ref']

        # ItemCitation (preferred citation note - now using #cite exclusively it seems)
        # mappings['ItemCitation'] = json['notes'].select {|n| n['type'] == 'prefercite'}
        #                                       .map {|n| n['subnotes'].map {|s| s['content']}.join(' ')}
        #                                       .join(' ')

        # ItemAuthor (creators)
        # first agent, role='creator'
        creator = json['linked_agents'].select {|a| a['role'] == 'creator'}.first
        mappings['ItemAuthor'] = creator['_resolved']['title'] if creator

        # ItemInfo5 (access restriction notes)
        mappings['ItemInfo5'] = YaleAeonUtils.access_restrictions_content(json['notes'])

        # ItemInfo6 (use_restrictions_note)
        mappings['ItemInfo6'] = json['notes'].select {|n| n['type'] == 'userestrict'}
                                           .map {|n| n['subnotes'].map {|s| s['content']}.join(' ')}
                                           .join(' ')

        # ItemInfo7 (extents)
        mappings['ItemInfo7'] = json['extents'].select {|e| !e.has_key?('_inherited')}
                                             .map {|e| "#{e['number']} #{e['extent_type']}"}.join('; ')

        # ItemInfo8 (access restriction types)
        mappings['ItemInfo8'] = YaleAeonUtils.local_access_restrictions(json['notes'])


        # The remainder are per request fields

        # ItemInfo1 (y/n overview for restrictions; going with the ASpace-defined version of restricted; note, though, that the Aeon plugin didn't need to split these values out for multiple containers.)
        map_request_values(mappings, 'instance_top_container_restricted', 'ItemInfo1') do |r|
            r == true ? 'Y' : 'N'
        end

        # ItemInfo10 (top_container uri)
        map_request_values(mappings, 'instance_top_container_uri', 'ItemInfo10')

        # ItemVolume (top_containers type + indicator)
        # need to add "Box" if missing? we're going to add the data to the source for now. might want to revist that.
        map_request_values(mappings, 'instance_top_container_display_string', 'ItemVolume') {|v| v[0, (v.index(':') || v.length)]}

        # update:  now we're mapping folders whether they occur as a child or a grandchild.  if both, they'll be combined with a semi-colon.
        # shouldn't need flatten and uniq at all, just in case there are multiple instances (e.g. b1, f1; b1; f1, then we don't need to have 1; 1 when 1 would do, right?)
        map_request_values(mappings, 'instance_top_container_uri', 'ItemEdition') do |uri|
            valid_types = ['Folder', 'folder']
            sub = json['instances'].select {|i| i.has_key?('sub_container') && i['sub_container'].has_key?('top_container')}
                                   .select {|i| i['sub_container']['top_container']['ref'] == uri}
                                   .map{|i| i['sub_container']}
            if sub
                folders = sub.select {|i| valid_types.include?(i['type_2'])}
                             .map {|i| i['indicator_2']}
                folders += sub.select {|i| valid_types.include?(i['type_3'])}
                              .map {|i| i['indicator_3']}
                folders = folders.flatten.uniq.join('; ')
            else
                ''
            end
        end

        # and here we're mapping those hacky item_barcodes to Aeon.
        map_request_values(mappings, 'instance_top_container_uri', 'ItemISxN') do |uri|
            sub = json['instances'].select {|i| i.has_key?('sub_container') && i['sub_container'].has_key?('top_container')}
                                   .select {|i| i['sub_container']['top_container']['ref'] == uri}
                                   .map{|i| i['sub_container']}
            if sub
                ibs = sub.select {|i| i['type_2'] == 'item_barcode'}
                         .map {|i| i['indicator_2']}
                ibs += sub.select {|i| i['type_3'] == 'item_barcode'}
                          .map {|i| i['indicator_3']}
                ibs = ibs.flatten.uniq.join('; ')
            else
                ''
            end
        end

        #ItemIssue
        #(instance_top_container_series_identifier + instance_top_container_series_display_string)
        # also need series_level_display_string ?
        # check and see if we need to convert the identifiers to roman numerals.  e.g. 1 -> I, but keeping other things as is like "accession 2018 etc"
        map_request_values(mappings, 'instance_top_container_uri', 'ItemIssue') do |uri|
            tc = JSON.parse(self.record.raw['_resolved_top_container_uri_u_sstr'][uri].first['json'])

            if tc
                series_info = []
                series_info += tc['series'].select {|i| i['identifier'].present? }
                                           .map {|i| i['level_display_string'] + ' ' + i['identifier'] + '. ' + i['display_string']}

                series = []
                series = series_info.join('; ')
            else
                ''
            end
        end

        # ReferenceNumber (top_container barcode)
        map_request_values(mappings, 'instance_top_container_barcode', 'ReferenceNumber')

        # Location (location uris)
        # there is an open_url mapping on the aeon side that is blatting this
        # with the value in instance_top_container_long_display_string
        # so below, we blat the blatter!
        #
        # now:
        # Location
        # ItemInfo11 (location uri)
        map_request_values(mappings, 'instance_top_container_uri', 'ItemInfo11') do |v|
            tc = json['instances'].select {|i| i.has_key?('sub_container') && i['sub_container'].has_key?('top_container')}
                                  .map {|i| resolved_top_container_for_uri(i['sub_container']['top_container']['ref'])}
                                  .select {|t| t['uri'] == v}.first

            if tc
                loc = tc['container_locations'].select {|l| l['status'] == 'current'}.first
                loc ? loc['ref'] : ''
            else
                ''
            end
        end
        map_request_values(mappings, 'instance_top_container_uri', 'Location') do |v|
            tc = JSON.parse(self.record.raw['_resolved_top_container_uri_u_sstr'][v].first['json'])

            if tc
                loc = tc['container_locations'].select {|l| l['status'] == 'current'}.first
                if loc
                    # until we create an ASpace plugin to control how the location title is constructed, we're going to remove any 5-digit location barcodes
                    # using the sub method below.
                    loc['_resolved']['title'].sub(/\[\d{5}, /, '[')
                else
                    ''
                end
            else
                ''
            end
        end

        #mdc: and now we map SubLocations to accomodate previously-instituted mappings for container profiles.
        map_request_values(mappings, 'instance_top_container_uri', 'SubLocation') do |v|
            tc = json['instances'].select {|i| i.has_key?('sub_container') && i['sub_container'].has_key?('top_container')}
                                  .map {|i| resolved_top_container_for_uri(i['sub_container']['top_container']['ref'])}
                                  .select {|t| t['uri'] == v}.first
            if tc
                cp = tc.dig('container_profile', '_resolved', 'name') || ''
            else
                ''
            end
        end

        # blat the blatter
        map_request_values(mappings, 'Location', 'instance_top_container_long_display_string')

        mappings
    end

    # Returns a hash that maps from Aeon OpenURL values to values in the provided record.
    def record_fields
        mappings = super

        mappings['component_id'] = self.record['component_id']

        # ItemTitle (title)
        # handled in super?  maybe not for bulk requests
        #we're now mapping collection title to ItemTitle. Keep an eye out on that mapping, and also see about updating the Aeon merge feature, since the ItemTitle field is the only field retained in a merge.
        mappings['ItemTitle'] = mappings['collection_title']

        # DocumentType - from settings
        mappings['DocumentType'] = YaleAeonUtils.doc_type(self.repo_settings, mappings['collection_id'])

        # WebRequestForm - from settings
        mappings['WebRequestForm'] = YaleAeonUtils.web_request_form(self.repo_settings, mappings['collection_id'])

        # ItemSubTitle (record.request_item.hierarchy)
        #mapped['ItemSubTitle'] = strip_mixed_content(self.record.request_item.hierarchy.join(' / '))
        mappings['ItemSubTitle'] = mappings['title']

        # ItemCitation (record.request_item.cite)
        mappings['ItemCitation'] = self.record.request_item.cite

        # ItemDate (record.dates.final_expressions)
        mappings['ItemDate'] = self.record.dates.map {|d| d['final_expression']}.join(', ')

        # no longer mapping collection title here. leaving this as example to show how the hierarchical title was grabbed previously.
        #mapped['ItemInfo12'] = strip_mixed_content(self.record.request_item.hierarchy.join(' / '))

        # ItemInfo13: including the component unique identifier field
        mappings['ItemInfo13'] = mappings['component_id']

        # Append external_ids with source = 'local_surrogate_call_number' to 'collection_id'
        self.record.json['external_ids'].select{|ei| ei['source'] == 'local_surrogate_call_number'}.map do |ei|
            mappings['collection_id'] += '; ' + ei['external_id']
        end

        StatusUpdater.update('Yale Aeon Last Request', :good, "Mapped: #{mappings['uri']}")

        mappings
    end

    def map
        if request_type == AeonRecordMapper::REQUEST_TYPE_READING_ROOM
            super
        elsif request_type == AeonRecordMapper::REQUEST_TYPE_PHOTODUPLICATION
            # HACK: It turns out we want to map to different forms within Aeon, so really we
            # want one mapping per (ASpaceRecordType, AeonForm).  Currently we only have one
            # mapper per ASpaceRecordType, so we're going to force it to do double duty with
            # this ugly if statement.
            #
            # NOTE: self.record in this context is the PUI version of the AO
            # (/repositories/123/archival_objects/456#pui).

            selected_instances = Array(@requested_instance_indexes)

            result = {}.merge(self.system_information)

            resource = archivesspace.get_record(self.record.json.fetch('resource').fetch('ref'))
            result['CallNumber'] = resource.four_part_identifier.compact.join('-')

            # Series for all instances get loaded into ItemIssue
            result['ItemIssue'] =
                selected_instances.map {|instance_idx|
                instance = self.record.json.fetch('instances', []).fetch(instance_idx)
                if (top_container_ref = instance.dig('sub_container', 'top_container', 'ref'))
                  resolved_top_container_for_uri(top_container_ref).fetch('series', [])
                    .map {|series| series.fetch('display_string')}
                end
            }.flatten
             .uniq
             .compact
             .join('; ')

            # ReferenceNumber (top_container barcode)
            result['ReferenceNumber'] = selected_instances.map {|instance_idx|
                instance = self.record.json.fetch('instances', []).fetch(instance_idx)
                instance.dig('sub_container', 'top_container', '_resolved', 'barcode')
                if (top_container_ref = instance.dig('sub_container', 'top_container', 'ref'))
                    resolved_top_container_for_uri(top_container_ref).fetch('barcode', nil)
                end
            }.compact.join('; ')

            selected_instance_labels = selected_instances.map {|instance_idx|
                instance = self.record.json.fetch('instances', []).fetch(instance_idx)

                top_container_display_string = nil

                if (top_container_ref = instance.dig('sub_container', 'top_container', 'ref'))
                    top_container_display_string = resolved_top_container_for_uri(top_container_ref).fetch('display_string', nil)
                end

                next if top_container_display_string.nil?

                sub_container = instance.fetch('sub_container')

                label_parts = []
                label_parts << top_container_display_string
                label_parts << "Folder %s" % [sub_container['indicator_2']] if sub_container['type_2'] == 'folder'
                label_parts << "Folder %s" % [sub_container['indicator_3']] if sub_container['type_3'] == 'folder'

                label_parts.compact.join(" > ")
            }.compact

            result['ItemVolume'] = selected_instance_labels.map {|s| s.gsub(/:.*/, '')}.join('; ')

            result['ItemTitle'] = self.record.display_string

            creator = self.record.json['linked_agents'].select {|a| a['role'] == 'creator'}.first
            result['ItemAuthor'] = creator['_resolved']['title'] if creator

            non_pui_ao = ao = archivesspace.get_record(self.record.json.fetch('uri') + '#pui')

            result['ItemInfo5'] = YaleAeonUtils.access_restrictions_content(non_pui_ao.json['notes'])

            result['ItemInfo6'] = self.record.json['notes'].select {|n| n['type'] == 'userestrict'}
                                                           .map {|n| n['subnotes'].map {|s| s['content']}.join(' ')}
                                                           .join(' ')

            result['ItemInfo8'] = YaleAeonUtils.local_access_restrictions(non_pui_ao.json['notes'])

            result['ItemDate'] = ASUtils.wrap(non_pui_ao.dates).map {|d| d['final_expression']}.join('; ')

            result['ItemCitation'] = self.record.request_item.cite

            result
        else
            raise "Unknown request type: #{request_type}"
        end
    end

    private

    # FIXME is it ok for the from_val to be nil? (PG not super sure)
    def map_request_values(mapped, from, to, &block)
        mapped['requests'].each do |r|
            ix = r['Request']
            from_val = r["#{from}_#{ix}"]
            new_val = yield r["#{from}_#{ix}"] if !from_val.nil? && block_given?
            r["#{to}_#{ix}"] = new_val || from_val
        end
    end
end
