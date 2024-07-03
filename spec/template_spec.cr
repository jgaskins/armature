require "./spec_helper"

require "../src/template"

module Armature
  describe Template do
    it "renders a template" do
      rendered = Template.render "spec/support/hello_world.ecr"

      rendered.strip.should eq "Hello world!"
    end

    it "interpolates data with <%= ... %>" do
      user_supplied_input = "<script>console.log('pwned')</script>"

      rendered = Template.render "spec/support/interpolate_safe.ecr"

      rendered.strip.should eq "&lt;script&gt;console.log(&#39;pwned&#39;)&lt;/script&gt;"
    end

    it "interpolates data with <%== ... %>" do
      values = %w[foo bar baz]

      rendered = Template.render "spec/support/interpolate_raw.ecr"

      rendered.strip.should eq <<-EOF
        foo
        bar
        baz
        EOF
    end

    it "interpolates a method that takes a block" do
      items = [1, 2]
      rendered = Template.render "spec/support/interpolate_block.ecr"

      # Formatting is a little wonky, but it's fine
      rendered.strip.should eq <<-EOF
        <ul>
          <li>  item 1</li>
          <li>  item 2</li>
        </ul>
        EOF
    end
  end

  private struct ListExample(T)
    @collection : Enumerable(T)
    @block : T ->

    def initialize(@collection, &@block : T ->)
    end

    def to_s(io)
      Armature::Template.embed "spec/support/list_example.ecr", io
    end
  end
end
