require "http/cookies"
require "http/server/handler"

module Armature
  abstract class Session
    def initialize(@store : Store, @cookies : HTTP::Cookies)
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
    def initialize(@store, @cookies)
    end

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
      @session : Armature::Session?

      def session : Armature::Session
        @session ||= Armature::BlankSession.new(
          store: Armature::BlankSession::Store.new(""),
          cookies: self.request.cookies,
        )
      end

      def session=(session : Armature::Session) : Nil
        @session = session
      end
    end
  end
end
