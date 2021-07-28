class AeonAccessionMapper < AeonRecordMapper

    register_for_record_type(Accession)

    def initialize(accession)
        super(accession)
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

    def json_fields
        mappings = super

        json = self.record.json
        return mappings unless json

        accession_identifier = [ json['id_0'], json['id_1'], json['id_2'], json['id_3'] ]
        mappings['accession_id'] = accession_identifier
            .reject {|id_comp| id_comp.blank?}
            .join('-')

        # CallNumber (collection_id)
        mappings['collection_id'] = [0,1,2,3].map {|n| json["id_#{n}"]}.join(' ')
        if json.has_key?('user_defined')
            mappings['collection_id'] += '; ' + json['user_defined']['text_1'] if json['user_defined']['text_1']
        end

        # ItemInfo5 (access restriction notes)
        mappings['ItemInfo5'] = json['access_restrictions_note']

        # ItemInfo6 (use_restrictions_note)
        mappings['ItemInfo6'] = json['use_restrictions_note']

        # ItemInfo7 (extents)
        mappings['ItemInfo7'] = json['extents'].select {|e| !e.has_key?('_inherited')}
                                             .map {|e| "#{e['number']} #{e['extent_type']}"}.join('; ')

        # ItemAuthor (creators)
        # first agent, role='creator'
        creator = json['linked_agents'].select {|a| a['role'] == 'creator'}.first
        mappings['ItemAuthor'] = creator['_resolved']['title'] if creator

        mappings
    end

    # Returns a hash that maps from Aeon OpenURL values to values in the provided record.
    def record_fields
        mappings = super

        if record.use_restrictions_note && record.use_restrictions_note.present?
            mappings['use_restrictions_note'] = record.use_restrictions_note
        end

        if record.access_restrictions_note && record.access_restrictions_note.present?
            mappings['access_restrictions_note'] = record.access_restrictions_note
        end

        mappings['language'] = self.record['language']

        # DocumentType - from settings
        mappings['DocumentType'] = YaleAeonUtils.doc_type(self.repo_settings, mappings['collection_id'])

        # WebRequestForm - from settings
        mappings['WebRequestForm'] = YaleAeonUtils.web_request_form(self.repo_settings, mappings['collection_id'])

        # ItemDate (record.dates.final_expressions)
        mappings['ItemDate'] = self.record.dates.map {|d| d['final_expression']}.join(', ')

        mappings
    end
end
