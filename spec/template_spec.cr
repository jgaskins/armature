require "./spec_helper"
require "xml"

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

    it "handles nested interpolation with blocks" do
      rendered = Template.render "spec/support/interpolate_nested_block.ecr"

      normalize(rendered).should eq <<-EOF
        <div>
          outer
          outer header
          <div>
          inner
            inner stuff
          
        </div>

          outer footer

        </div>
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

  private class NestedExample
    @value : String

    def initialize(@value, &@block)
    end

    def to_s(io)
      Armature::Template.embed "spec/support/nested_example.ecr", io
    end
  end
end

private def normalize(rendered)
  XML
    .parse_html(rendered)
    .to_xml(options: XML::SaveOptions[
      :format,
      :as_html,
    ])
    .lines[2..-2]
    .join('\n')
    .strip
end
