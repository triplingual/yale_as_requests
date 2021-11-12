class AeonArchivalObjectMapper < AeonRecordMapper

    register_for_record_type(ArchivalObject)

    # Override of #show_action? from AeonRecordMapper
    def show_action?
        return false if !super
        self.requestable_based_on_archival_record_level?
    end

end
