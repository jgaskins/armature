require "redis"
require "uuid"
require "json"
require "http/cookie"
require "http/server/context"

require "./session"

module Armature
  class Session
    class RedisStore < Store
      getter key

      @expiration : Time::Span?

      def initialize(
        key : String,
        @redis = Redis::Client.new,
        @expiration = 2.weeks,
        @http_only : Bool = true,
        @path : String? = "/",
        @log = Log.for("armature.session")
      )
        super key
      end

      def call(context : HTTP::Server::Context)
        session = Session.new(self, context.request.cookies)
        context.session = session

        unless session_id = context.request.cookies[@key]?.try(&.value)
          session_id = UUID.random.to_s
        end

        call_next context

        if session.modified? || !session.new?
          context.response.cookies << HTTP::Cookie.new @key, session_id,
            path: @path,
            expires: @expiration.try(&.from_now),
            http_only: @http_only

          save "#{@key}-#{session_id}", session.as(Session)
        end
      end

      def load(key : String) : Hash(String, JSON::Any)
        value = @redis.get(key)
        @log.debug &.emit "GET #{key}", value: value
        value = JSON.parse(value || "{}")
        if value.raw.nil?
          value = JSON::Any.new({} of String => JSON::Any)
        end

        value.as_h
      end

      def save(key : String, session : Session)
        @redis.set key, session.json, ex: @expiration
      end

      class Session < ::Armature::Session
        getter? modified : Bool = false
        alias Data = Hash(String, JSON::Any)
        private getter data : Data do
          if cookie = self.cookie
            redis_key = "#{@store.key}-#{cookie.value}"
            @store.as(RedisStore).load(redis_key)
          else
            Data.new
          end
        end

        def [](key : String)
          data[key]
        end

        def []?(key : String)
          data[key]?
        end

        def []=(key : String, value : Hash)
          self[key] = value.transform_values { |value| JSON::Any.new(value) }
        end

        def []=(key : String, value : Hash(String, JSON::Any))
          self[key] = JSON::Any.new(value)
        end

        def []=(key : String, value : JSON::Any::Type)
          self[key] = JSON::Any.new(value)
        end

        def []=(key : String, value : Int)
          self[key] = JSON::Any.new(value.to_i64)
        end

        def []=(key : String, value : JSON::Any)
          data[key] = value
          @modified = true
        end

        def delete(key : String)
          if data.has_key? key
            data.delete key
            @modified = true
          end
        end

        def json
          @data.to_json
        end

        def new?
          cookie.nil? || data.empty?
        end

        private getter cookie : HTTP::Cookie? do
          @cookies[@store.key]?
        end
      end
    end
  end
end
