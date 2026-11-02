require_relative "../test_helper"

class DeployUserPatchTest < Minitest::Test
  def test_needed
    Cmd.expects(:ssh).returns("ok")
    refute DeployUserPatch.needed?

    Cmd.expects(:ssh).raises("failure")
    assert DeployUserPatch.needed?
  end

  def test_apply
    Cmd.stubs(:ssh)
    Cmd.stubs(:ssh_write)
    Cmd.expects(:ssh).with("useradd deploy -m", user: "root")
    Cmd.expects(:ssh).with("chpasswd", user: "root", stdin: "deploy:password\n")
    Cmd.expects(:ssh_write).with("/home/deploy/.ssh/id_rsa", "private-key", user: "root")
    Cmd.expects(:ssh_write).with("/home/deploy/.ssh/id_rsa.pub", "public-key", user: "root")
    Cmd.expects(:ssh_write).with("/etc/ssh/sshd_config", includes("PermitRootLogin no"), user: "root")
    Cmd.expects(:ssh).with("systemctl restart ssh", user: "root")

    DeployUserPatch.apply
  end
end
