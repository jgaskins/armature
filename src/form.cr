require "./session"

module Armature
  struct Form
    def initialize(@response : IO, @session : Armature::Session)
    end

    def call(method : String? = nil, action : String? = nil, **kwargs)
      @response << "<form"
      @response << %{ method="#{method}"} if method
      @response << %{ action="#{action}"} if action
      kwargs.each do |key, value|
        @response << ' ' << key << '='
        case value
        when String
          value.inspect @response
        when Nil
          @response << %{""}
        else
          @response << '"' << value << '"'
        end
      end
      @response << '>'
      yield
      @response << "</form>"
    end

    module Helper
      extend self

      macro form(method = nil, action = nil, response = "response", session = "session", **kwargs, &block)
        {% kwargs = "NamedTuple.new".id if kwargs.empty? %}
        ::Armature::Form.new(response: {{response.id}}, session: {{session.id}}).call(**{{kwargs}}, method: {{method}}, action: {{action}}) do {% unless block.args.empty? %} |{{block.args.join(", ").id}}| {% end %}
          unless ({{method}} || "").upcase.in?({"GET", "HEAD", ""})
            {{response.id}} << %{<input type="hidden" name="_authenticity_token" value="#{authenticity_token_for({{session.id}})}"/>}
          end
          {{yield}}
        end
      end

      def authenticity_token_for(session)
        token = Bytes.new(64)
        padded = token + 32
        one_time_pad = Random::Secure.random_bytes(32)
        if csrf = session["csrf"]?.try(&.as_s?)
          csrf = Base64.decode csrf
        else
          csrf = Random::Secure.random_bytes(32)
          session["csrf"] = Base64.strict_encode(csrf)
        end

        csrf.each_with_index do |byte, index|
          padded[index] = byte ^ one_time_pad[index]
          token[index] = one_time_pad[index]
        end

        Base64.strict_encode token
      end

      def valid_authenticity_token?(form_params : URI::Params, session)
        return false unless token = form_params["_authenticity_token"]?
        if csrf = session["csrf"]?.try(&.as_s?)
          csrf = Base64.decode csrf
        else
          return false
        end

        token = Base64.decode(token)
        pad = token[0...32]
        challenge = token[32...64]
        challenge.each_with_index do |byte, index|
          challenge[index] = byte ^ pad[index]
        end
        challenge == csrf
      rescue ex : IndexError
        false
      end
    end
  end
end
