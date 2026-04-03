require "http/cookies"
require "http/server/handler"

module Armature
  abstract class Session
    getter store : Store
    getter id : String
    getter cookies : HTTP::Cookies

    def self.new(store : Store, cookies : HTTP::Cookies)
      new(
        store: store,
        cookies: cookies,
        id: UUID.v7.to_s,
      )
    end

    def initialize(@store, @id, @cookies)
    end

    abstract def [](key : String)

    abstract def []=(key : String, value : String)

    abstract def delete(key : String)

    abstract class Store
      include HTTP::Handler

      getter key : String

      def initialize(@key)
      end
    end
  end

  class BlankSession < Session
    def [](key)
    end

    def []=(key, value)
    end

    def []?(key)
    end

    def delete(key)
    end

    class Store < Session::Store
      def call(context)
      end

      def key
        ""
      end
    end
  end
end

module HTTP
  class Server
    class Context
      property session : Armature::Session do
        Armature::BlankSession.new(
          store: Armature::BlankSession::Store.new(""),
          cookies: self.request.cookies,
        )
      end
    end
  end
end
