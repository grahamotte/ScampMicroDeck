require_relative "test_helper"

class SafetyTest < Minitest::Test
  def test_blocks_commands
    assert_raises(UnsafeTestOperation) { system("true") }
    assert_raises(UnsafeTestOperation) { `true` }
    assert_raises(UnsafeTestOperation) { Process.spawn("true") }
    assert_raises(UnsafeTestOperation) { IO.popen("true") }
    assert_raises(UnsafeTestOperation) { Cmd.local("true") }
    assert_raises(UnsafeTestOperation) { Cmd.ssh("true") }
  end

  def test_blocks_requests
    assert_raises(UnsafeTestOperation) { Req.call(url: "https://example.com") }
    assert_raises(WebMock::NetConnectNotAllowedError) { Faraday.get("https://example.com") }
    assert_raises(UnsafeTestOperation) { TCPSocket.new("example.com", 80) }
  end

  def test_ruby_packages_have_one_unit_test_file
    expected = { "deploy" => "", "manager" => "lib/", "publish" => "" }.flat_map do |package, flattened|
      Dir[File.join(repo_root, package, "{lib,patches}/**/*.rb")]
        .map { |path| path.delete_prefix("#{repo_root}/#{package}/").delete_suffix(".rb") }
        .reject { |path| path == "lib/require" }
        .map { |path| File.join(package, "tests", path.delete_prefix(flattened)) }
    end
    actual = Dir[File.join(repo_root, "{deploy,manager,publish}/tests/**/*_test.rb")]
      .map { |path| path.delete_prefix("#{repo_root}/").delete_suffix("_test.rb") }
      .reject { |path| path.end_with?("/tests/safety") }

    refute_empty expected
    assert_empty expected - actual
    assert_empty actual - expected
  end

  def test_frontend_and_gems_have_one_unit_test_file
    frontend_sources = Dir[File.join(repo_root, "frontend/{components,utils}/*.{ts,tsx}")]
      .map { |path| File.basename(path).sub(/\.tsx?\z/, "") }
      .sort
    frontend_tests = Dir[File.join(repo_root, "frontend/tests/{components,utils}/*.test.{ts,tsx}")]
      .map { |path| File.basename(path).sub(/\.test\.tsx?\z/, "") }
      .sort
    gem_sources = Dir[File.join(repo_root, "gems/*/lib/*.rb")]
    missing_gem_tests = gem_sources.reject do |path|
      gem_root = File.dirname(File.dirname(path))
      File.file?(File.join(gem_root, "test", "#{File.basename(path, ".rb")}_test.rb"))
    end

    refute_empty frontend_sources
    refute_empty gem_sources
    assert_equal frontend_sources, frontend_tests
    assert_equal [], missing_gem_tests
  end

  def test_unit_tests_only_mock_boundaries
    tests = Dir[File.join(__dir__, "**/*_test.rb")]
      .reject { |path| path.end_with?("safety_test.rb") }
      .map { |path| File.read(path) }
      .join("\n")

    refute_match(/\b(?!Cmd|Req)\w+\.(?:stubs|expects)\(/, tests)
  end

  private

  def repo_root = File.expand_path("../..", __dir__)
end
