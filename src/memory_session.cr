require "json"

require "./session"

class Armature::Session::MemoryStore < Armature::Session::Store
  private getter data : Hash(String, Hash(String, JSON::Any)) do
    Hash(String, Hash(String, JSON::Any)).new do |hash, key|
      hash[key] = {} of String => JSON::Any
    end
  end
  getter log : Log { Log.for("session") }

  def call(context)
    unless session_id = context.request.cookies[@key]?.try(&.value)
      session_id = Random::Secure.hex
      context.response.cookies[@key] = session_id
    end

    context.session = session = load(context.request.cookies, session_id)
    call_next context
  end

  def load(cookies, session_id : String)
    Session.new(self, cookies, data[session_id])
  end

  class Session < Armature::Session
    alias Data = Hash(String, JSON::Any)
    protected getter data = Data.new

    def initialize(store, cookies, @data = Data.new)
      super store, cookies
    end

    def [](key : String)
      data[key]
    end

    def []?(key : String)
      data[key]?
    end

    def []=(key : String, value : Bytes)
      self[key] = String.new(value)
    end

    def []=(key : String, value : JSON::Any::Type)
      self[key] = JSON::Any.new(value)
    end

    def []=(key : String, value : JSON::Any)
      data[key] = value
    end

    def delete(key : String)
      data.delete key
    end
  end
end
