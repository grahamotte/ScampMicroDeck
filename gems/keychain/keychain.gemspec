# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "keychain"
  spec.version = "0.0.0"
  spec.authors = [ "Graham Otte" ]
  spec.summary = "macOS keychain configuration guard for Code Moto tasks"
  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = [ "lib" ]

  spec.add_development_dependency "minitest", "6.0.6"
end
