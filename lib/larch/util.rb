class Module

  # Java-style whole-method synchronization, shamelessly stolen from Sup:
  # http://sup.rubyforge.org. Assumes the existence of a <tt>@mutex</tt>
  # variable.
  def synchronized(*methods)
    methods.each do |method|
      class_eval <<-EOF
        alias unsync_#{method} #{method}
        def #{method}(*a, &b)
          @mutex.synchronize { unsync_#{method}(*a, &b) }
        end
      EOF
    end
  end

end
