require "http"
require "json"

require "./template"
require "./session"

module Armature
  module Route
    def route(context, &block : Request, Response, Armature::Session ->)
      response = Response.new(context)
      request = Request.new(context)

      yield request, response, context.session
    end

    macro render(template, to io = response)
      ::Armature::Template.embed "views/{{template.id}}.ecr", {{io}}
    end

    def safe(value)
      ::Armature::Template::HTML::SafeValue.new(value)
    end

    class Request
      delegate headers, path, :headers=, cookies, body, method, to: original_request

      getter context : HTTP::Server::Context
      getter original_request : HTTP::Request { context.request }
      getter response : Response { context.armature_response }
      getter session : Session { context.session }

      def initialize(@context)
      end

      def params
        original_request.query_params
      end

      def form_params
        context.armature_form_params
      end

      def original_path
        context.original_request_path
      end

      def root
        return if handled?

        is("") { yield }
      end

      macro handle_method(*methods)
        {% for method in methods %}
          def {{method.id.downcase}}
            return if handled?

            if original_request.method == {{method.stringify.upcase}}
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

      def is
        return if handled?

        old_path = original_request.path
        begin
          yield
        ensure
          handled!
        end
      ensure
        if old_path
          original_request.path = old_path
        end
      end

      def is(*segments)
        return if handled?

        old_path = original_request.path
        captures = segments.map do |matcher|
          if (match = %r(\A/?[^/]*).match original_request.path.sub(%r(\A/), "")) && (result = match?(match[0], matcher))
            original_request.path = original_request.path.sub(%r(\A/?#{match[0]}), "")
            result
          else
            break nil
          end
        end

        if captures
          begin
            yield *captures
          ensure
            handled!
          end
        end
      ensure
        if old_path
          original_request.path = old_path
        end
      end

      def on(*segments)
        return if handled?

        on segments do |captures|
          yield *captures
        end
      end

      private def on(segments : Tuple(*T)) forall T
        {% begin %}
          path = original_request.path
          captures = {
            {% for i in 0...T.size %}
              begin
                %matcher{i} = segments[{{i}}]
                if (%match{i} = %r(\A/?[^/]+).match path.sub(%r(\A/), "")) && (%result{i} = match?(%match{i}[0], %matcher{i}))
                  path = path.sub(%r(\A/?#{%match{i}[0]}), "")
                  %result{i}
                end
              end,
            {% end %}
          }

          if captures.any?(&.nil?)
            return
          else
            original_request.path = path
            yield({
              {% for i in 0...T.size %}
                captures[{{i}}].not_nil!,
              {% end %}
            })
          end
        {% end %}
      end

      def on(**segments)
        on *segments.values do |*args|
          yield *args
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

      def match?(segment : String, matcher : Symbol | String.class)
        segment
      end

      def match?(segment : String, matcher : UUID.class)
        UUID.parse? segment
      end

      def match?(segment : String, matcher : Regex)
        matcher.match segment
      end

      def params(*params)
        return if handled?
        return if !params.all? { |param| original_request.query_params.has_key? param }

        begin
          yield params.map { |key| original_request.query_params[key] }
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
        @uri ||= URI.parse("https://#{original_request.host_with_port}/#{original_request.path}")
      end

      private def match?(path : String)
        original_request.path.starts_with?(path) || original_request.path.starts_with?("/#{path}")
      end

      def handled?
        context.handled?
      end

      def handled!
        context.handled!
      end
    end

    class Response < IO
      @response : HTTP::Server::Response

      delegate headers, read, status, to: @response

      def self.new(context : HTTP::Server::Context)
        new context.response
      end

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

      def write(slice : Bytes) : Nil
        @response.write slice
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
  class Server::Context
    # We mutate the request path as we traverse the routing tree so we need to
    # be able to know the original path.
    property! original_request_path : String
    getter? handled = false

    def initialize(request, response)
      previous_def
      @original_request_path = request.path
    end

    def handled!
      @handled = true
    end

    getter armature_form_params : URI::Params do
      if body = request.body
        case request.headers["Content-Type"]?
        when Nil
          URI::Params.new
        when .includes? "multipart"
          params = URI::Params.new
          HTTP::FormData.parse request do |part|
            params[part.name] = part.body.gets_to_end
          end
          params
        when .includes? "url"
          URI::Params.parse body.gets_to_end
        else
          URI::Params.new
        end
      else
        URI::Params.new
      end
    end
  end
end
