# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "path"
  spec.version = "0.0.0"
  spec.authors = [ "Graham Otte" ]
  spec.summary = "Simple path utility"
  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "base64", "0.3.0"

  spec.add_development_dependency "minitest", "6.0.6"
end
