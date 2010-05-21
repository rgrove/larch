# Monkeypatches for Net::IMAP.

module Net # :nodoc:
  class IMAP # :nodoc:
    class ResponseParser # :nodoc:
      private

      # Fixes an issue with bogus STATUS responses from Exchange that contain
      # trailing whitespace. This monkeypatch works cleanly against Ruby 1.8.x
      # and 1.9.x.
      def status_response
        token = match(T_ATOM)
        name = token.value.upcase
        match(T_SPACE)
        mailbox = astring
        match(T_SPACE)
        match(T_LPAR)
        attr = {}
        while true
          token = lookahead
          case token.symbol
          when T_RPAR
            shift_token
            break
          when T_SPACE
            shift_token
          end
          token = match(T_ATOM)
          key = token.value.upcase
          match(T_SPACE)
          val = number
          attr[key] = val
        end

        # Monkeypatch starts here...
        token = lookahead
        shift_token if token.symbol == T_SPACE
        # ...and ends here.

        data = StatusData.new(mailbox, attr)
        return UntaggedResponse.new(name, data, @str)
      end

      if RUBY_VERSION <= '1.9.1'

        # Monkeypatches Net::IMAP in Ruby <= 1.9.1 to fix broken response
        # handling, particularly when changing mailboxes on a Dovecot 1.2+
        # server.
        #
        # This monkeypatch shouldn't be necessary in Ruby 1.9.2 and higher.
        # It's included in Ruby 1.9 SVN trunk as of 2010-02-08.
        def resp_text_code
          @lex_state = EXPR_BEG
          match(T_LBRA)
          token = match(T_ATOM)
          name = token.value.upcase
          case name
          when /\A(?:ALERT|PARSE|READ-ONLY|READ-WRITE|TRYCREATE|NOMODSEQ)\z/n
            result = ResponseCode.new(name, nil)
          when /\A(?:PERMANENTFLAGS)\z/n
            match(T_SPACE)
            result = ResponseCode.new(name, flag_list)
          when /\A(?:UIDVALIDITY|UIDNEXT|UNSEEN)\z/n
            match(T_SPACE)
            result = ResponseCode.new(name, number)
          else
            token = lookahead
            if token.symbol == T_SPACE
              shift_token
              @lex_state = EXPR_CTEXT
              token = match(T_TEXT)
              @lex_state = EXPR_BEG
              result = ResponseCode.new(name, token.value)
            else
              result = ResponseCode.new(name, nil)
            end
          end
          match(T_RBRA)
          @lex_state = EXPR_RTEXT
          return result
        end
      end

    end

  end
end
