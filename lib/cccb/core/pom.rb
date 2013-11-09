module CCCB::Core::Pom
  extend Module::Requirements
  needs :bot

  def module_load
    add_request :pom, /^pom$/i do |m, s|
      %x{pom}
    end
  end
end
