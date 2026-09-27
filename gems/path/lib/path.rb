# frozen_string_literal: true

class Path
  class << self
    def dir?(x)
      return true if x.end_with?("/")

      File.directory?(x)
    end

    def file?(x)
      return false if x.end_with?("/")

      File.file?(x)
    end

    def exists?(x)
      File.exist?(x)
    end

    def exist?(x)
      exists?(x)
    end

    def does_not_exist?(x)
      !exists?(x)
    end

    def empty_dir?(x)
      Dir.empty?(x)
    end

    def mkdir(x)
      return if exists?(x) && dir?(x)

      FileUtils.mkdir_p(x)
    end

    def mtime(x)
      File.mtime(x)
    end

    def size(x)
      File.size(x)
    end

    def md5(x)
      Digest::MD5.file(x).hexdigest
    end

    def quick_hash(x)
      [
        x.to_s,
        size(x).to_s,
        mtime(x).iso8601,
      ].join("|").then { |x| Digest::SHA256.hexdigest(x) }
    end

    def extension(x)
      return nil if blank?(x)

      x = extract_path_from_url(x) if url?(x)
      ext = File.extname(x).downcase.gsub(".", "")
      ext.empty? ? nil : ext.to_sym
    end

    def ext(x)
      extension(x)
    end

    def title_name(x)
      filter_present(basename(x).rpartition(".")).first.to_s
    end

    def title(x)
      title_name(x)
    end

    def basename(x)
      File.basename(x)
    end

    def file_name(x)
      filename(x)
    end

    def filename(x)
      basename(x)
    end

    def dirname(x)
      File.dirname(x)
    end

    def dir(x)
      dirname(x)
    end

    def folder(x)
      dirname(x)
    end

    def depth(x)
      x.count("/")
    end

    def join(x, *fs)
      [ x, fs ]
        .flatten
        .select { |item| present?(item) }
        .map(&:to_s)
        .then { |xs| present?(xs) && [ "/", "~" ].include?(xs.first[0]) ? xs : [ "/" ] + xs }
        .then { |xs| File.join(xs) }
        .then { |y| File.expand_path(y) }
    end

    def slash_compact(x)
      result = x.to_s
      loop do
        before = result
        result = result.gsub("//", "/")
        break if result == before
      end
      result
        .gsub("http:/", "http://")
        .gsub("https:/", "https://")
    end

    def slash(x, front: true, back: true)
      x = x.to_s
      x = x.start_with?("/") ? x : "/#{x}" if front
      x = x.to_s
      x = x.end_with?("/") ? x[..-2] : x if back
      x = x.to_s
      slash_compact(x)
    end

    def unslash(x, front: true, back: true)
      x = x.to_s
      x = x.start_with?("/") ? x[1..] : x if front
      x = x.to_s
      x = x.end_with?("/") ? x[..-2] : x if back
      x = x.to_s
      slash_compact(x)
    end

    def ls(dir)
      Dir.glob(join(dir, "*"))
    end

    def list(dir)
      Dir.glob(join(dir, "**/*"))
    end

    def list_files(dir)
      list(dir).select { |x| file?(x) }
    end

    def list_dirs(dir)
      list(dir).select { |x| dir?(x) }
    end

    def touch(x)
      FileUtils.touch(x)
    end

    def write(data, x, check_dir: true)
      mkdir(dirname(x))
      File.write(x, data)
    end

    def binwrite(data, x, check_dir: true)
      mkdir(dirname(x))
      File.binwrite(x, data)
    end

    def chmod(x, mode)
      File.chmod(mode, x)
    end

    def read(x)
      File.read(x)
    end

    def binread(x)
      File.binread(x)
    end

    def read64(x)
      Base64.strict_encode64(binread(x))
    end

    def read_json(x)
      JSON.parse(File.read(x), symbolize_names: true)
    end

    def mv(a, b, overwrite: false)
      return if a == b

      prepare_destination!(b, overwrite:)
      mkdir(dirname(b))
      FileUtils.mv(a, b)
    end

    def cp(a, b, overwrite: false)
      return if a == b

      prepare_destination!(b, overwrite:)
      mkdir(dirname(b))
      FileUtils.cp(a, b)
    end

    def rm(x)
      raise "can't rm home dir #{x}" if slash(x) == ENV.fetch("HOME") || x == ENV.fetch("HOME")
      raise "can't rm root dir #{x}" if slash(x) == "/" || x == "/"
      raise "cant rm blank #{x}" if blank?(x)

      FileUtils.rm_rf(x)
    end

    def with_tmp_dir(d = join("~/tmp", SecureRandom.hex(8)))
      raise "#{d} is not a dir" if exists?(d) && !dir?(d)
      raise "#{d} exists and is not empty" if exists?(d) && dir?(d) && !empty_dir?(d)

      mkdir(d)
      yield(d)
    ensure
      rm(d)
    end

    def uniq_dirs(dirs)
      compact_blank(array_wrap(dirs).flatten)
        .map { |x| filter_present(dirname(x).split("/")) }
        .map { |x| x.map.with_index { |_, i| join("/", x[0..i]) } }
        .flatten
        .uniq
    end

    def mime_type(x)
      return "inode/directory" if dir?(x)

      case extension(x)

      when :gif then "image/gif"
      when :heic then "image/heic"
      when :heif then "image/heif"
      when :jpg, :jpeg then "image/jpeg"
      when :png then "image/png"
      when :tif, :tiff then "image/tiff"
      when :webp then "image/webp"
      when :avif then "image/avif"

      when :avi then "video/avi"
      when :flv then "video/flv"
      when :mkv then "video/mkv"
      when :mov then "video/quicktime"
      when :mp4 then "video/mp4"
      when :mpeg then "video/mpeg"
      when :mpg then "video/mpg"
      when :webm then "video/webm"
      when :wmv then "video/wmv"
      when :m4v then "video/m4v"
      when :"3gp" then "video/3gp"

      when :mp3 then "audio/mpeg"
      when :flac then "audio/flac"
      when :m4a then "audio/mp4"
      when :qta then "audio/quicktime"

      when :txt, :text then "text/plain"
      when :html, :htm then "text/html"
      when :csv then "text/csv"
      when :json then "application/json"
      when :py then "application/x-sh"

      when :pdf then "application/pdf"
      when :epub then "application/epub+zip"
      when :cbz then "application/zip"
      when :cbr then "application/x-rar-compressed"
      when :mobi then "application/x-mobipocket-ebook"
      when :gpg then "application/pgp-encrypted"
      when :opf then "application/xml"
      when :zip then "application/zip"
      when :swf then "application/vnd.adobe.flash.movie"
      when :numbers then "application/zip"
      when :ics then "text/calendar"
      when :db then "application/x-sqlite3"
      when :docx then "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      when :xlsx then "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      when :nes then "application/x-nesrom"
      when :mpp then "application/x-ole-storage"

      else
        "application/octet-stream"
      end
    end

    def media_type(x)
      case mime_type(x)
      when "inode/directory" then :folder
      when %r{image/} then :image
      when %r{video/} then :video
      when %r{audio/} then :audio
      else
        :file
      end
    end

    def image?(x)
      media_type(x) == :image
    end

    def video?(x)
      media_type(x) == :video
    end

    def audio?(x)
      media_type(x) == :audio
    end

    def media?(x)
      image?(x) || video?(x) || audio?(x)
    end

    def comic?(x)
      [ :pdf, :cbz, :cbr ].include?(ext(x))
    end

    def book?(x)
      [ :pdf, :epub, :mobi ].include?(ext(x))
    end

    private

    def prepare_destination!(b, overwrite:)
      return unless exists?(b)
      raise "#{b} already exists" if dir?(b) || !overwrite
    end

    def url?(x)
      x_str = x.to_s
      x_str.start_with?("http://") || x_str.start_with?("https://")
    end

    def extract_path_from_url(url)
      require "uri"
      parsed = URI.parse(url.to_s)
      parsed.path || url.to_s
    rescue URI::InvalidURIError, ArgumentError
      url.to_s
    end

    def blank?(obj)
      return true if obj.nil?
      return obj.empty? if obj.respond_to?(:empty?)

      false
    end

    def present?(obj)
      !blank?(obj)
    end

    def array_wrap(obj)
      if obj.nil?
        []
      elsif obj.respond_to?(:to_ary)
        obj.to_ary || [ obj ]
      else
        [ obj ]
      end
    end

    def compact_blank(array)
      array.reject { |item| blank?(item) }
    end

    def filter_present(array)
      array.select { |item| present?(item) }
    end
  end
end
