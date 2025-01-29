require "http/client"
require "http/headers"
require "lexbor"

require "./memory_session"

class Armature::TestSession < HTTP::Client
  private DEFAULT_HEADERS = HTTP::Headers.new

  @host = ""
  @port = -1
  getter cookies = HTTP::Cookies.new
  getter session_store : Session::MemoryStore
  getter session : Session::MemoryStore::Session do
    session_store.load cookies, session_id
  end
  getter session_id : String = Random::Secure.hex
  getter! last_request : HTTP::Request
  getter! last_response : HTTP::Client::Response

  def self.new(
    app : Armature::Route,
    cookie_key = "test_session",
    default_headers = DEFAULT_HEADERS.dup,
  )
    session_store = make_session_store(cookie_key)
    session_store.next = PassThrough.new(app)
    new(
      http_client: HotTopic.new(session_store),
      session_key: cookie_key,
      session_store: session_store,
      default_headers: default_headers,
    )
  end

  def initialize(
    @http_client : HTTP::Client,
    @session_key : String,
    @session_store : Session::MemoryStore,
    @default_headers : HTTP::Headers,
  )
  end

  delegate :[], :[]?, to: session

  def authenticity_token
    Armature::Form::Helper.authenticity_token_for(session)
  end

  def []=(key : String, value)
    session[key] = value
    cookies << HTTP::Cookie.new(@session_key, session_id, expires: 5.minutes.from_now)
    value
  end

  def visit(path : String)
    get path
  end

  def fill_in(selector, with value : String)
    if element = find_element(selector)
      case element.tag_name
      when "input"
        element["value"] = value
      when "textarea"
        element.inner_text = value
      else
        raise "Don't know how to fill in a #{element.tag_name} element"
      end
    else
      raise "No element with the selector #{selector.inspect}"
    end
  end

  def fill_in_all(selector, with value : String)
    document.css(selector).each do |element|
      element["value"] = value
    end
  end

  def click_link(text : String)
    link = find_element("a", text: text)

    if link
      visit link["href"]
    else
      raise "Cannot find a link on the page with the text #{text.inspect}"
    end
  end

  def click_button(text : String | Regex, follow_redirects : Bool = true) : HTTP::Client::Response
    button = find_element("button", text: text) ||
             find_element("input[type=submit]") { |i| i["value"] =~ text }

    if button
      if button["type"]? != "button" && (form = closest(button, "form"))
        stuff = URI::Params.new
        form.css("input").each do |input|
          if (name = input["name"]?) && (value = input["value"]?)
            stuff[name] = value
          end
        end
        form.css("textarea").each do |textarea|
          if (name = textarea["name"]?) && (value = textarea.inner_text)
            stuff[name] = value
          end
        end
        if (name = button["name"]?) && (value = button["value"]?)
          stuff[name] = value
        end
        headers = HTTP::Headers{"content-type" => "x-www-form-urlencoded"}
        request = HTTP::Request.new(
          method: form.fetch("method", "GET"),
          resource: form.fetch("action") { last_request.resource },
          headers: headers,
          body: stuff.to_s,
        )

        response = exec(request)

        while response.status_code.in?(300...400) && (location = response.headers["location"]?)
          response = get(location)
        end

        response
      elsif url = button["hx-get"]?
        uri = URI.parse(url)
        request = HTTP::Request.new(
          method: "GET",
          resource: "#{uri.path}?#{uri.query}",
        )
        prev_response = last_response
        prev_request = last_request
        prev_document = document

        response = exec(request)
        # We want the last page loaded, really, so in this case `last_response` is kinda wrong
        @last_response = prev_response
        @last_request = prev_request
        @document = prev_document

        if target_selector = button["hx-target"]?
          unless target = find_element(target_selector)
            raise "Could not find an element on the page matching the selector #{target_selector} as specified in #{button}"
          end
        else
          target = button
        end
        target.inner_html = response.body

        while response.status_code.in?(300...400) && (location = response.headers["location"]?)
          response = get(location)
        end

        response
      else
        raise "No form associated with the button with text #{text.inspect}\nHTML: #{last_response.body.strip}"
      end
    else
      raise "Cannot find a button on the page with the text #{text.inspect}\nHTML: #{document.to_html.strip}"
    end
  end

  def find_element(css : String)
    find_element(css) { true }
  end

  def find_element(css : String, *, text : String)
    find_element css, &.inner_text.includes?(text)
  end

  def find_element(css : String, *, text regex : Regex)
    find_element(css) { |e| e.inner_text =~ regex }
  end

  def find_element(css : String, & : Lexbor::Node ->) : Lexbor::Node?
    document
      .css(css)
      .find { |e| yield(e) }
  end

  private def closest(node, tag_name : String)
    while node = node.parent
      if node.tag_name == tag_name
        return node
      end
    end
  end

  getter document : Lexbor::Parser do
    body = last_response.body_io? || last_response.body
    Lexbor::Parser.new(body)
  end

  private def exec_internal(request : HTTP::Request)
    request.headers.merge! @default_headers
    Log.with_context do
      @cookies.add_request_headers request.headers
      @last_request = request
      response = @http_client.exec(request)
      response.cookies.each { |cookie| @cookies << cookie }

      @document = nil
      @last_response = response
    end
  end

  private def self.make_session_store(cookie_key)
    Armature::Session::MemoryStore.new(key: cookie_key)
  end

  class PassThrough
    include HTTP::Handler

    def initialize(@app : Route)
    end

    def call(context)
      @app.call context
    end
  end
end
