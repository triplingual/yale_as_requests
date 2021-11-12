require_relative '../../common/aeon_top_container_request'

class AeonContainerMapper < AeonRecordMapper

  register_for_record_type(Container)

  def map
    AeonTopContainerRequest.build(self.record.json, super)
  end

end
