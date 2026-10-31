require "test_helper"

class TokenTest < ActiveSupport::TestCase
  def setup
    super
    @user = User.create!(email: "user@example.com", password: "password123")
  end

  test "make returns a token for valid credentials" do
    assert_equal @user, Token.verify(Token.make("User@Example.com ", "password123"))
  end

  test "make returns nil for an unknown email" do
    assert_nil Token.make("nope@example.com", "password123")
  end

  test "make returns nil for a bad password" do
    assert_nil Token.make(@user.email, "wrongpassword")
  end

  test "make returns nil for a blank password" do
    assert_nil Token.make(@user.email, "")
  end

  test "generate_for_user encodes the user" do
    payload = JWT.decode(Token.generate_for_user(@user), ENV.fetch("JWT_SECRET")).first

    assert_equal @user.id, payload["user_id"]
    assert_equal @user.email, payload["email"]
    assert_in_delta 99.days.from_now.to_i, payload["exp"], 5
  end

  test "generate_for_user returns nil without a user" do
    assert_nil Token.generate_for_user(nil)
  end

  test "verify returns the user for a valid token" do
    assert_equal @user, Token.verify(Token.generate_for_user(@user))
  end

  test "verify returns nil for a blank token" do
    assert_nil Token.verify(nil)
    assert_nil Token.verify("")
  end

  test "verify returns nil for an invalid token" do
    assert_nil Token.verify("not.a.token")
  end

  test "verify returns nil for a token signed with another secret" do
    assert_nil Token.verify(JWT.encode({ user_id: @user.id, exp: 1.day.from_now.to_i }, "other"))
  end

  test "verify returns nil for an expired token" do
    assert_nil Token.verify(JWT.encode({ user_id: @user.id, exp: 1.second.ago.to_i }, ENV.fetch("JWT_SECRET")))
  end

  test "verify returns nil for a deleted user" do
    token = Token.generate_for_user(@user)
    @user.destroy!

    assert_nil Token.verify(token)
  end
end
