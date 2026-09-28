class BasePatch
  class << self
    def call
      start_time = Time.now
      puts "\n////// #{name.split("::").last.underscore.gsub("_", " ").as_title} //////\n".magenta

      always
      apply if needed?

      puts "took #{(Time.now - start_time).round(2)}s"
    end

    def needed?
      true
    end

    def apply; end

    def always; end

    def pry
      binding.pry
    end
  end
end
