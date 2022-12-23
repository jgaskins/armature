require "http"
require "json"

require "./template"
require "./session"

module Armature
  module Route
    def route(context, &block : Request, Response, Armature::Session ->)
      response = Response.new(context.response)
      request = Request.new(context.request, response: response, session: context.session)

      yield request, response, context.session
    end

    macro render(template, to io = response)
      ::Armature::Template.embed "views/{{template.id}}.ecr", {{io}}
    end

    def safe(value)
      ::Armature::Template::HTML::SafeValue.new(value)
    end

    class Request
      delegate headers, path, :headers=, cookies, body, method, original_path, to: @request

      getter response : Response
      getter session : Session
      @handled = false

      def initialize(@request : HTTP::Request, @response, @session)
        @request.original_path = @request.@original_path || @request.path
      end

      def params
        @request.query_params
      end

      def form_params
        @form_params ||= begin
          if body = @request.body
            case headers["Content-Type"]?
            when /multipart/
              params = URI::Params.new
              HTTP::FormData.parse @request do |part|
                params[part.name] = part.body.gets_to_end
              end
              params
            when /url/
              URI::Params.parse body.gets_to_end
            else
              URI::Params.new
            end
          else
            URI::Params.new
          end
        end
      end

      def root
        return if handled?

        is("/") { yield }
        is("") { yield }
      end

      macro handle_method(*methods)
        {% for method in methods %}
          def {{method.id.downcase}}
            return if handled?

            if @request.method == {{method.stringify.upcase}}
              begin
                yield
              ensure
                handled!
              end
            end
          end

          def {{method.id.downcase}}(capture : Symbol)
            is(capture) { |capture| {{method.id.downcase}} { yield capture } }
          end

          def {{method.id.downcase}}(path : String)
            is(path) { {{method.id.downcase}} { yield } }
          end
        {% end %}
      end

      handle_method get, post, put, patch, delete

      def is(path : String = "")
        return if handled?

        check_path = path.sub(%r(\A/), "")
        actual = @request.path.sub(%r(\A/), "")

        old_path = @request.path
        if check_path == actual
          @request.path = ""
          begin
            yield
          ensure
            handled!
          end
        end
      ensure
        @request.path = old_path if old_path
      end

      def is(path : Symbol)
        return if handled?

        old_path = @request.path
        match = %r(\A/?[^/]+\z).match @request.path.sub(%r(\A/), "")
        if match
          @request.path = @request.path.sub(%r(\A/#{match[0]}), "")

          begin
            yield match[0]
          ensure
            handled!
          end
        end
      ensure
        if old_path
          @request.path = old_path
        end
      end

      def on(*paths : String)
        paths.each do |path|
          on(path) { yield }
        end
      end

      def on(path : String)
        return if handled?

        if match?(path)
          begin
            old_path = @request.path
            @request.path = @request.path.sub(/\A\/?#{path}/, "")
            yield
          ensure
            @request.path = old_path.not_nil!
          end
        end
      end

      def on(capture : Symbol)
        return if handled?

        old_path = @request.path
        match = %r(\A/?[^/]+).match @request.path.sub(%r(\A/), "")
        if match
          @request.path = @request.path.sub(%r(\A/#{match[0]}), "")

          yield match[0]
        end
      ensure
        if old_path
          @request.path = old_path
        end
      end


      def on(**capture)
        return if handled?

        old_path = @request.path
        capture.each do |key, value|
          if (match = %r(\A/?[^/]+).match @request.path.sub(%r(\A/), "")) && (result = match?(match[0], value))
            @request.path = @request.path.sub(%r(\A/#{match[0]}), "")
            yield result
          end
        end
      ensure
        if old_path
          @request.path = old_path
        end
      end

      def match?(segment : String, matcher)
        matcher === segment
      end

      {% for type in %w[Int UInt] %}
        {% for size in %w[8 16 32 64 128] %}
          def match?(segment : String, matcher : {{type.id}}{{size.id}}.class)
            segment.to_{{type[0..0].downcase.id}}{{size.id}}?
          end
        {% end %}
      {% end %}

      def match?(segment : String, matcher : UUID.class)
        UUID.parse? segment
      end

      def match?(segment : String, matcher : Regex)
        matcher.match segment
      end

      def params(*params)
        return if handled?
        return if !params.all? { |param| @request.query_params.has_key? param }

        begin
          yield params.map { |key| @request.query_params[key] }
        ensure
          handled!
        end
      end

      def miss
        return if handled?

        begin
          yield
        ensure
          handled!
        end
      end

      def json?
        path.ends_with?("json") || headers["Content-Type"]? =~ /json/ || headers["Accept"]? =~ /json/
      end

      def url : URI
        @uri ||= URI.parse("https://#{@request.host_with_port}/#{@request.path}")
      end

      private def match?(path : String)
        @request.path.starts_with?(path) || @request.path.starts_with?("/#{path}")
      end

      def handled?
        @request.handled?
      end

      def handled!
        @request.handled!
      end
    end

    class Response < IO
      @response : HTTP::Server::Response

      delegate headers, read, status, to: @response

      def initialize(@response)
      end

      def redirect(path, status : HTTP::Status = :see_other)
        self.status = status
        @response.headers["Location"] = path
      end

      def json(serializer)
        @response.headers["Content-Type"] = "application/json"
        serializer.to_json @response
      end

      def json(**stuff)
        @response.headers["Content-Type"] = "application/json"
        stuff.to_json @response
      end

      def status=(status : HTTP::Status)
        @response.status = status
      end

      def write(bytes : Bytes) : Nil
        @response.write bytes
      end

      def output
        @response.output.as(IO::Buffered)
      end
    end

    class UnauthenticatedException < Exception
    end

    class RequestHandled < Exception
    end
  end
end

module HTTP
  class Request
    # We mutate the request path as we traverse the routing tree so we need to
    # be able to know the original path.
    property! original_path : String
    getter? handled = false

    def handled!
      @handled = true
    end
  end
end
