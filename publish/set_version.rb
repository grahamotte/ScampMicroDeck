require_relative "lib/require"

Apps::VersionSetter.call(ARGV.fetch(0))
