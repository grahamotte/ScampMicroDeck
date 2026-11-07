Gem::Specification.new do |spec|
  spec.name = "test_safety"
  spec.version = "0.0.0"
  spec.authors = [ "Graham Otte" ]
  spec.summary = "Blocks unstubbed commands and network calls in tests"
  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = [ "lib" ]

  spec.add_development_dependency "minitest", "6.1.0"
end
