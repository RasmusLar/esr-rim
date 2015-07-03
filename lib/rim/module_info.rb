module RIM

class ModuleInfo
  # remote url (unique identifier of module)
  attr_reader :remote_url
  # locale module path
  attr_reader :local_path
  # target revision
  attr_reader :target_revision
  # ignores
  attr_reader :ignores
  
  def initialize(remote_url, local_path, target_revision, ignores = nil)
    @remote_url = remote_url
    @local_path = local_path
    @target_revision = target_revision
    if ignores.is_a?(String)
      @ignores = ignores.split(",").each do |s| 
        s.strip! 
      end 
    else
      @ignores = ignores || []
    end
  end
end

end
