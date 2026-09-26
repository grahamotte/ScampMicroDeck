# frozen_string_literal: true

class Cache
  class << self
    def set(key, value)
      $cache ||= new
      $cache.set(key, value)
    end

    def get(key)
      $cache ||= new
      $cache.get(key)
    end

    def changed?(key, value)
      $cache ||= new
      $cache.changed?(key, value)
    end

    def unchanged?(key, value)
      $cache ||= new
      $cache.unchanged?(key, value)
    end

    def if_files_changed(*paths, &block)
      $cache ||= new
      $cache.if_files_changed(*paths, &block)
    end

    def clear
      $cache ||= new
      $cache.clear
    end

    def default_root_dir
      if defined?($root_dir) && $root_dir
        $root_dir
      else
        File.expand_path(File.dirname($PROGRAM_NAME))
      end
    end
  end

  attr_accessor :groups, :dir

  def initialize(dir: File.join(self.class.default_root_dir, "tmp/cache"))
    @groups = {}
    @dir = dir
    FileUtils.mkdir_p(@dir)
    Dir.glob(File.join(@dir, "*.json")).each do |path|
      @groups[File.basename(path)] = JSON.parse(File.read(path))
    end
  end

  def set(key, value)
    gk = group_key(key)
    @groups[gk] ||= {}
    @groups[gk][key.to_s] = value.to_s
    File.write(group_file_path(gk), JSON.pretty_generate(@groups[gk]))
  end

  def get(key)
    gk = group_key(key)
    @groups[gk] ||= {}
    @groups[gk][key.to_s] || nil
  end

  def clear
    @groups = {}
    Dir.glob(File.join(@dir, "*.json")).each do |path|
      FileUtils.rm(path)
    end
  end

  def changed?(key, value)
    return false if blank?(value)

    get(key) != value
  end

  def unchanged?(key, value)
    !changed?(key, value)
  end

  def if_files_changed(*paths)
    comb_path = [ paths ].flatten.compact.join("|")
    comb_content = Digest::SHA256.hexdigest([ paths ].flatten.compact.map { |path| File.binread(path) }.join("|"))
    if changed?(comb_path, comb_content)
      yield
      set(comb_path, comb_content)
    else
      puts "CAH skip #{comb_path.split('|').first} because content hasn't changed" unless ENV['test']
    end
  end

  private

  def group_key(key)
    "#{Digest::SHA256.hexdigest(key.to_s)[0..1]}.json"
  end

  def group_file_path(group_key)
    File.join(@dir, group_key)
  end

  def blank?(obj)
    return true if obj.nil?
    return obj.empty? if obj.respond_to?(:empty?)

    false
  end
end
