require "http/server/context"
require "http/server/response"
require "http/request"
require "http/status"
require "json"
require "uri"
require "uuid"

require "./template"
require "./session"

module Armature
  module Route
    def route(context, &block : Request, Response, Armature::Session ->)
      response = context.armature_response
      request = context.armature_request

      yield request, response, context.session
    end

    # Scaffold a full set of REST-style handlers that map to route methods. The mapping is:
    #
    # - `GET /` -> `index`
    # - `GET /new` -> `new`
    # - `POST /` -> `create`
    # - `GET /:id` -> `show(resource)`
    # - `GET /:id/edit` -> `edit(resource)`
    # - `PUT /:id` -> `update(resource)`
    # - `DELETE /:id` -> `destroy(resource)`
    #
    # ```
    # struct Posts
    #   include Armature::Route
    #
    #   scaffold id: UUID do |id|
    #     PostQuery.new.find(id)
    #   end
    #
    #   def new
    #     render "posts/new"
    #   end
    #
    #   def create
    #     title = r.form_params["title"]?
    #     body = r.form_params["body"]?
    #     if title && body
    #       case post = PostQuery.new.create(title: title, body: body)
    #       in Post
    #         response.redirect "/posts/#{post.id}"
    #       in Failure
    #         response.status = :unprocessable_entity
    #         error = post.errors
    #         render "posts/errors"
    #         render "posts/new"
    #       end
    #     else
    #       response.status = :bad_request
    #     end
    #   end
    #
    #   def show(post : Post)
    #     render "posts/show"
    #   end
    # end
    # ```
    @[Experimental("Route scaffolding is not yet stabilized")]
    macro scaffold(*, id id_type = String)
      include Armature::Form::Helper

      getter! context : HTTP::Server::Context
      getter request : Armature::Route::Request do
        Request.new context
      end
      getter response : Armature::Route::Response do
        Response.new context
      end
      getter session : Armature::Session do
        context.session
      end
      getter! id : {{id_type}}

      def call(context)
        route context do |r, response, session|
          @context = context

          r.root do
            r.get do
              index
            end

            r.post do
              check_csrf_token { create }
            end
          end

          r.get "new" { new }

          r.on id: {{id_type}} do |id|
            if resource = {{yield}}
              r.root do
                r.get { show resource }
                r.put { check_csrf_token { update resource } }
                r.delete { check_csrf_token { destroy resource } }
              end

              r.get "edit" { edit resource }
            end
          end
        end
      end

      def check_csrf_token(params_type : ParamType = default_params_type)
        params = case params_type
                 in .query?
                   r.params
                 in .form?
                   r.form_params
                 in .multipart_form_data?
                   response.status = :unprocessable_entity
                   response << "This endpoint doesn't support multipart data"
                   return
                 end

        if valid_authenticity_token?(params, session)
          yield
        else
          response.status = :bad_request
        end
      end

      def default_params_type : ParamType
        case r.headers["content-type"]?
        when nil
          ParamType::Query
        when .includes? "form"
          ParamType::Form
        when .includes? "multipart/form-data"
          ParamType::MultipartFormData
        else
          ParamType::Query
        end
      end

      enum ParamType
        Query
        Form
        MultipartFormData
      end

      def r
        request
      end

      def index
        not_found!
      end

      def show(resource)
        not_found!
      end

      def new
        not_found!
      end

      def create
        not_found!
      end

      def edit(resource)
        not_found!
      end

      def update(resource)
        not_found!
      end

      def destroy(resource)
        not_found!
      end

      def not_found!
        response.status = :not_found
      end
    end

    macro render(template, to io = response)
      ::Armature::Template.embed "views/{{template.id}}.ecr", {{io}}
    end

    def safe(value)
      ::Armature::Template::HTML::SafeValue.new(value)
    end

    class Request
      delegate headers, path, :headers=, cookies, body, method, resource, to: original_request

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

      def root(&)
        return if handled?

        is { yield }
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

      def is(&)
        return if handled?

        if path == "" || path == "/"
          old_path = original_request.path
          begin
            yield
          ensure
            handled!
          end
        end
      ensure
        if old_path
          original_request.path = old_path
        end
      end

      def is(*segments, &)
        return if handled?

        on(*segments) do |*captures|
          if path == "" || path == "/"
            yield(*captures)
            handled!
          end
        end
      end

      def on(*segments, &)
        return if handled?

        on segments do |captures|
          yield *captures
        end
      end

      private def on(segments : Tuple(*T), &) forall T
        {% begin %}
          path = original_request.path
          original_path = path

          begin
            captures = {
              {% for i in 0...T.size %}
                begin
                  %matcher{i} = segments[{{i}}]
                  path = path.lchop('/')
                  if %matcher{i}.is_a?(String)
                    %matcher{i} = %matcher{i}.lchop('/')
                    if path.starts_with?(%matcher{i})
                      segment = %matcher{i}
                      path = path.lchop(segment)
                    end
                    segment
                  else
                    if %matcher{i}.responds_to? :matches_request?
                      if %result{i} = %matcher{i}.matches_request? self
                        %result{i}
                      end
                    else
                      if slash_index = path.index('/')
                        segment = path[0...slash_index]
                      else
                        segment = path
                      end
                      if (%match{i} = segment.presence) && (%result{i} = match?(%match{i}, %matcher{i}))
                        if segment == path
                          path = ""
                        else
                          path = path.lchop(segment)
                        end
                        %result{i}
                      end
                    end
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
          ensure
            original_request.path = original_path
          end
        {% end %}
      end

      def on(**segments, &)
        on *segments.values do |*args|
          yield *args
        end
      end

      def match?(segment : String, matcher)
        matcher === segment
      end

      def match?(segment : String, matcher : String)
        if matcher.starts_with? segment
          segment
        end
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

      def params(*params, &)
        return if handled?
        return if !params.all? { |param| original_request.query_params.has_key? param }

        begin
          yield params.map { |key| original_request.query_params[key] }
        ensure
          handled!
        end
      end

      def miss(&)
        return if handled?
        return unless response.status.ok?

        begin
          yield
        ensure
          handled!
        end
      end

      def html(&)
        yield if html?
      end

      def html?
        headers["Accept"]?.try &.includes? "text/html"
      end

      def json(&)
        yield if json?
      end

      def json?
        path.ends_with?("json") || headers["Content-Type"]?.try(&.includes?("json")) || headers["Accept"]?.try(&.includes?("json"))
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

      def redirect(path : String | URI, status : HTTP::Status = :see_other)
        self.status = status
        @response.headers["Location"] = path.to_s
      end

      def json(**stuff)
        json stuff
      end

      def json(serializer)
        @response.headers["Content-Type"] ||= "application/json"
        serializer.to_json @response
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

require "http/server/context"

# :nodoc:
class HTTP::Server
  # Instances of this class are passed to an `HTTP::Server` handler.
  class Context
    # We mutate the request path as we traverse the routing tree so we need to
    # be able to know the original path.
    property! original_request_path : String
    getter? handled = false
    getter armature_response : Armature::Route::Response do
      Armature::Route::Response.new(response)
    end
    getter armature_request : Armature::Route::Request do
      Armature::Route::Request.new(self)
    end

    # :nodoc:
    def initialize(@request : Request, @response : Response)
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
