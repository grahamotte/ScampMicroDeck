require "test_helper"

class XTest < ActiveSupport::TestCase
  def test_environment
    refute X.prod?
    refute X.dev?
    assert X.test?
    assert_equal "https://#{Settings.all.fetch(:domain)}", X.host
  end

  def test_wait_and_timeout
    assert_nil X.wait(0, 0)
    assert_equal "done", X.timeout { "done" }
  end

  def test_tryn
    attempts = []
    result = X.tryn(2, sleep: 0.5) do |remaining|
      attempts << remaining
      raise "retry" if remaining.positive?

      "done"
    end

    assert_equal "done", result
    assert_equal [ 1, 0 ], attempts
    assert_raises(RuntimeError) { X.tryn(1) { raise "failure" } }
  end

  def test_recursive_deep_symbolize_keys
    assert_equal({ a: [ { b: 1 } ] }, X.recursive_deep_symbolize_keys("a" => [ { "b" => 1 } ]))
    assert_equal 1, X.recursive_deep_symbolize_keys(1)
  end

  def test_recursive_open_struct
    result = X.recursive_open_struct("a" => [ { "b" => 1 } ])

    assert_equal 1, result.a.first.b
    assert_equal 1, X.recursive_open_struct(1)
  end
end
