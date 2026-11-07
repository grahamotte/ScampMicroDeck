require_relative "../test_helper"

class InstanceTest < Minitest::Test
  def test_image_id
    Req.expects(:call).returns(images: [
      { slug: "ubuntu-24-04-x64", id: 1 },
      { slug: "ubuntu-26-04-arm64", id: 2 },
      { slug: "ubuntu-25-10-x64", id: 3 },
      { slug: "ubuntu-26-04-x64", id: 4 },
      { slug: "ubuntu-27-04-x64", id: 5 },
    ])

    assert_equal 4, Instance.image_id
  end

  def test_ssh_key_id
    Req.expects(:call).with(has_entry(:url, "https://api.digitalocean.com/v2/account/keys"))
      .returns(ssh_keys: [ { fingerprint: "fingerprint", id: 4 } ])
    assert_equal 4, Instance.ssh_key_id

    Instance.clear
    Req.expects(:call).with(has_entries(method: :get, url: "https://api.digitalocean.com/v2/account/keys"))
      .returns(ssh_keys: [])
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.digitalocean.com/v2/account/keys"))
      .returns(ssh_key: { id: 5 })
    assert_equal 5, Instance.ssh_key_id
  end

  def test_show_ip_and_running_state
    Req.expects(:call).returns(droplets: [
      { name: "other.com" },
      {
        name: "example.com",
        id: 6,
        status: "active",
        networks: { v4: [ { type: "private", ip_address: "10.0.0.1" }, { type: "public", ip_address: "1.2.3.4" } ] },
      },
    ])

    assert_equal 6, Instance.instance_id
    assert_equal "1.2.3.4", Instance.ip
    assert Instance.running?
  end

  def test_create
    Req.expects(:call).with(has_entry(:url, "https://api.digitalocean.com/v2/images"))
      .returns(images: [ { slug: "ubuntu-26-04-x64", id: 1 } ])
    Req.expects(:call).with(has_entry(:url, "https://api.digitalocean.com/v2/account/keys"))
      .returns(ssh_keys: [ { fingerprint: "fingerprint", id: 2 } ])
    Req.expects(:call).with do |options|
      options[:method] == :post && options[:url].end_with?("/droplets") && options[:payload] == {
        name: "example.com",
        region: "test-region",
        image: 1,
        size: "test-size",
        ssh_keys: [ 2 ],
      }
    end.returns(id: 3)

    assert_equal({ id: 3 }, Instance.create)
  end

  def test_destroy
    Req.expects(:call).returns(droplets: [ { name: "example.com", id: 6 } ])
    Req.expects(:call).with do |options|
      options[:method] == :delete && options[:url].end_with?("/droplets/6")
    end

    Instance.destroy
  end

  def test_destroy_without_instance
    Req.expects(:call).returns(droplets: [])

    assert_raises(RuntimeError) { Instance.destroy }
  end

  def test_service_state_and_stop
    Cmd.expects(:ssh).returns("LoadState=loaded\nActiveState=active\nFreezerState=running\n")
    assert Instance.service_running?("api")

    Cmd.expects(:ssh).returns("LoadState=loaded\nActiveState=inactive\nFreezerState=dead\n")
    refute Instance.service_running?("api")

    Cmd.expects(:ssh).raises("failure")
    assert_nil Instance.stop_service("api")
  end

  def test_start_service
    Cmd.expects(:ssh).with("sudo systemctl daemon-reload")
    Cmd.expects(:ssh).with("sudo systemctl start api.service")
    Cmd.expects(:ssh).with("sudo systemctl enable api.service")
    Cmd.expects(:ssh).with("systemctl show --no-page --property=LoadState,ActiveState,FreezerState api.service")
      .returns("LoadState=loaded\nActiveState=active\nFreezerState=running\n")

    Instance.start_service("api")
  end

  def test_start_service_failure
    Cmd.stubs(:ssh).returns("")

    assert_raises(RuntimeError) { Instance.start_service("api") }
  end

  def test_write_service
    Cmd.expects(:ssh_write).with("/etc/systemd/system/api.service", "definition", sudo: true)
    Cmd.expects(:ssh).with("sudo systemctl daemon-reload")
    Cmd.expects(:ssh).with("sudo systemctl enable api.service")

    Instance.write_service("api", "definition")
    assert_nil Instance.write_service("api", "definition")
  end

  def test_restart_service
    Cmd.expects(:ssh).with("sudo systemctl stop api.service")
    Cmd.expects(:ssh).with("sudo systemctl daemon-reload")
    Cmd.expects(:ssh).with("sudo systemctl start api.service")
    Cmd.expects(:ssh).with("sudo systemctl enable api.service")
    Cmd.expects(:ssh).with("systemctl show --no-page --property=LoadState,ActiveState,FreezerState api.service")
      .returns("LoadState=loaded\nActiveState=active\nFreezerState=running\n")

    Instance.restart_service("api")
  end

  def test_app_command
    assert_equal(
      { "MISE_DATA_DIR" => "/home/deploy/.local/share/mise", "MISE_TRUSTED_CONFIG_PATHS" => "/var/www/example.com" },
      Instance.app_environment,
    )
    assert_equal(
      "sudo -u app -H env MISE_DATA_DIR=/home/deploy/.local/share/mise MISE_TRUSTED_CONFIG_PATHS=/var/www/example.com bash -c cd\\ /tmp\\ \\&\\&\\ echo\\ \\'hi\\'",
      Instance.app_command("cd /tmp && echo 'hi'"),
    )
  end

  def test_packages
    Cmd.expects(:ssh).with("which ffmpeg").returns("/usr/bin/ffmpeg")
    assert Instance.installed?("ffmpeg")

    Cmd.expects(:ssh).with("which missing").raises("missing")
    refute Instance.installed?("missing")

    Cmd.expects(:ssh).with("which convert").returns("")
    Cmd.expects(:ssh).with("sudo apt-get install -y imagemagick")
    Instance.install_package("imagemagick", bin: "convert")

    Cmd.expects(:ssh).with("which ffmpeg").returns("/usr/bin/ffmpeg")
    assert_nil Instance.install_package("ffmpeg")
  end
end
