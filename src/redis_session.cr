require "redis"
require "uuid"
require "json"
require "http"

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
      )
        super key
      end

      def call(context : HTTP::Server::Context)
        context.session = Session.new(self, context)

        unless session_id = context.request.cookies[@key]?.try(&.value)
          session_id = UUID.random.to_s
          context.response.cookies << HTTP::Cookie.new(@key, session_id, expires: @expiration.try(&.from_now))
        end

        call_next context

        save "#{@key}-#{session_id}", context.session.as(Session)
      end

      def load(key : String) : Hash(String, JSON::Any)
        value = JSON.parse(@redis.get(key) || "{}")
        if value.raw.nil?
          value = JSON::Any.new({} of String => JSON::Any)
        end

        value.as_h
      end

      def save(key : String, session : Session)
        return unless session.modified?

        @redis.set key, session.json, ex: 2.weeks.total_seconds.to_i
      end

      class Session < ::Armature::Session
        @data : Hash(String, JSON::Any)?
        @modified : Bool = false

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

        def modified?
          @modified
        end

        def data
          if cookie = @context.request.cookies[@store.key]?
            cookie.value ||= UUID.random.to_s
          else
            cookie = @context.request.cookies[@store.key] = UUID.random.to_s
          end

          redis_key = "#{@store.key}-#{cookie.value}"
          (@data ||= @store.as(RedisStore).load(redis_key)).not_nil!
        end

        def json
          @data.to_json
        end
      end
    end
  end
end
