# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "link"
  spec.version = "0.0.0"
  spec.authors = [ "Graham Otte" ]
  spec.summary = "URL parsing and manipulation utility"
  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "addressable", "2.9.0"
  spec.add_dependency "path", "0.0.0"
  spec.add_dependency "uri", "1.1.2"

  spec.add_development_dependency "minitest", "6.0.6"
end
