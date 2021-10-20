class AeonRecordMapper

    include ManipulateNode

    @@mappers = {}

    attr_reader :record, :container_instances, :request_type

    REQUEST_TYPE_READING_ROOM = 'reading_room'
    REQUEST_TYPE_PHOTODUPLICATION = 'digitization'

    RESTRICTION_TYPE_NO_REQUEST = 'NoRequest'
    RESTRICTION_TYPE_BORN_DIGITAL = 'BornDigital'

    def initialize(record)
        @record = record
        @container_instances = find_container_instances(record['json'] || {})

        @requested_instance_indexes = nil

        @request_type = REQUEST_TYPE_READING_ROOM
    end

    def disable_for_restriction_types(request_type)
        disable_for_types = [RESTRICTION_TYPE_NO_REQUEST]

        if request_type == REQUEST_TYPE_READING_ROOM
            disable_for_types += ASUtils.wrap(repo_settings[:disable_reading_room_request_for_access_restriction_types])
        elsif request_type == REQUEST_TYPE_PHOTODUPLICATION
            disable_for_types += ASUtils.wrap(repo_settings[:disable_digital_copy_request_for_access_restriction_types])
        end

        disable_for_types
    end

    def container_instances_for_request_type(request_type = @request_type)
        disable_for_types = disable_for_restriction_types(request_type)

        @container_instances.reject do |instance|
            if (top_container_uri = instance.dig('sub_container', 'top_container', 'ref'))
                top_container = resolved_top_container_for_uri(top_container_uri)
                ASUtils.wrap(top_container['active_restrictions']).any? do |restriction|
                    !(ASUtils.wrap(restriction['local_access_restriction_type']) & disable_for_types).empty?
                end
            else
                false
            end
        end
    end

    def request_type_available?(request_type)
        disable_for_types = disable_for_restriction_types(request_type)

        return false if any_local_access_restriction_type?(disable_for_types)

        born_digital? || !container_instances_for_request_type(request_type).empty?
    end

    def available_request_types
        result = []

        if request_type_available?(REQUEST_TYPE_READING_ROOM)
            result << {
              :aeon_uri => "#{repo_settings[:aeon_web_url]}?action=11&type=200",
              :request_type => REQUEST_TYPE_READING_ROOM,
              :button_label => I18n.t('plugins.aeon_fulfillment.request_reading_room_button'),
              :button_help_text => I18n.t('plugins.aeon_fulfillment.request_reading_room_help_text'),
              :extra_params => {'RequestType' => 'Loan'}
            }
        end

        if record.is_a?(Container)
            # Containers can only be requested to the reading room
            return result
        end

        if request_type_available?(REQUEST_TYPE_PHOTODUPLICATION)
            result << {
              :aeon_uri => "#{repo_settings[:aeon_web_url]}?action=10&form=23",
              :request_type => REQUEST_TYPE_PHOTODUPLICATION,
              :button_label => I18n.t('plugins.aeon_fulfillment.request_digital_copy_button'),
              :button_help_text => I18n.t('plugins.aeon_fulfillment.request_digital_copy_help_text'),
              :extra_params => {'RequestType' => 'Copy', 'DocumentType' => 'Default'}
            }
        end

        result
    end

    def requested_instance_indexes=(indexes)
        @requested_instance_indexes = indexes
    end

    def request_type=(request_type)
        @request_type = request_type
    end

    def archivesspace
        ArchivesSpaceClient.instance
    end

    def self.register_for_record_type(type)
        @@mappers[type] = self
    end

    def self.mapper_for(record)
        if @@mappers.has_key?(record.class)
            @@mappers[record.class].new(record)
        else
            Rails.logger.error("Aeon Fulfillment Plugin") { "This ArchivesSpace object type (#{record.class}) is not supported by this plugin." }
            raise
        end
    end

    def repo_code
        self.record.resolved_repository.dig('repo_code').downcase
    end

    def repo_settings
        AppConfig[:aeon_fulfillment][self.repo_code]
    end

    def user_defined_fields
        mappings = {}

        if (udf_setting = self.repo_settings[:user_defined_fields])
            if (user_defined_fields = (self.record['json'] || {})['user_defined'])

                # Determine if the list is a whitelist or a blacklist of fields.
                # If the setting is just an array, assume that the list is a
                # whitelist.
                if udf_setting == true
                    # If the setting is set to "true", then all fields should be
                    # pulled in. This is implemented as a blacklist that contains
                    # 0 values.
                    is_whitelist = false
                    fields = []

                    Rails.logger.debug("Aeon Fulfillment Plugin") { "Pulling in all user defined fields" } if AeonRecordMapper.debug_mode?
                else
                    if udf_setting.is_a?(Array)
                        is_whitelist = true
                        fields = udf_setting
                    else
                        list_type = udf_setting[:list_type]
                        is_whitelist = (list_type == :whitelist) || (list_type == 'whitelist')
                        fields = udf_setting[:values] || udf_setting[:fields] || []
                    end

                    list_type_description = is_whitelist ? 'Whitelist' : 'Blacklist'
                    Rails.logger.debug("Aeon Fulfillment Plugin") { ":allow_user_defined_fields is a #{list_type_description}" } if AeonRecordMapper.debug_mode?
                    Rails.logger.debug("Aeon Fulfillment Plugin") { "User Defined Field #{list_type_description}: #{fields}" } if AeonRecordMapper.debug_mode?
                end

                user_defined_fields.each do |field_name, value|
                    if (is_whitelist ? fields.include?(field_name) : fields.exclude?(field_name))
                        mappings["user_defined_#{field_name}"] = value
                    end
                end
            end
        end

        mappings
    end

    # This method tests whether the button should be hidden. This determination is based
    # on the settings for the repository and defaults to false.
    def hide_button?
        # returning false to maintain the original behavior
        return false unless self.repo_settings

        return true if self.repo_settings[:hide_request_button]
        return true if self.repo_settings[:hide_button_for_accessions] && record.is_a?(Accession)

        return true if any_local_access_restriction_type?(self.repo_settings[:hide_button_for_access_restriction_types])
        return true if any_local_access_restriction_type?(RESTRICTION_TYPE_NO_REQUEST)

        # If record has containers but they are not available for request, it means
        # there is a condition that is blocking requests.
        #
        # We want records without any instances to have a request button that is
        # visible but disabled.
        return true if !@container_instances.empty? && available_request_types.empty?

        false
    end

    def any_local_access_restriction_type?(candidate_types)
        !(ASUtils.wrap(candidate_types) & local_access_restriction_types).empty?
    end

    def local_access_restriction_types
        return @local_access_restriction_types if @local_access_restriction_types

        @local_access_restriction_types = (record.json['notes'] || []).select {|n| n['type'] == 'accessrestrict' && n.has_key?('rights_restriction')}
                                            .map {|n| n['rights_restriction']['local_access_restriction_type']}
                                            .flatten.uniq
    end

    # Determines if the :requestable_archival_record_levels setting is present
    # and exlcudes the 'level' property of the current record. This method is
    # not used by this class, because not all implementations of "abstract_archival_object"
    # have a "level" property that uses the "archival_record_level" enumeration.
    def requestable_based_on_archival_record_level?
        if (req_levels = self.repo_settings[:requestable_archival_record_levels])
            is_whitelist = false
            levels = []

            # Determine if the list is a whitelist or a blacklist of levels.
            # If the setting is just an array, assume that the list is a
            # whitelist.
            if req_levels.is_a?(Array)
                is_whitelist = true
                levels = req_levels
            else
                list_type = req_levels[:list_type]
                is_whitelist = (list_type == :whitelist) || (list_type == 'whitelist')
                levels = req_levels[:values] || req_levels[:levels] || []
            end

            list_type_description = is_whitelist ? 'Whitelist' : 'Blacklist'
            Rails.logger.debug("Aeon Fulfillment Plugin") { ":requestable_archival_record_levels is a #{list_type_description}" } if AeonRecordMapper.debug_mode?
            Rails.logger.debug("Aeon Fulfillment Plugin") { "Record Level #{list_type_description}: #{levels}" } if AeonRecordMapper.debug_mode?

            # Determine the level of the current record.
            level = ''
            if self.record.json
                level = self.record.json['level'] || ''
            end

            Rails.logger.debug("Aeon Fulfillment Plugin") { "Record's Level: \"#{level}\"" } if AeonRecordMapper.debug_mode?

            # If whitelist, check to see if the list of levels contains the level.
            # Otherwise, check to make sure the level is not in the list.
            return is_whitelist ? levels.include?(level) : levels.exclude?(level)
        end

        true
    end

    # If #show_action? returns false, then the button is shown disabled
    def show_action?
        begin
            Rails.logger.debug("Aeon Fulfillment Plugin") { "Checking for plugin settings for the repository" } if AeonRecordMapper.debug_mode?

            if !self.repo_settings
                Rails.logger.info("Aeon Fulfillment Plugin") { "Could not find plugin settings for the repository: \"#{self.repo_code}\"." } if AeonRecordMapper.debug_mode?
            else
                Rails.logger.debug("Aeon Fulfillment Plugin") { "Checking for top containers" } if AeonRecordMapper.debug_mode?

                has_top_container = record.is_a?(Container) || self.container_instances.any?

                only_top_containers = self.repo_settings[:requests_permitted_for_containers_only] || false

                # if we're showing the button for accessions, and this is an accession,
                # then don't require containers
                only_top_containers = self.repo_settings.fetch(:hide_button_for_accessions, false) if record.is_a?(Accession)

                Rails.logger.debug("Aeon Fulfillment Plugin") { "Containers found?    #{has_top_container}" } if AeonRecordMapper.debug_mode?
                Rails.logger.debug("Aeon Fulfillment Plugin") { "only_top_containers? #{only_top_containers}" } if AeonRecordMapper.debug_mode?

                return (has_top_container || !only_top_containers) || born_digital?
            end

        rescue Exception => e
            Rails.logger.error("Aeon Fulfillment Plugin") { "Failed to create Aeon Request action." }
            Rails.logger.error(e.message)
            Rails.logger.error(e.backtrace.inspect)

        end

        false
    end


    # Pulls data from the contained record
    def map
        mappings = {}

        mappings = mappings
            .merge(self.system_information)
            .merge(self.json_fields)
            .merge(self.record_fields)
            .merge(self.user_defined_fields)

        mappings
    end


    # Pulls data from AppConfig and ASpace System
    def system_information
        mappings = {}

        mappings['SystemID'] =
            if (!self.repo_settings[:aeon_external_system_id].blank?)
                self.repo_settings[:aeon_external_system_id]
            else
                "ArchivesSpace"
            end

        return_url =
            if (!AppConfig[:public_proxy_url].blank?)
                AppConfig[:public_proxy_url]
            elsif (!AppConfig[:public_url].blank?)
                AppConfig[:public_url]
            else
                ""
            end

        mappings['ReturnLinkURL'] = "#{return_url}#{self.record['uri']}"

        mappings['ReturnLinkSystemName'] =
            if (!self.repo_settings[:aeon_return_link_label].blank?)
                self.repo_settings[:aeon_return_link_label]
            else
                "ArchivesSpace"
            end

        mappings['Site'] = self.repo_settings[:aeon_site_code] if self.repo_settings.has_key?(:aeon_site_code)

        mappings
    end


    # Pulls data from self.record
    def record_fields
        mappings = {}

        Rails.logger.debug("Aeon Fulfillment Plugin") { "Mapping Record: #{self.record}" } if AeonRecordMapper.debug_mode?

        mappings['identifier'] = self.record.identifier || self.record['identifier']
        mappings['publish'] = self.record['publish']
        mappings['level'] = self.record.level || self.record['level']
        mappings['title'] = strip_mixed_content(self.record['title'])
        mappings['uri'] = self.record.uri || self.record['uri']

        resolved_resource = self.record['_resolved_resource'] || self.record.resolved_resource
        if resolved_resource
            resource_obj = resolved_resource[self.record['resource']]
            if resource_obj
                collection_id_components = [
                    resource_obj[0]['id_0'],
                    resource_obj[0]['id_1'],
                    resource_obj[0]['id_2'],
                    resource_obj[0]['id_3']
                ]

                mappings['collection_id'] = collection_id_components
                    .reject {|id_comp| id_comp.blank?}
                    .join('-')

                mappings['collection_title'] = resource_obj[0]['title']
            end
        end

        resolved_repository = self.record.resolved_repository
        if resolved_repository
            mappings['repo_code'] = resolved_repository['repo_code']
            mappings['repo_name'] = resolved_repository['name']
        end

        if record['creators']
            mappings['creators'] = self.record['creators']
                .select { |cr| cr.present? }
                .map { |cr| cr.strip }
                .join("; ")
        end

        mappings
    end


    # Pulls relevant data from the record's JSON property
    def json_fields

        mappings = {}

        json = self.record.json
        return mappings unless json

        Rails.logger.debug("Aeon Fulfillment Plugin") { "Mapping Record JSON: #{json}" } if AeonRecordMapper.debug_mode?

        mappings['language'] = json['language']

        notes = json['notes']
        if notes
            mappings['physical_location_note'] = notes
                .select { |note| note['type'] == 'physloc' and note['content'].present? }
                .map { |note| note['content'] }
                .flatten
                .join("; ")

            mappings['accessrestrict'] = notes
                .select { |note| note['type'] == 'accessrestrict' and note['subnotes'] }
                .map { |note| note['subnotes'] }
                .flatten
                .select { |subnote| subnote['content'].present? }
                .map { |subnote| subnote['content'] }
                .flatten
                .join("; ")
        end

        if json['dates']
            json['dates']
                .select { |date| date['expression'].present? }
                .group_by { |date| date['label'] }
                .each { |label, dates|
                    mappings["#{label}_date"] = dates
                        .map { |date| date['expression'] }
                        .join("; ")
                }
        end

        mappings['restrictions_apply'] = json['restrictions_apply']
        mappings['display_string'] = json['display_string']

        mappings['requests'] = []
        request_count = 0

        if born_digital?
            request_count = request_count + 1

            mappings['requests'] << map_born_digital_to_reading_room_request(request_count)

            return mappings
        end

        instances = self.container_instances

        return mappings if instances.empty?

        instances.each do |instance|
            next if @requested_instance_indexes.nil? || !@requested_instance_indexes.include?(instance.fetch('_index'))

            request_count = request_count + 1

            mappings['requests'] << map_container_to_reading_room_request(instance, request_count)
        end

        mappings
    end

    def map_born_digital_to_reading_room_request(request_number)
        request = {}
        request['Request'] = "#{request_number}"
        request
    end

    def map_container_to_reading_room_request(instance, request_number)
        request = {}

        request['Request'] = "#{request_number}"

        request["instance_is_representative_#{request_number}"] = instance['is_representative']
        request["instance_last_modified_by_#{request_number}"] = instance['last_modified_by']
        request["instance_instance_type_#{request_number}"] = instance['instance_type']
        request["instance_created_by_#{request_number}"] = instance['created_by']

        container = instance['sub_container']
        return request unless container

        request["instance_container_grandchild_indicator_#{request_number}"] = container['indicator_3']
        request["instance_container_child_indicator_#{request_number}"] = container['indicator_2']
        request["instance_container_grandchild_type_#{request_number}"] = container['type_3']
        request["instance_container_child_type_#{request_number}"] = container['type_2']
        request["instance_container_last_modified_by_#{request_number}"] = container['last_modified_by']
        request["instance_container_created_by_#{request_number}"] = container['created_by']

        top_container = container['top_container']
        return request unless top_container

        request["instance_top_container_ref_#{request_number}"] = top_container['ref']

        top_container_resolved = resolved_top_container_for_uri(top_container['ref'])

        request["instance_top_container_long_display_string_#{request_number}"] = top_container_resolved['long_display_string']
        request["instance_top_container_last_modified_by_#{request_number}"] = top_container_resolved['last_modified_by']
        request["instance_top_container_display_string_#{request_number}"] = top_container_resolved['display_string']
        request["instance_top_container_restricted_#{request_number}"] = top_container_resolved['restricted']
        request["instance_top_container_created_by_#{request_number}"] = top_container_resolved['created_by']
        request["instance_top_container_indicator_#{request_number}"] = top_container_resolved['indicator']
        request["instance_top_container_barcode_#{request_number}"] = top_container_resolved['barcode']
        request["instance_top_container_type_#{request_number}"] = top_container_resolved['type']
        request["instance_top_container_uri_#{request_number}"] = top_container_resolved['uri']


        collection = top_container_resolved['collection']
        if collection
            request["instance_top_container_collection_identifier_#{request_number}"] = collection
                                                                                          .select { |c| c['identifier'].present? }
                                                                                          .map { |c| c['identifier'] }
                                                                                          .join("; ")

            request["instance_top_container_collection_display_string_#{request_number}"] = collection
                                                                                              .select { |c| c['display_string'].present? }
                                                                                              .map { |c| c['display_string'] }
                                                                                              .join("; ")
        end

        series = top_container_resolved['series']
        if series
            request["instance_top_container_series_identifier_#{request_number}"] = series
                                                                                      .select { |s| s['identifier'].present? }
                                                                                      .map { |s| s['identifier'] }
                                                                                      .join("; ")

            request["instance_top_container_series_display_string_#{request_number}"] = series
                                                                                          .select { |s| s['display_string'].present? }
                                                                                          .map { |s| s['display_string'] }
                                                                                          .join("; ")

        end

        request
    end

    # Grabs a list of instances from the given jsonmodel, ignoring any digital object
    # instances. If the current jsonmodel does not have any top container instances, the
    # method will recurse up the record's resource tree, until it finds a record that does
    # have top container instances, and will pull the list of instances from there.
    def find_container_instances (record_json)

        current_uri = record_json['uri']

        Rails.logger.info("Aeon Fulfillment Plugin") { "Checking \"#{current_uri}\" for Top Container instances..." } if AeonRecordMapper.debug_mode?
        Rails.logger.debug("Aeon Fulfillment Plugin") { "#{record_json.to_json}" } if AeonRecordMapper.debug_mode?

        # Inheriting containers doesn't work with our other plugin (it gets passed an
        # empty array that will cause an error later), so just skipping those for now.
        # TODO: Figure out why the other plugin does not work with this new feature
        
        # The container pages will still get a few checks below, but those will always
        # evaluate to false.
        unless record.is_a?(Container)
          instances = record_json['instances']
            .each_with_index
            .map { |instance, idx|
                next if instance['digital_object']
                instance['_index'] = idx
                instance
            }.compact

          Rails.logger.info("Aeon Fulfillment Plugin") { "Top Container instances found" } if AeonRecordMapper.debug_mode?
          return instances
        end

        if record.is_a?(Container)
            return [record_json]
        end

        # DISABLE INHERITANCE MAGIC AS YALE DOESN'T USE IT
        #
        # parent_uri = ''
        #
        # if record_json['parent'].present?
        #     parent_uri = record_json['parent']['ref']
        #     parent_uri = record_json['parent'] unless parent_uri.present?
        # elsif record_json['resource'].present?
        #     parent_uri = record_json['resource']['ref']
        #     parent_uri = record_json['resource'] unless parent_uri.present?
        # end
        #
        # if parent_uri.present?
        #     Rails.logger.debug("Aeon Fulfillment Plugin") { "No Top Container instances found. Checking parent. (#{parent_uri})" }
        #     parent = archivesspace.get_record(parent_uri)
        #     parent_json = parent['json']
        #     return find_container_instances(parent_json)
        # end

        Rails.logger.debug("Aeon Fulfillment Plugin") { "No Top Container instances found." } if AeonRecordMapper.debug_mode?

        []
    end

    def born_digital?
        !!self.repo_settings[:requests_permitted_for_born_digital] && record.is_a?(ArchivalObject) && local_access_restriction_types.include?(RESTRICTION_TYPE_BORN_DIGITAL)
    end

    def self.debug_mode?
        AppConfig.has_key?(:aeon_fulfillment_debug) && AppConfig[:aeon_fulfillment_debug]
    end

    def resolved_top_container_for_uri(top_container_uri)
        ASUtils.json_parse(@record.raw.fetch('_resolved_top_container_uri_u_sstr').fetch(top_container_uri).fetch(0).fetch('json'))
    end

    protected :json_fields, :record_fields, :system_information,
              :requestable_based_on_archival_record_level?,
              :find_container_instances, :user_defined_fields
end
