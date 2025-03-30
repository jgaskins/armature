require "html"

module Armature::Template
  extend self

  DefaultBufferName = "__str__"

  # Defines a `to_s(io)` method whose body is the ECR contained
  # in *filename*, translated to Crystal code.
  #
  # ```text
  # # greeting.ecr
  # Hello <%= @name %>!
  # ```
  #
  # ```
  # require "ecr/macros"
  #
  # class Greeting
  #   def initialize(@name : String)
  #   end
  #
  #   ECR.def_to_s "greeting.ecr"
  # end
  #
  # Greeting.new("World").to_s # => "Hello World!"
  # ```
  #
  # The macro basically translates the text inside the given file
  # to Crystal code that appends to the IO:
  #
  # ```
  # class Greeting
  #   def to_s(io)
  #     io << "Hello "
  #     io << @name
  #     io << '!'
  #   end
  # end
  # ```
  macro def_to_s(filename)
    def to_s(__io__ : IO) : Nil
      ::Armature::Template.embed {{filename}}, "__io__"
    end
  end

  # Embeds an ECR file *filename* into the program and appends the content to
  # an IO in the variable *io_name*.
  #
  # The generated code is the result of translating the contents of
  # the ECR file to Crystal, a program that appends to an IO.
  #
  # ```text
  # # greeting.ecr
  # Hello <%= name %>!
  # ```
  #
  # ```
  # require "ecr/macros"
  #
  # name = "World"
  #
  # io = IO::Memory.new
  # ECR.embed "greeting.ecr", io
  # io.to_s # => "Hello World!"
  # ```
  #
  # The `ECR.embed` line basically generates this Crystal code:
  #
  # ```
  # io << "Hello "
  # io << name
  # io << '!'
  # ```
  macro embed(filename, io_name)
    \{{ run("armature/template/compile", {{filename}}, {{io_name.id.stringify}}) }}
  end

  # Embeds an ECR file *filename* into the program and renders it to a string.
  #
  # The generated code is the result of translating the contents of
  # the ECR file to Crystal, a program that appends to an IO and returns a string.
  #
  # ```text
  # # greeting.ecr
  # Hello <%= name %>!
  # ```
  #
  # ```
  # require "ecr/macros"
  #
  # name = "World"
  #
  # rendered = ECR.render "greeting.ecr"
  # rendered # => "Hello World!"
  # ```
  #
  # The `ECR.render` basically generates this Crystal code:
  #
  # ```
  # String.build do |io|
  #   io << "Hello "
  #   io << name
  #   io << '!'
  # end
  # ```
  macro render(filename)
    ::String.build do |%io|
      ::Armature::Template.embed({{filename}}, %io)
    end
  end

  module HTML
    struct SanitizableValue(T)
      def initialize(@value : T)
      end

      def to_s(io)
        {% if T < ::Armature::Template::HTML::SafeValue %}
          @value.to_s io
        {% else %}
          ::HTML.escape @value.to_s, io
        {% end %}
      end
    end

    struct SafeValue(T)
      def initialize(@value : T)
      end

      def to_s(io)
        @value.to_s io
      end
    end
  end

  # :nodoc:
  def process_file(filename, buffer_name = DefaultBufferName) : String
    process_string File.read(filename), filename, buffer_name
  end

  # :nodoc:
  def process_string(string, filename, buffer_name = DefaultBufferName) : String
    lexer = Lexer.new string
    token = lexer.next_token

    String.build do |str|
      while true
        case token.type
        in .string?
          string = token.value
          token = lexer.next_token

          string = suppress_leading_indentation(token, string)

          str << buffer_name
          str << " << "
          string.inspect str
          str << '\n'
        in .output?
          string = token.value
          line_number = token.line_number
          column_number = token.column_number
          suppress_trailing = token.suppress_trailing?
          token = lexer.next_token

          suppress_trailing_whitespace(token, suppress_trailing)

          str << "#<loc:push>("
          append_loc(str, filename, line_number, column_number)
          # If they used <%== safe_content %>, we can just use that
          if string.starts_with? '='
            # Write all but the first byte to the buffer, but without allocating
            # another string to do it.
            str.write string.to_slice + 1
          else
            str << "::Armature::Template::HTML::SanitizableValue.new((" << string << "))"
          end
          str << ")#<loc:pop>.to_s "
          str << buffer_name
          str << '\n'
        in .begin_output_block?
          string = token.value
          line_number = token.line_number
          column_number = token.column_number
          suppress_trailing = token.suppress_trailing?
          token = lexer.next_token

          suppress_trailing_whitespace(token, suppress_trailing)
          str << "#<loc:push>"
          append_loc(str, filename, line_number, column_number)
          # If they used <%|== safe_content do %>, we can just use that
          if string.starts_with? '='
            # Write all but the first byte to the buffer, but without allocating
            # another string to do it.
            str.write string.to_slice + 1
          else
            raise "HTML sanitization for block capture is not yet supported."
            str << string
          end
        in .end_output_block?
          string = token.value
          token = lexer.next_token
          str.puts "#<loc:pop>"
          str.puts string
          str << ".to_s " << buffer_name << '\n'
        in .control?
          string = token.value
          line_number = token.line_number
          column_number = token.column_number
          suppress_trailing = token.suppress_trailing?
          token = lexer.next_token

          suppress_trailing_whitespace(token, suppress_trailing)

          str << "#<loc:push>"
          append_loc(str, filename, line_number, column_number)
          str << ' ' unless string.starts_with?(' ')
          str << string
          str << "#<loc:pop>"
          str << '\n'
        in .eof?
          break
        end
      end
    end
  end

  private def suppress_leading_indentation(token, string)
    # To suppress leading indentation we find the last index of a newline and
    # then check if all chars after that are whitespace.
    # We use a Char::Reader for this for maximum efficiency.
    if (token.type.output? || token.type.control?) && token.suppress_leading?
      char_index = string.rindex('\n')
      char_index = char_index ? char_index + 1 : 0
      byte_index = string.char_index_to_byte_index(char_index).not_nil!
      reader = Char::Reader.new(string)
      reader.pos = byte_index
      while reader.current_char.ascii_whitespace? && reader.has_next?
        reader.next_char
      end
      if reader.pos == string.bytesize
        string = string.byte_slice(0, byte_index)
      end
    end
    string
  end

  private def suppress_trailing_whitespace(token, suppress_trailing)
    if suppress_trailing && token.type.string?
      newline_index = token.value.index('\n')
      token.value = token.value[newline_index + 1..-1] if newline_index
    end
  end

  private def append_loc(str, filename, line_number, column_number)
    str << %(#<loc:")
    str << filename
    str << %(",)
    str << line_number
    str << ','
    str << column_number
    str << '>'
  end

  class Lexer
    class Token
      enum Type
        String
        Output
        BeginOutputBlock
        EndOutputBlock
        Control
        EOF
      end

      property type : Type
      property value : String
      property line_number : Int32
      property column_number : Int32
      property? suppress_leading : Bool
      property? suppress_trailing : Bool

      def initialize
        @type = :EOF
        @value = ""
        @line_number = 0
        @column_number = 0
        @suppress_leading = false
        @suppress_trailing = false
      end
    end

    def initialize(string)
      @reader = Char::Reader.new(string)
      @token = Token.new
      @line_number = 1
      @column_number = 1
    end

    def next_token : Token
      copy_location_info_to_token

      case current_char
      when '\0'
        @token.type = :EOF
        return @token
      when '<'
        if peek_next_char == '%'
          next_char
          next_char

          if current_char == '-'
            @token.suppress_leading = true
            next_char
          elsif current_char == '|'
            is_output_block = true
            next_char
          else
            @token.suppress_leading = false
          end

          case current_char
          when '='
            next_char
            copy_location_info_to_token
            is_output = true
          when '%'
            next_char
            copy_location_info_to_token
            is_escape = true
          else
            copy_location_info_to_token
          end

          return consume_control(is_output, is_output_block, is_escape)
        end
      else
        # consume string
      end

      consume_string
    end

    private def consume_string
      start_pos = current_pos
      while true
        case current_char
        when '\0'
          break
        when '\n'
          @line_number += 1
          @column_number = 0
        when '<'
          if peek_next_char == '%'
            break
          end
        else
          # keep going
        end
        next_char
      end

      @token.type = :string
      @token.value = string_range(start_pos)
      @token
    end

    private def consume_control(is_output, is_output_block, is_escape)
      start_pos = current_pos
      while true
        case current_char
        when '\0'
          if is_output
            raise "Unexpected end of file inside <%= ..."
          elsif is_escape
            raise "Unexpected end of file inside <%% ..."
          else
            raise "Unexpected end of file inside <% ..."
          end
        when '\n'
          @line_number += 1
          @column_number = 0
        when '-'
          if peek_next_char == '%'
            # We need to peek another char, so we remember
            # where we are, check that, and then go back
            pos = @reader.pos
            column_number = @column_number

            next_char

            is_end = peek_next_char == '>'
            @reader.pos = pos
            @column_number = column_number

            if is_end
              @token.suppress_trailing = true
              setup_control_token(start_pos, is_escape)
              raise "Expecting '>' after '-%'" if current_char != '>'
              next_char
              break
            end
          end
        when '%'
          if peek_next_char == '>'
            @token.suppress_trailing = false
            setup_control_token(start_pos, is_escape)
            break
          end
        else
          # keep going
        end
        next_char
      end

      if is_escape
        @token.type = :string
      elsif is_output_block
        if is_output
          @token.type = :begin_output_block
        else
          @token.type = :end_output_block
        end
      elsif is_output
        @token.type = :output
      else
        @token.type = :control
      end
      @token
    end

    private def setup_control_token(start_pos, is_escape)
      @token.value = if is_escape
                       "<%#{string_range(start_pos, current_pos + 2)}"
                     else
                       string_range(start_pos)
                     end
      next_char
      next_char
    end

    private def copy_location_info_to_token
      @token.line_number = @line_number
      @token.column_number = @column_number
    end

    private def current_char
      @reader.current_char
    end

    private def next_char
      @column_number += 1
      next_char_no_column_increment
    end

    private def next_char_no_column_increment
      @reader.next_char
    end

    private def peek_next_char
      @reader.peek_next_char
    end

    private def current_pos
      @reader.pos
    end

    private def string_range(start_pos)
      string_range(start_pos, current_pos)
    end

    private def string_range(start_pos, end_pos)
      @reader.string.byte_slice(start_pos, end_pos - start_pos)
    end
  end
end
