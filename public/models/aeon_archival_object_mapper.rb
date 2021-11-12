require_relative '../../common/aeon_archival_object_request'

class AeonArchivalObjectMapper < AeonRecordMapper

    register_for_record_type(ArchivalObject)

    def map
        AeonArchivalObjectRequest.build(self.record.json, super, :resource => self.record.resolved_resource)
    end

    # Override of #show_action? from AeonRecordMapper
    def show_action?
        return false if !super
        self.requestable_based_on_archival_record_level?
    end

end
