require "ecr"

module Armature
  abstract struct Component
    macro def_to_s(template)
      ::Armature::Template.def_to_s "views/{{template.id}}.ecr"
    end
  end
end
