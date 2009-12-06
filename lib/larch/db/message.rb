module Larch; module Database

class Message < Sequel::Model(:messages)
  def flags
    self[:flags].split(',').sort.map do |f|
      # Flags beginning with $ should be strings; all others should be symbols.
      f[0,1] == '$' ? f : f.to_sym
    end
  end

  def flags_str
    self[:flags]
  end

  def flags=(flags)
    self[:flags] = flags.map{|f| f.to_s }.join(',')
  end
end

end; end
