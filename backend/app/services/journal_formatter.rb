module JournalFormatter
  PRIORITIES = {
    "DEBUG" => 7,
    "INFO" => 6,
    "WARN" => 4,
    "ERROR" => 3,
    "FATAL" => 2,
  }.freeze

  def self.install(logger)
    loggers = logger.respond_to?(:broadcasts) ? logger.broadcasts : [ logger ]
    loggers.each { |x| x.formatter.extend(self) unless x.formatter.is_a?(self) }
  end

  def call(severity, time, progname, msg)
    "<#{PRIORITIES.fetch(severity, 2)}>#{super.sub(/\n+\z/, "").gsub("\n", "\\n")}\n"
  end
end
