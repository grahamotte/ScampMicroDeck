# frozen_string_literal: true

require_relative "test_helper"

class PathTest < Minitest::Test
  def setup
    @temp_dir = File.join(Dir.tmpdir, "path_test_#{SecureRandom.hex(8)}")
    @temp_files = []
    FileUtils.mkdir_p(@temp_dir)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if Dir.exist?(@temp_dir)
    @temp_files.each do |file|
      FileUtils.rm_rf(file) if File.exist?(file) || Dir.exist?(file)
    end
  end

  def test_dir_returns_true_for_directory
    dir_path = File.join(@temp_dir, "test_dir")
    FileUtils.mkdir_p(dir_path)

    assert Path.dir?(dir_path)
  end

  def test_dir_returns_true_for_path_ending_with_slash
    assert Path.dir?("/some/path/")
  end

  def test_dir_returns_false_for_file
    file_path = create_temp_file("content")

    refute Path.dir?(file_path)
  end

  def test_file_returns_true_for_file
    file_path = create_temp_file("content")

    assert Path.file?(file_path)
  end

  def test_file_returns_false_for_directory
    dir_path = File.join(@temp_dir, "test_dir")
    FileUtils.mkdir_p(dir_path)

    refute Path.file?(dir_path)
  end

  def test_file_returns_false_for_path_ending_with_slash
    refute Path.file?("/some/path/")
  end

  def test_exists_returns_true_for_existing_file
    file_path = create_temp_file("content")

    assert Path.exists?(file_path)
  end

  def test_exists_returns_false_for_nonexistent_file
    refute Path.exists?(File.join(@temp_dir, "nonexistent"))
  end

  def test_exist_is_alias_for_exists
    file_path = create_temp_file("content")

    assert Path.exist?(file_path)
    refute Path.exist?(File.join(@temp_dir, "nonexistent"))
  end

  def test_does_not_exist_returns_true_for_nonexistent_file
    assert Path.does_not_exist?(File.join(@temp_dir, "nonexistent"))
  end

  def test_does_not_exist_returns_false_for_existing_file
    file_path = create_temp_file("content")

    refute Path.does_not_exist?(file_path)
  end

  def test_empty_dir_returns_true_for_empty_directory
    dir_path = File.join(@temp_dir, "empty_dir")
    FileUtils.mkdir_p(dir_path)

    assert Path.empty_dir?(dir_path)
  end

  def test_empty_dir_returns_false_for_nonempty_directory
    dir_path = File.join(@temp_dir, "nonempty_dir")
    FileUtils.mkdir_p(dir_path)
    File.write(File.join(dir_path, "file.txt"), "content")

    refute Path.empty_dir?(dir_path)
  end

  def test_mkdir_creates_directory
    dir_path = File.join(@temp_dir, "new_dir")
    Path.mkdir(dir_path)

    assert Dir.exist?(dir_path)
  end

  def test_mkdir_creates_nested_directories
    dir_path = File.join(@temp_dir, "parent/child/grandchild")
    Path.mkdir(dir_path)

    assert Dir.exist?(dir_path)
  end

  def test_mkdir_does_not_error_if_directory_exists
    dir_path = File.join(@temp_dir, "existing_dir")
    FileUtils.mkdir_p(dir_path)
    Path.mkdir(dir_path)

    assert Dir.exist?(dir_path)
  end

  def test_mtime_returns_modification_time
    file_path = create_temp_file("content")
    mtime = Path.mtime(file_path)

    assert_instance_of Time, mtime
  end

  def test_size_returns_file_size
    file_path = create_temp_file("hello world")

    assert_equal 11, Path.size(file_path)
  end

  def test_md5_returns_md5_hash
    file_path = create_temp_file("content")
    md5 = Path.md5(file_path)

    assert_match(/^[a-f0-9]{32}$/, md5)
  end

  def test_quick_hash_returns_consistent_hash
    file_path = create_temp_file("content")
    hash1 = Path.quick_hash(file_path)
    hash2 = Path.quick_hash(file_path)

    assert_equal hash1, hash2
  end

  def test_quick_hash_changes_when_file_modified
    file_path = create_temp_file("content")
    hash1 = Path.quick_hash(file_path)
    File.write(file_path, "different content with different size")
    hash2 = Path.quick_hash(file_path)

    refute_equal hash1, hash2
  end

  def test_extension_returns_file_extension
    assert_equal :txt, Path.extension("file.txt")
    assert_equal :rb, Path.extension("script.rb")
    assert_equal :jpeg, Path.extension("image.JPEG")
  end

  def test_extension_handles_no_extension
    assert_nil Path.extension("noext")
  end

  def test_extension_handles_urls
    assert_equal :jpg, Path.extension("https://example.com/image.jpg")
    assert_equal :png, Path.extension("http://example.com/path/to/file.png")
    assert_equal :pdf, Path.extension("https://example.com/document.pdf?query=param")
  end

  def test_extension_handles_invalid_urls
    assert_nil Path.extension("http://[invalid")
  end

  def test_ext_is_alias_for_extension
    assert_equal :txt, Path.ext("file.txt")
  end

  def test_title_name_returns_filename_without_extension
    assert_equal "document", Path.title_name("document.pdf")
    assert_equal "file.backup", Path.title_name("file.backup.txt")
  end

  def test_title_name_handles_no_extension
    assert_equal "filename", Path.title_name("filename")
  end

  def test_title_name_handles_dotfile
    assert_equal ".", Path.title_name(".gitignore")
  end

  def test_title_is_alias_for_title_name
    assert_equal "document", Path.title("document.pdf")
  end

  def test_basename_returns_filename
    assert_equal "file.txt", Path.basename("/path/to/file.txt")
  end

  def test_filename_is_alias_for_basename
    assert_equal "file.txt", Path.filename("/path/to/file.txt")
  end

  def test_file_name_is_alias_for_basename
    assert_equal "file.txt", Path.file_name("/path/to/file.txt")
  end

  def test_dirname_returns_directory_name
    assert_equal "/path/to", Path.dirname("/path/to/file.txt")
  end

  def test_dir_is_alias_for_dirname
    assert_equal "/path/to", Path.dir("/path/to/file.txt")
  end

  def test_folder_is_alias_for_dirname
    assert_equal "/path/to", Path.folder("/path/to/file.txt")
  end

  def test_depth_returns_slash_count
    assert_equal 0, Path.depth("file.txt")
    assert_equal 2, Path.depth("/path/file.txt")
    assert_equal 3, Path.depth("/path/to/file.txt")
  end

  def test_join_joins_paths
    result = Path.join("path", "to", "file.txt")

    assert_includes result, "path/to/file.txt"
  end

  def test_join_expands_paths
    result = Path.join("~", "file.txt")

    assert result.start_with?(ENV["HOME"])
  end

  def test_join_handles_nil_and_empty_values
    result = Path.join("path", nil, "", "file.txt")

    assert_includes result, "path/file.txt"
  end

  def test_join_handles_absolute_path_in_middle
    result = Path.join("base", "/absolute", "file.txt")

    assert_includes result, "absolute/file.txt"
  end

  def test_join_with_multiple_slashes
    result = Path.join("path//to///file")

    assert result.end_with?("path/to/file")
    refute_includes result, "//"
  end

  def test_slash_compact_removes_double_slashes
    assert_equal "/path/to/file", Path.slash_compact("/path//to///file")
  end

  def test_slash_compact_preserves_http_slashes
    assert_equal "http://example.com", Path.slash_compact("http://example.com")
    assert_equal "https://example.com", Path.slash_compact("https://example.com")
  end

  def test_slash_adds_front_slash
    assert_equal "/path", Path.slash("path")
  end

  def test_slash_removes_back_slash
    assert_equal "/path", Path.slash("/path/")
  end

  def test_slash_with_front_false
    assert_equal "path", Path.slash("path", front: false, back: true)
  end

  def test_slash_with_back_false
    assert_equal "/path/", Path.slash("path/", front: true, back: false)
  end

  def test_unslash_removes_front_slash
    assert_equal "path", Path.unslash("/path")
  end

  def test_unslash_removes_back_slash
    assert_equal "path", Path.unslash("path/")
  end

  def test_unslash_with_front_false
    assert_equal "/path", Path.unslash("/path", front: false, back: true)
  end

  def test_unslash_with_back_false
    assert_equal "path/", Path.unslash("path/", front: true, back: false)
  end

  def test_ls_lists_direct_children
    dir_path = File.join(@temp_dir, "ls_test")
    FileUtils.mkdir_p(dir_path)
    File.write(File.join(dir_path, "file1.txt"), "content")
    File.write(File.join(dir_path, "file2.txt"), "content")
    FileUtils.mkdir_p(File.join(dir_path, "subdir"))

    results = Path.ls(dir_path)

    assert_equal 3, results.length
  end

  def test_list_lists_all_descendants
    dir_path = File.join(@temp_dir, "list_test")
    FileUtils.mkdir_p(File.join(dir_path, "subdir"))
    File.write(File.join(dir_path, "file1.txt"), "content")
    File.write(File.join(dir_path, "subdir/file2.txt"), "content")

    results = Path.list(dir_path)

    assert_operator results.length, :>=, 2
  end

  def test_list_files_returns_only_files
    dir_path = File.join(@temp_dir, "list_files_test")
    FileUtils.mkdir_p(File.join(dir_path, "subdir"))
    File.write(File.join(dir_path, "file1.txt"), "content")
    File.write(File.join(dir_path, "subdir/file2.txt"), "content")

    results = Path.list_files(dir_path)

    assert results.all? { |f| Path.file?(f) }
  end

  def test_list_dirs_returns_only_directories
    dir_path = File.join(@temp_dir, "list_dirs_test")
    FileUtils.mkdir_p(File.join(dir_path, "subdir1"))
    FileUtils.mkdir_p(File.join(dir_path, "subdir2"))
    File.write(File.join(dir_path, "file.txt"), "content")

    results = Path.list_dirs(dir_path)

    assert results.all? { |d| Path.dir?(d) }
  end

  def test_touch_creates_file
    file_path = File.join(@temp_dir, "touched.txt")
    Path.touch(file_path)

    assert_path_exists file_path
  end

  def test_touch_updates_mtime_on_existing_file
    file_path = create_temp_file("content")
    original_mtime = File.mtime(file_path)
    original_stat = File.stat(file_path)
    Path.touch(file_path)
    new_stat = File.stat(file_path)

    assert_operator new_stat.mtime, :>=, original_mtime
    assert_path_exists file_path
  end

  def test_write_creates_file_with_content
    file_path = File.join(@temp_dir, "written.txt")
    Path.write("test content", file_path)

    assert_equal "test content", File.read(file_path)
  end

  def test_write_creates_parent_directories
    file_path = File.join(@temp_dir, "parent/child/file.txt")
    Path.write("content", file_path)

    assert_path_exists file_path
  end

  def test_binwrite_writes_binary_data
    file_path = File.join(@temp_dir, "binary.dat")
    data = [ 0x00, 0xFF, 0xAA ].pack("C*")
    Path.binwrite(data, file_path)

    assert_equal data, File.binread(file_path)
  end

  def test_binwrite_creates_parent_directories
    file_path = File.join(@temp_dir, "parent/child/binary.dat")
    data = [ 0x00, 0xFF ].pack("C*")
    Path.binwrite(data, file_path)

    assert_path_exists file_path
    assert_equal data, File.binread(file_path)
  end

  def test_chmod_changes_file_mode
    file_path = create_temp_file("content")
    Path.chmod(file_path, 0o644)
    stat = File.stat(file_path)

    assert_equal 0o644, stat.mode & 0o777
  end

  def test_read_reads_file_content
    file_path = create_temp_file("test content")

    assert_equal "test content", Path.read(file_path)
  end

  def test_binread_reads_binary_data
    file_path = File.join(@temp_dir, "binary.dat")
    data = [ 0x00, 0xFF, 0xAA ].pack("C*")
    File.binwrite(file_path, data)

    assert_equal data, Path.binread(file_path)
  end

  def test_read64_returns_base64_encoded_content
    file_path = create_temp_file("test content")
    base64 = Path.read64(file_path)

    assert_equal Base64.strict_encode64("test content"), base64
  end

  def test_read_json_parses_json_file
    file_path = File.join(@temp_dir, "data.json")
    File.write(file_path, JSON.generate({ key: "value" }))
    result = Path.read_json(file_path)

    assert_equal "value", result[:key]
  end

  def test_mv_moves_file
    source = create_temp_file("content")
    dest = File.join(@temp_dir, "moved.txt")
    Path.mv(source, dest)

    assert_path_exists dest
    refute_path_exists source
  end

  def test_mv_creates_parent_directories
    source = create_temp_file("content")
    dest = File.join(@temp_dir, "parent/child/moved.txt")
    Path.mv(source, dest)

    assert_path_exists dest
  end

  def test_mv_does_nothing_if_source_equals_dest
    file = create_temp_file("content")
    Path.mv(file, file)

    assert_path_exists file
  end

  def test_mv_raises_if_destination_file_exists
    source = create_temp_file("new")
    dest = File.join(@temp_dir, "existing.txt")
    File.write(dest, "old")

    error = assert_raises(RuntimeError) { Path.mv(source, dest) }

    assert_equal "#{dest} already exists", error.message
    assert_path_exists source
    assert_equal "old", File.read(dest)
  end

  def test_mv_raises_if_destination_dir_exists
    source = create_temp_file("content")
    dest = File.join(@temp_dir, "existing_dir")
    FileUtils.mkdir_p(dest)

    error = assert_raises(RuntimeError) { Path.mv(source, dest) }

    assert_equal "#{dest} already exists", error.message
    assert_path_exists source
    assert Dir.exist?(dest)
    refute_path_exists File.join(dest, File.basename(source))
  end

  def test_mv_overwrites_destination_file_when_overwrite_true
    source = create_temp_file("new")
    dest = File.join(@temp_dir, "existing.txt")
    File.write(dest, "old")
    Path.mv(source, dest, overwrite: true)

    assert_path_exists dest
    refute_path_exists source
    assert_equal "new", File.read(dest)
  end

  def test_mv_raises_if_destination_dir_exists_even_when_overwrite_true
    source = create_temp_file("content")
    dest = File.join(@temp_dir, "existing_dir")
    FileUtils.mkdir_p(dest)

    error = assert_raises(RuntimeError) { Path.mv(source, dest, overwrite: true) }

    assert_equal "#{dest} already exists", error.message
    assert_path_exists source
    assert Dir.exist?(dest)
    refute_path_exists File.join(dest, File.basename(source))
  end

  def test_cp_copies_file
    source = create_temp_file("content")
    dest = File.join(@temp_dir, "copied.txt")
    Path.cp(source, dest)

    assert_path_exists dest
    assert_path_exists source
    assert_equal "content", File.read(dest)
  end

  def test_cp_creates_parent_directories
    source = create_temp_file("content")
    dest = File.join(@temp_dir, "parent/child/copied.txt")
    Path.cp(source, dest)

    assert_path_exists dest
  end

  def test_cp_does_nothing_if_source_equals_dest
    file = create_temp_file("content")
    Path.cp(file, file)

    assert_path_exists file
  end

  def test_cp_raises_if_destination_file_exists
    source = create_temp_file("new")
    dest = File.join(@temp_dir, "existing.txt")
    File.write(dest, "old")

    error = assert_raises(RuntimeError) { Path.cp(source, dest) }

    assert_equal "#{dest} already exists", error.message
    assert_equal "new", File.read(source)
    assert_equal "old", File.read(dest)
  end

  def test_cp_raises_if_destination_dir_exists
    source = create_temp_file("content")
    dest = File.join(@temp_dir, "existing_dir")
    FileUtils.mkdir_p(dest)

    error = assert_raises(RuntimeError) { Path.cp(source, dest) }

    assert_equal "#{dest} already exists", error.message
    assert_path_exists source
    assert Dir.exist?(dest)
    refute_path_exists File.join(dest, File.basename(source))
  end

  def test_cp_overwrites_destination_file_when_overwrite_true
    source = create_temp_file("new")
    dest = File.join(@temp_dir, "existing.txt")
    File.write(dest, "old")
    Path.cp(source, dest, overwrite: true)

    assert_path_exists dest
    assert_path_exists source
    assert_equal "new", File.read(dest)
    assert_equal "new", File.read(source)
  end

  def test_cp_raises_if_destination_dir_exists_even_when_overwrite_true
    source = create_temp_file("content")
    dest = File.join(@temp_dir, "existing_dir")
    FileUtils.mkdir_p(dest)

    error = assert_raises(RuntimeError) { Path.cp(source, dest, overwrite: true) }

    assert_equal "#{dest} already exists", error.message
    assert_path_exists source
    assert Dir.exist?(dest)
    refute_path_exists File.join(dest, File.basename(source))
  end

  def test_rm_removes_file
    file = create_temp_file("content")
    Path.rm(file)

    refute_path_exists file
  end

  def test_rm_removes_directory
    dir = File.join(@temp_dir, "remove_me")
    FileUtils.mkdir_p(dir)
    Path.rm(dir)

    refute Dir.exist?(dir)
  end

  def test_rm_raises_error_for_home_directory
    assert_raises(RuntimeError) { Path.rm(ENV["HOME"]) }
  end

  def test_rm_raises_error_for_root_directory
    assert_raises(RuntimeError) { Path.rm("/") }
  end

  def test_rm_raises_error_for_blank_path
    assert_raises(RuntimeError) { Path.rm("") }
    assert_raises(RuntimeError) { Path.rm(nil) }
  end

  def test_rm_raises_error_for_home_directory_with_trailing_slash
    assert_raises(RuntimeError) { Path.rm("#{ENV['HOME']}/") }
  end

  def test_with_tmp_dir_creates_and_cleans_up_directory
    created_dir = nil
    Path.with_tmp_dir do |dir|
      created_dir = dir

      assert Dir.exist?(dir)
      File.write(File.join(dir, "test.txt"), "content")
    end

    refute Dir.exist?(created_dir)
  end

  def test_with_tmp_dir_cleans_up_on_error
    created_dir = nil
    begin
      Path.with_tmp_dir do |dir|
        created_dir = dir
        raise "test error"
      end
    rescue
    end

    refute Dir.exist?(created_dir)
  end

  def test_with_tmp_dir_raises_error_if_dir_exists_and_not_empty
    dir = File.join(@temp_dir, "nonempty")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "file.txt"), "content")
    assert_raises(RuntimeError) { Path.with_tmp_dir(dir) { } }
  end

  def test_with_tmp_dir_with_custom_empty_path
    custom_path = File.join(@temp_dir, "custom_tmp")
    FileUtils.mkdir_p(custom_path)
    Path.with_tmp_dir(custom_path) do |dir|
      assert_equal custom_path, dir

      assert Dir.exist?(dir)
      File.write(File.join(dir, "test.txt"), "content")
    end

    refute Dir.exist?(custom_path)
  end

  def test_with_tmp_dir_raises_error_if_path_is_file
    file_path = create_temp_file("content")
    assert_raises(RuntimeError) { Path.with_tmp_dir(file_path) { } }
  end

  def test_uniq_dirs_returns_unique_parent_directories
    paths = [
      "/path/to/file1.txt",
      "/path/to/file2.txt",
      "/path/other/file3.txt",
    ]
    result = Path.uniq_dirs(paths)

    assert_includes result, "/path"
    assert_includes result, "/path/to"
    assert_includes result, "/path/other"
  end

  def test_uniq_dirs_handles_nil_and_empty_values
    paths = [ "/path/to/file.txt", nil, "", "/other/file.txt" ]
    result = Path.uniq_dirs(paths)

    assert_includes result, "/path"
    assert_includes result, "/other"
  end

  def test_uniq_dirs_handles_single_string
    result = Path.uniq_dirs("/path/to/file.txt")

    assert_includes result, "/path"
    assert_includes result, "/path/to"
  end

  def test_mime_type_returns_correct_type_for_images
    assert_equal "image/jpeg", Path.mime_type("photo.jpg")
    assert_equal "image/png", Path.mime_type("graphic.png")
    assert_equal "image/gif", Path.mime_type("animation.gif")
  end

  def test_mime_type_returns_correct_type_for_videos
    assert_equal "video/mp4", Path.mime_type("video.mp4")
    assert_equal "video/quicktime", Path.mime_type("movie.mov")
  end

  def test_mime_type_returns_correct_type_for_audio
    assert_equal "audio/mpeg", Path.mime_type("song.mp3")
    assert_equal "audio/flac", Path.mime_type("track.flac")
    assert_equal "audio/quicktime", Path.mime_type("recording.qta")
  end

  def test_mime_type_returns_correct_type_for_documents
    assert_equal "application/pdf", Path.mime_type("document.pdf")
    assert_equal "text/plain", Path.mime_type("readme.txt")
  end

  def test_mime_type_returns_directory_for_directories
    dir = File.join(@temp_dir, "dir_test")
    FileUtils.mkdir_p(dir)

    assert_equal "inode/directory", Path.mime_type(dir)
  end

  def test_mime_type_returns_octet_stream_for_unknown_extension
    assert_equal "application/octet-stream", Path.mime_type("file.unknown")
  end

  def test_mime_type_comprehensive_image_types
    assert_equal "image/heic", Path.mime_type("photo.heic")
    assert_equal "image/tiff", Path.mime_type("scan.tif")
    assert_equal "image/tiff", Path.mime_type("scan.tiff")
    assert_equal "image/webp", Path.mime_type("image.webp")
    assert_equal "image/avif", Path.mime_type("modern.avif")
  end

  def test_mime_type_comprehensive_video_types
    assert_equal "video/avi", Path.mime_type("video.avi")
    assert_equal "video/flv", Path.mime_type("video.flv")
    assert_equal "video/mkv", Path.mime_type("video.mkv")
    assert_equal "video/webm", Path.mime_type("video.webm")
    assert_equal "video/wmv", Path.mime_type("video.wmv")
    assert_equal "video/m4v", Path.mime_type("video.m4v")
    assert_equal "video/3gp", Path.mime_type("video.3gp")
  end

  def test_mime_type_comprehensive_document_types
    assert_equal "text/html", Path.mime_type("page.html")
    assert_equal "text/csv", Path.mime_type("data.csv")
    assert_equal "application/json", Path.mime_type("config.json")
    assert_equal "application/x-sh", Path.mime_type("script.py")
    assert_equal "application/epub+zip", Path.mime_type("book.epub")
    assert_equal "application/zip", Path.mime_type("archive.zip")
    assert_equal "application/x-mobipocket-ebook", Path.mime_type("book.mobi")
    assert_equal "application/pgp-encrypted", Path.mime_type("secret.gpg")
    assert_equal "text/calendar", Path.mime_type("event.ics")
    assert_equal "application/x-sqlite3", Path.mime_type("database.db")
    assert_equal "application/vnd.openxmlformats-officedocument.wordprocessingml.document", Path.mime_type("document.docx")
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", Path.mime_type("sheet.xlsx")
    assert_equal "application/x-ole-storage", Path.mime_type("project.mpp")
  end

  def test_media_type_returns_correct_type
    assert_equal :image, Path.media_type("photo.jpg")
    assert_equal :video, Path.media_type("video.mp4")
    assert_equal :audio, Path.media_type("song.mp3")
    assert_equal :file, Path.media_type("document.pdf")
  end

  def test_media_type_returns_folder_for_directories
    dir = File.join(@temp_dir, "dir_test")
    FileUtils.mkdir_p(dir)

    assert_equal :folder, Path.media_type(dir)
  end

  def test_image_returns_true_for_images
    assert Path.image?("photo.jpg")
    assert Path.image?("graphic.png")
    refute Path.image?("video.mp4")
  end

  def test_video_returns_true_for_videos
    assert Path.video?("video.mp4")
    assert Path.video?("movie.mov")
    refute Path.video?("photo.jpg")
  end

  def test_audio_returns_true_for_audio
    assert Path.audio?("song.mp3")
    assert Path.audio?("track.flac")
    refute Path.audio?("video.mp4")
  end

  def test_media_returns_true_for_media_files
    assert Path.media?("photo.jpg")
    assert Path.media?("video.mp4")
    assert Path.media?("song.mp3")
    refute Path.media?("document.pdf")
  end

  def test_comic_returns_true_for_comic_formats
    assert Path.comic?("comic.pdf")
    assert Path.comic?("comic.cbz")
    assert Path.comic?("comic.cbr")
    refute Path.comic?("photo.jpg")
  end

  def test_book_returns_true_for_book_formats
    assert Path.book?("book.pdf")
    assert Path.book?("book.epub")
    assert Path.book?("book.mobi")
    refute Path.book?("photo.jpg")
  end

  def test_join_filters_blank_strings
    result = Path.join("path", "", "to", "file")

    assert result.end_with?("path/to/file")
  end

  def test_join_does_not_filter_whitespace_only_strings
    result = Path.join("path", "   ", "to", "file")

    assert_includes result, "path"
    assert_includes result, "to"
    assert_includes result, "file"
  end

  def test_join_does_not_filter_strings_with_newlines
    result = Path.join("path", "   \n ", "to", "file")

    assert_includes result, "path"
    assert_includes result, "to"
    assert_includes result, "file"
  end

  def test_rm_handles_empty_string
    assert_raises(RuntimeError) { Path.rm("") }
  end


  def test_uniq_dirs_filters_empty_strings
    paths = [ "/path/to/file1.txt", "", "/other/file2.txt" ]
    result = Path.uniq_dirs(paths)

    assert_includes result, "/path"
    assert_includes result, "/other"
    assert_equal result.uniq.length, result.length
  end

  def test_uniq_dirs_does_not_filter_whitespace_strings
    paths = [ "/path/to/file1.txt", "   ", "/other/file2.txt" ]
    result = Path.uniq_dirs(paths)

    assert_includes result, "/path"
    assert_includes result, "/other"
  end

  def test_uniq_dirs_does_not_filter_strings_with_newlines
    paths = [ "/path/to/file1.txt", "   \n ", "/other/file2.txt" ]
    result = Path.uniq_dirs(paths)

    assert_includes result, "/path"
    assert_includes result, "/other"
  end

  def test_title_name_with_empty_string
    assert_equal "", Path.title_name("")
  end

  def test_title_name_with_whitespace_only
    result = Path.title_name("   ")

    assert_kind_of String, result
  end

  def test_extension_with_empty_string
    assert_nil Path.extension("")
  end

  def test_extension_with_nil
    assert_nil Path.extension(nil)
  end

  def test_extension_with_whitespace
    assert_nil Path.extension("   ")
  end

  private

  def create_temp_file(content)
    file = File.join(@temp_dir, "test_#{SecureRandom.hex(4)}.txt")
    File.write(file, content)
    @temp_files << file
    file
  end
end
