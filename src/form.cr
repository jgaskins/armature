require "./session"

module Armature
  struct Form
    def initialize(@response : IO, @session : Armature::Session)
    end

    def call(**kwargs : String?)
      @response << "<form"
      kwargs.each do |key, value|
        if value = value.presence
          @response << ' '
          HTML.escape key.to_s, @response
          @response << '='
          @response << '"'
          HTML.escape value, @response
          @response << '"'
        else
          @response << %{""}
        end
      end
      @response << '>'
      yield
      @response << "</form>"
    end

    module Helper
      extend self

      macro form(response = "response", session = "session", **kwargs, &block)
        {% kwargs = "NamedTuple.new".id if kwargs.empty? %}
        ::Armature::Form.new(response: {{response.id}}, session: {{session.id}}).call(**{{kwargs}}) do {% unless block.args.empty? %} |{{block.args.join(", ").id}}| {% end %}
          unless ({{kwargs[:method]}} || "").upcase.in?({"GET", "HEAD", ""})
            {{response.id}} << %{<input type="hidden" name="_authenticity_token" value="#{authenticity_token_for({{session.id}})}"/>}
          end
          {{yield}}
        end
      end

      def authenticity_token_for(session)
        token = Bytes.new(64)
        padded = token + 32
        one_time_pad = Random::Secure.random_bytes(32)
        if csrf = unwrap_session_value(session["csrf"]?)
          csrf = Base64.decode csrf
        else
          csrf = generate_authenticity_token!(session)
        end

        csrf.each_with_index do |byte, index|
          padded[index] = byte ^ one_time_pad[index]
          token[index] = one_time_pad[index]
        end

        Base64.strict_encode token
      end

      def generate_authenticity_token!(session)
        csrf = Random::Secure.random_bytes(32)
        session["csrf"] = Base64.strict_encode(csrf)
        csrf
      end

      def valid_authenticity_token?(form_params : URI::Params, session)
        return false unless token = form_params["_authenticity_token"]?
        if csrf = unwrap_session_value(session["csrf"]?)
          csrf = Base64.decode csrf
          return false if csrf.size != 32
        else
          return false
        end

        token = Base64.decode(token)
        return false if token.size != 64

        pad = token[0...32]
        challenge = token[32...64]

        challenge.each_with_index do |byte, index|
          challenge[index] = byte ^ pad[index]
        end

        challenge == csrf
      end

      def unwrap_session_value(value)
        # Handle types like JSON::Any and MessagePack::Any that respond to `.as_s?`
        if value.responds_to? :as_s?
          value.as_s?
        else
          value
        end
      end
    end
  end
end
