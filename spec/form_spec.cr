require "./spec_helper"
require "xml"

require "../src/form"
require "../src/redis_session"

private macro make_response_and_session
  %response = IO::Memory.new
  %session_id = UUID.random.to_s
  %session = Armature::Session::RedisStore::Session.new(
    store: redis_store,
    cookies: HTTP::Cookies{"armature-test" => %session_id},
  )

  {
    %response,
    %session,
  }
end

struct FormTestRoute
  include Armature::Form::Helper

  def initialize(@method : String? = nil, @action : String? = nil)
  end

  def call(response, session)
    # `form` is a macro that uses the response and session variables. In order
    # to specify an authenticity token, the method must not be GET/HEAD
    form method: @method, action: @action, "data-foo": "bar" do
      # ...
      response << "<input name=lol>"
    end

    XML.parse_html response.rewind
  end
end

redis = Redis::Client.new
redis_store = Armature::Session::RedisStore.new(
  key: "armature-test",
  redis: redis,
  expiration: 1.minute,
)

describe Armature::Form do
  it "sets method attribute for the form" do
    response, session = make_response_and_session

    html = FormTestRoute.new(method: "POST").call response, session

    if form = html.xpath_node("//form")
      form["method"].should eq "POST"
    else
      raise "Missing form"
    end
  end

  it "sets action attribute for the form" do
    response, session = make_response_and_session

    html = FormTestRoute.new(action: "/foo").call response, session

    if form = html.xpath_node("//form")
      form["action"].should eq "/foo"
    else
      raise "Missing form"
    end
  end

  it "sets arbitrary attributes for the form" do
    response, session = make_response_and_session

    html = FormTestRoute.new.call response, session

    if form = html.xpath_node("//form")
      form["data-foo"].should eq "bar"
    else
      raise "Missing form"
    end
  end

  it "adds an authenticity token to the form" do
    response, session = make_response_and_session

    html = FormTestRoute.new("POST", "/").call response, session

    if node = html.xpath_node("//input[@name='_authenticity_token']")
      valid_token = Armature::Form::Helper.valid_authenticity_token?(
        form_params: URI::Params{"_authenticity_token" => node["value"]},
        session: session
      )

      valid_token.should eq true
    else
      raise "Missing authenticity token param"
    end
  end

  it "marks a bogus authenticity token as invalid" do
    session_id = UUID.random.to_s
    session = Armature::Session::RedisStore::Session.new(
      store: redis_store,
      cookies: HTTP::Cookies{"armature-test" => session_id},
    )
    # Generate the CSRF token
    token = Armature::Form::Helper.authenticity_token_for session

    valid_token = Armature::Form::Helper.valid_authenticity_token?(
      form_params: URI::Params{"_authenticity_token" => "lolnope"},
      session: session,
    )

    valid_token.should eq false
  end
end
