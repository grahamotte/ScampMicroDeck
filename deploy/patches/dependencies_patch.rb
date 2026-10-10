class DependenciesPatch < BasePatch
  class << self
    def always
      Instance.install_package("ffmpeg")
      Instance.install_package("imagemagick", bin: "convert")
      Instance.install_package("unzip")
      Cmd.ssh("set -o pipefail && d=$(mktemp -d) && trap 'rm -rf \"$d\"' EXIT && cd \"$d\" && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip -o awscliv2.zip && unzip -q awscliv2.zip && sudo ./aws/install --update")

      unless Instance.installed?("mise")
        Cmd.ssh("sudo apt update -y && sudo apt install -y gpg sudo wget curl")
        Cmd.ssh("sudo install -dm 755 /etc/apt/keyrings")
        Cmd.ssh("wget -qO - https://mise.jdx.dev/gpg-key.pub | gpg --dearmor | sudo tee /etc/apt/keyrings/mise-archive-keyring.gpg 1> /dev/null")
        Cmd.ssh("echo 'deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=amd64] https://mise.jdx.dev/deb stable main' | sudo tee /etc/apt/sources.list.d/mise.list")
        Cmd.ssh("sudo apt update")
        Cmd.ssh("sudo apt install -y mise")
      end

      Cmd.ssh("mise settings add idiomatic_version_file_enable_tools \"[]\"")
      Cmd.ssh("mise settings set ruby.compile=false")
      Cmd.ssh("set -o pipefail && curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path && sudo ln -sf ~/.opencode/bin/opencode /usr/local/bin/opencode")
    end

    def needed?
      tool_versions.each do |package, version|
        return true if version_not_installed?(package, version)
      end

      false
    end

    def apply
      Cmd.ssh("cd #{Constants.remote_root} && mise -y trust -a")
      Cmd.ssh("sudo apt-get install -y autoconf bison build-essential gcc libffi-dev libgdbm-dev libjemalloc-dev libncurses5-dev libreadline-dev libssl-dev libyaml-dev make zlib1g-dev")
      Cmd.ssh("mkdir -p ~/tmp")
      Cmd.ssh([
        "cd ?",
        "export TMPDIR=~/tmp",
        "export RUBY_CONFIGURE_OPTS='--with-jemalloc'",
        "mise install --yes",
      ].join(" && "), Constants.remote_root)
    end

    private

    def version_installed?(package, version)
      current_versions[package.to_sym]
        .find { |ver| ver[:version] == version && ver[:installed] }
        .present?
    rescue StandardError => e
      puts e.message
      false
    end

    def version_not_installed?(package, version)
      !version_installed?(package, version)
    end

    def current_versions
      @current_versions ||= begin
        JSON.parse(Cmd.ssh("mise list --json"), symbolize_names: true)
      rescue StandardError => e
        puts e.message
        {}
      end
    end

    def tool_versions
      File
        .join(Constants.local_root, "mise.toml")
        .then { |x| File.readlines(x) }
        .drop_while { |line| line.strip != "[tools]" }
        .drop(1)
        .take_while { |line| !line.start_with?("[") }
        .filter_map { |line| line.match(/\A([^\s=]+)\s*=\s*"([^"]+)"/)&.captures }
        .to_h
    end
  end
end
