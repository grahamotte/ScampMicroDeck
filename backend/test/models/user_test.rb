require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "valid with email and password" do
    assert_predicate User.new(email: "user@example.com", password: "password123"), :valid?
  end

  test "normalizes email" do
    user = User.create!(email: "  User@Example.COM ", password: "password123")

    assert_equal "user@example.com", user.email
    assert_equal user, User.find_by(email: "USER@example.com")
  end

  test "invalid without email" do
    user = User.new(password: "password123")

    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "invalid with duplicate email" do
    User.create!(email: "dup@example.com", password: "password123")
    user = User.new(email: "DUP@example.com", password: "password456")

    assert_not user.valid?
    assert_includes user.errors[:email], "has already been taken"
  end

  test "invalid without password on create" do
    user = User.new(email: "user@example.com")

    assert_not user.valid?
    assert_includes user.errors[:password], "can't be blank"
  end

  test "invalid with short password" do
    user = User.new(email: "user@example.com", password: "short")

    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 8 characters)"
  end

  test "rejects a short password on update" do
    user = User.create!(email: "user@example.com", password: "password123")

    assert_not user.update(password: "short")
  end

  test "updates without changing the password" do
    user = User.create!(email: "user@example.com", password: "password123")

    assert user.update(email: "new@example.com")
    assert user.reload.authenticate("password123")
  end

  test "authenticate checks the password" do
    user = User.create!(email: "user@example.com", password: "password123")

    assert_equal user, user.authenticate("password123")
    assert_not user.authenticate("wrongpassword")
  end

  test "starts with token version zero" do
    assert_equal 0, User.create!(email: "user@example.com", password: "password123").token_version
  end

  test "increments token version when the password changes" do
    user = User.create!(email: "user@example.com", password: "password123")
    user.update!(password: "newpassword123")

    assert_equal 1, user.reload.token_version
  end

  test "keeps token version when other attributes change" do
    user = User.create!(email: "user@example.com", password: "password123")
    user.update!(email: "new@example.com")

    assert_equal 0, user.reload.token_version
  end

  test "revoke_tokens! increments token version" do
    user = User.create!(email: "user@example.com", password: "password123")
    user.revoke_tokens!
    user.revoke_tokens!

    assert_equal 2, user.reload.token_version
  end
end
