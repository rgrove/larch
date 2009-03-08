module Larch
  class Error < StandardError; end

  class IMAP
    class Error < Larch::Error; end
    class FatalError < Error; end
    class NotFoundError < Error; end
  end
end
