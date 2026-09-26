# frozen_string_literal: true

require_relative "test_helper"

class CacheTest < Minitest::Test
  CLASS_METHOD_MUTEX = Mutex.new

  def setup
    if name.start_with?("test_class_")
      CLASS_METHOD_MUTEX.lock
      @class_method_locked = true
    end
    @temp_files = []
    @cache_dirs = []
  end

  def teardown
    [ @cache, @cache2 ].compact.each do |cache|
      FileUtils.rm_rf(cache.dir) if cache&.dir && !cache.dir.empty?
    end

    @cache_dirs.each do |dir|
      FileUtils.rm_rf(dir) if Dir.exist?(dir)
    end

    @temp_files.each do |file|
      FileUtils.rm_f(file) if File.exist?(file)
    end

    if @class_method_locked
      $cache = nil
      CLASS_METHOD_MUTEX.unlock
    end
  end

  def test_set_stores_value_and_creates_file
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.set("test_key", "test_value")

    assert_equal "test_value", @cache.get("test_key")
    group_file = Dir.glob(File.join(@cache.dir, "*.json")).first

    assert_path_exists group_file
    content = JSON.parse(File.read(group_file))

    assert_equal "test_value", content["test_key"]
  end

  def test_set_creates_multiple_group_files
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.set("key1", "value1")
    @cache.set("key2", "value2")

    json_files = Dir.glob(File.join(@cache.dir, "*.json"))

    assert_operator json_files.length, :>=, 1
    json_files.each do |file|
      content = JSON.parse(File.read(file))

      assert_kind_of Hash, content
    end
  end

  def test_get_returns_nil_for_missing_key
    @cache = Cache.new(dir: unique_cache_dir)

    assert_nil @cache.get("nonexistent_key")
  end

  def test_get_retrieves_stored_value
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.set("my_key", "my_value")

    assert_equal "my_value", @cache.get("my_key")
  end

  def test_changed_returns_true_when_value_differs
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.set("key", "old_value")

    assert @cache.changed?("key", "new_value")
  end

  def test_changed_returns_false_when_value_matches
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.set("key", "same_value")

    refute @cache.changed?("key", "same_value")
  end

  def test_changed_returns_false_when_value_is_blank
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.set("key", "value")

    refute @cache.changed?("key", "")
    refute @cache.changed?("key", nil)
  end

  def test_changed_returns_true_for_new_key
    @cache = Cache.new(dir: unique_cache_dir)

    assert @cache.changed?("new_key", "value")
  end

  def test_unchanged_returns_true_when_value_matches
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.set("key", "same_value")

    assert @cache.unchanged?("key", "same_value")
  end

  def test_unchanged_returns_false_when_value_differs
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.set("key", "old_value")

    refute @cache.unchanged?("key", "new_value")
  end

  def test_clear_removes_all_cache_files
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.set("key1", "value1")
    @cache.set("key2", "value2")
    @cache.set("key3", "value3")

    refute_empty Dir.glob(File.join(@cache.dir, "*.json"))

    @cache.clear

    assert_equal 0, Dir.glob(File.join(@cache.dir, "*.json")).length
    assert_nil @cache.get("key1")
    assert_nil @cache.get("key2")
    assert_nil @cache.get("key3")
  end

  def test_clear_on_empty_cache
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.clear

    assert_equal 0, Dir.glob(File.join(@cache.dir, "*.json")).length
  end

  def test_if_files_changed_executes_block_on_first_run
    @cache = Cache.new(dir: unique_cache_dir)
    test_file = create_temp_file("initial content")
    executed = false

    @cache.if_files_changed(test_file) do
      executed = true
    end

    assert executed
    group_file = Dir.glob(File.join(@cache.dir, "*.json")).first
    content = JSON.parse(File.read(group_file))
    expected = Digest::SHA256.hexdigest(File.binread(test_file))

    assert_includes content.values, expected
  end

  def test_if_files_changed_skips_block_when_unchanged
    @cache = Cache.new(dir: unique_cache_dir)
    test_file = create_temp_file("same content")
    execution_count = 0

    @cache.if_files_changed(test_file) do
      execution_count += 1
    end

    assert_equal 1, execution_count

    @cache.if_files_changed(test_file) do
      execution_count += 1
    end

    assert_equal 1, execution_count
  end

  def test_if_files_changed_executes_block_when_content_changes
    @cache = Cache.new(dir: unique_cache_dir)
    test_file = create_temp_file("initial content")
    execution_count = 0

    @cache.if_files_changed(test_file) do
      execution_count += 1
    end

    assert_equal 1, execution_count

    File.write(test_file, "changed content")

    @cache.if_files_changed(test_file) do
      execution_count += 1
    end

    assert_equal 2, execution_count
  end

  def test_if_files_changed_with_non_ascii_file_under_us_ascii
    @cache = Cache.new(dir: unique_cache_dir)
    test_file = create_temp_file("pnpm-lock — café")
    original_external = Encoding.default_external
    Encoding.default_external = Encoding::US_ASCII
    begin
      executed = false

      @cache.if_files_changed(test_file) do
        executed = true
      end

      assert executed
    ensure
      Encoding.default_external = original_external
    end
  end

  def test_if_files_changed_handles_multiple_files
    @cache = Cache.new(dir: unique_cache_dir)
    file1 = create_temp_file("content1")
    file2 = create_temp_file("content2")
    executed = false

    @cache.if_files_changed(file1, file2) do
      executed = true
    end

    assert executed
    group_file = Dir.glob(File.join(@cache.dir, "*.json")).first
    content = JSON.parse(File.read(group_file))
    expected = Digest::SHA256.hexdigest([ File.binread(file1), File.binread(file2) ].join("|"))

    assert_includes content.values, expected
  end

  def test_initialize_loads_existing_cache_files
    dir = unique_cache_dir
    FileUtils.mkdir_p(dir)
    group_key = "#{Digest::SHA256.hexdigest('existing_key')[0..1]}.json"
    File.write(File.join(dir, group_key), JSON.pretty_generate({ "existing_key" => "existing_value" }))

    @cache = Cache.new(dir: dir)

    assert_equal "existing_value", @cache.get("existing_key")
  end

  def test_group_key_distributes_keys_across_files
    @cache = Cache.new(dir: unique_cache_dir)

    keys = (1..20).map { |i| "key_#{i}" }
    keys.each_with_index { |key, i| @cache.set(key, "value_#{i}") }

    json_files = Dir.glob(File.join(@cache.dir, "*.json"))

    assert_operator json_files.length, :>, 1
    json_files.each do |file|
      assert_match(/^[0-9a-f]{2}\.json$/, File.basename(file))
    end
  end

  def test_values_are_converted_to_strings
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.set("int_key", 42)
    @cache.set("bool_key", true)
    @cache.set("symbol_key", :symbol)

    assert_equal "42", @cache.get("int_key")
    assert_equal "true", @cache.get("bool_key")
    assert_equal "symbol", @cache.get("symbol_key")
  end

  def test_keys_are_converted_to_strings
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.set(:symbol_key, "value")
    @cache.set(123, "number_value")

    assert_equal "value", @cache.get(:symbol_key)
    assert_equal "value", @cache.get("symbol_key")
    assert_equal "number_value", @cache.get(123)
    assert_equal "number_value", @cache.get("123")
  end

  def test_class_methods_use_global_cache
    dir1 = unique_cache_dir
    $cache = Cache.new(dir: dir1)

    Cache.set("global_key", "global_value")

    assert_equal "global_value", Cache.get("global_key")
    group_file = Dir.glob(File.join(dir1, "*.json")).first
    content = JSON.parse(File.read(group_file))

    assert_equal "global_value", content["global_key"]

    $cache = nil
  end

  def test_class_changed_method
    dir1 = unique_cache_dir
    $cache = Cache.new(dir: dir1)

    Cache.set("key", "value")

    assert Cache.changed?("key", "new_value")
    refute Cache.changed?("key", "value")

    $cache = nil
  end

  def test_class_unchanged_method
    dir1 = unique_cache_dir
    $cache = Cache.new(dir: dir1)

    Cache.set("key", "value")

    assert Cache.unchanged?("key", "value")
    refute Cache.unchanged?("key", "different_value")

    $cache = nil
  end

  def test_class_if_files_changed_method
    dir1 = unique_cache_dir
    $cache = Cache.new(dir: dir1)
    test_file = create_temp_file("content")
    executed = false

    Cache.if_files_changed(test_file) do
      executed = true
    end

    assert executed

    $cache = nil
  end

  def test_class_clear_method
    dir1 = unique_cache_dir
    $cache = Cache.new(dir: dir1)

    Cache.set("key", "value")

    assert Cache.get("key") && !Cache.get("key").empty?

    Cache.clear

    assert_nil Cache.get("key")
    assert_equal 0, Dir.glob(File.join(dir1, "*.json")).length

    $cache = nil
  end

  def test_multiple_cache_instances_are_independent
    @cache = Cache.new(dir: unique_cache_dir)
    @cache2 = Cache.new(dir: unique_cache_dir)

    @cache.set("shared_key", "cache1_value")
    @cache2.set("shared_key", "cache2_value")

    assert_equal "cache1_value", @cache.get("shared_key")
    assert_equal "cache2_value", @cache2.get("shared_key")

    cache1_files = Dir.glob(File.join(@cache.dir, "*.json"))
    cache2_files = Dir.glob(File.join(@cache2.dir, "*.json"))

    refute_equal cache1_files.first, cache2_files.first
  end

  def test_json_files_are_pretty_formatted
    @cache = Cache.new(dir: unique_cache_dir)

    @cache.set("test_key", "test_value")

    group_file = Dir.glob(File.join(@cache.dir, "*.json")).first
    file_content = File.read(group_file)

    assert_includes file_content, "\n"
    assert_includes file_content, "  "
  end

  def test_default_root_dir_uses_global_root_dir_when_defined
    begin
      original_root = $root_dir
      $root_dir = "/custom/root"

      assert_equal "/custom/root", Cache.default_root_dir
    ensure
      $root_dir = original_root
    end
  end

  def test_default_root_dir_falls_back_to_program_name_when_undefined
    begin
      original_root = $root_dir
      $root_dir = nil

      expected = File.expand_path(File.dirname($PROGRAM_NAME))

      assert_equal expected, Cache.default_root_dir
    ensure
      $root_dir = original_root
    end
  end

  def test_initialize_uses_default_root_dir_when_no_dir_provided
    test_root = File.join(Dir.tmpdir, "test_cache_root_#{SecureRandom.hex(8)}")
    begin
      original_root = $root_dir
      $root_dir = test_root

      cache = Cache.new
      expected_dir = File.join(test_root, "tmp/cache")

      assert_equal expected_dir, cache.dir
      assert Dir.exist?(expected_dir)

      FileUtils.rm_rf(test_root)
    ensure
      $root_dir = original_root
    end
  end

  private

  def unique_cache_dir
    dir = File.join(Dir.tmpdir, "cache_test_#{SecureRandom.hex(8)}")
    @cache_dirs << dir
    dir
  end

  def create_temp_file(content)
    file = File.join(Dir.tmpdir, "test_file_#{SecureRandom.hex(8)}.txt")
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, content)
    @temp_files << file
    file
  end
end
