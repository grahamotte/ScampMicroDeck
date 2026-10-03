require_relative "../test_helper"

class AppPatchTest < Minitest::Test
  def test_always
    commands = []
    services = []
    Cmd.stubs(:ssh).with { |command, *| commands << command; true }.returns("")
    Cmd.stubs(:ssh_write).with { |path, definition, **| services << [ path, definition ]; true }
    Req.expects(:call).with(method: :get, url: "https://example.com/api/noop/ping")

    AppPatch.always

    assert_includes commands, "cd /var/www/example.com/frontend; mise exec -- pnpm install --frozen-lockfile"
    assert_includes commands, "cd /var/www/example.com/backend; mise exec -- bundle install"
    assert_includes commands, "cd /var/www/example.com/backend; set -a; source ../.env; mise exec -- bin/rails db:migrate"
    assert_includes commands, "rm -rf ~/tmp"
    assert_includes commands, "sudo systemctl stop api.service"
    assert_includes commands, "sudo systemctl stop job.service"
    assert_includes commands, "sudo systemctl start api.service"
    assert_includes commands, "sudo systemctl start job.service"
    assert commands.any? { |command| command.include?("VITE_SUBDOMAIN=www") }
    assert commands.any? { |command| command.include?("VITE_SUBDOMAIN=hc") }
    assert services.any? { |path, definition| path.end_with?("api.service") && definition.include?("Description=Api") }
    assert services.any? { |path, definition| path.end_with?("api.service") && definition.include?("bin/rails server --binding 127.0.0.1 --port 3000") }
    assert services.any? { |path, definition| path.end_with?("job.service") && definition.include?("Description=Job Worker") }
  end

  def test_service_definitions
    assert_includes AppPatch.send(:api_service), "User=deploy"
    assert_includes AppPatch.send(:api_service), "rails server --binding 127.0.0.1 --port 3000"
    assert_includes AppPatch.send(:job_service), "GOOD_JOB_ENABLE_CRON=true"
    assert_includes AppPatch.send(:job_service), "good_job start"
  end
end
