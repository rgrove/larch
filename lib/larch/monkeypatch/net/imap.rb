# Monkeypatch Net::IMAP in Ruby <= 1.9.1 to fix broken response handling,
# particularly when changing mailboxes on a Dovecot 1.2+ server.
#
# This monkeypatch shouldn't be necessary in Ruby 1.9.2 and higher.

if RUBY_VERSION <= '1.9.1'
  module Net # :nodoc:
    class IMAP # :nodoc:
      class ResponseParser # :nodoc:
        private

        # This monkeypatched method is the one included in Ruby 1.9 SVN trunk as
        # of 2010-02-08.
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
