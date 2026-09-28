require_relative "test_helper"

class AgentTest < Minitest::Test
  def test_posts_session_to_openchamber
    payload = nil
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      payload = opts
      true
    end.returns({ sessionId: "ses-1" })

    Agent.start("do the work")

    assert_equal "http://127.0.0.1:57123/api/openchamber/sessions", payload.fetch(:url)
    assert_equal :post, payload.fetch(:method)
    assert_equal Agent::ROOT, payload.dig(:payload, :directory)
    assert_equal "do the work", payload.dig(:payload, :prompt)
    assert_equal "xai/grok-4.6", payload.dig(:payload, :model)
    assert_equal "high", payload.dig(:payload, :variant)
  end

  def test_posts_session_to_given_directory
    payload = nil
    Req.stubs(:call).with do |*args, **kwargs|
      payload = req_opts(args, kwargs)
      true
    end.returns({ sessionId: "ses-1" })

    Agent.start("do the work", directory: "/tmp/card")

    assert_equal "/tmp/card", payload.dig(:payload, :directory)
  end

  def test_overrides_model_and_variant
    payload = nil
    Req.stubs(:call).with do |*args, **kwargs|
      payload = req_opts(args, kwargs)
      true
    end.returns({ sessionId: "ses-1" })

    Agent.start("do the work", model: "anthropic/claude-sonnet-4", variant: "medium")

    assert_equal "anthropic/claude-sonnet-4", payload.dig(:payload, :model)
    assert_equal "medium", payload.dig(:payload, :variant)
  end

  def test_falls_back_to_settings_when_overrides_blank
    payload = nil
    Req.stubs(:call).with do |*args, **kwargs|
      payload = req_opts(args, kwargs)
      true
    end.returns({ sessionId: "ses-1" })

    Agent.start("do the work", model: "", variant: "  ")

    assert_equal "xai/grok-4.6", payload.dig(:payload, :model)
    assert_equal "high", payload.dig(:payload, :variant)
  end

  def test_omits_variant_when_blank
    Settings.all[:agent][:variant] = ""
    payload = nil
    Req.stubs(:call).with do |*args, **kwargs|
      payload = req_opts(args, kwargs)
      true
    end.returns({ sessionId: "ses-1" })

    Agent.start("do the work")

    refute payload.fetch(:payload).key?(:variant)
  end

  def test_rejects_unknown_runner
    Settings.all[:agent][:runner] = "nope"

    error = assert_raises(RuntimeError) { Agent.start("do the work") }

    assert_equal "Unknown agent runner nope", error.message
  end
end
