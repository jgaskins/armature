require "ecr"

module Armature
  abstract struct Component
    macro def_to_s(template)
      ECR.def_to_s "views/{{template.id}}.ecr"
    end
  end
end
