require "test_helper"

# == Schema Information
#
# Table name: users
#
#  id               :uuid             not null, primary key
#  api_token_digest :string
#  email            :string           not null
#  password_digest  :string           not null
#  token_version    :integer          default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_users_on_email  (email) UNIQUE
#
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

  test "generate_api_token! stores only a digest" do
    user = User.create!(email: "user@example.com", password: "password123")

    token = user.generate_api_token!

    assert_match(/\A#{Settings.api_token_prefix}_#{user.id}_[1-9A-HJ-NP-Za-km-z]{40}\z/, token)
    assert user.reload.api_token?
    assert_not_includes user.api_token_digest, token.split("_").last
    assert_equal user, User.find_by_api_token(token)
  end

  test "generating a new API token replaces the old one" do
    user = User.create!(email: "user@example.com", password: "password123")
    old = user.generate_api_token!
    new = user.generate_api_token!

    assert_nil User.find_by_api_token(old)
    assert_equal user, User.find_by_api_token(new)
  end

  test "generating an API token keeps token version" do
    user = User.create!(email: "user@example.com", password: "password123")
    user.generate_api_token!

    assert_equal 0, user.reload.token_version
  end

  test "revoke_api_token! removes the API token" do
    user = User.create!(email: "user@example.com", password: "password123")
    token = user.generate_api_token!

    user.revoke_api_token!

    assert_not user.reload.api_token?
    assert_nil User.find_by_api_token(token)
  end

  test "find_by_api_token rejects bad tokens" do
    prefix = Settings.api_token_prefix
    user = User.create!(email: "user@example.com", password: "password123")
    secret = user.generate_api_token!.split("_").last
    other = User.create!(email: "other@example.com", password: "password123")

    [ nil, "", "#{prefix}_", "#{prefix}_#{user.id}_", "#{prefix}_#{user.id}_wrong", "xx_#{user.id}_#{secret}", "#{prefix}_#{other.id}_#{secret}", "#{prefix}_not-a-uuid_#{secret}" ].each do |token|
      assert_nil User.find_by_api_token(token), token.inspect
    end
  end

  test "find_by_api_token accepts a prefix with underscores" do
    Settings.instance_variable_set(:@all, Settings.all.merge(apiTokenPrefix: "my_app"))
    user = User.create!(email: "user@example.com", password: "password123")
    token = user.generate_api_token!

    assert token.start_with?("my_app_#{user.id}_")
    assert_equal user, User.find_by_api_token(token)
  ensure
    Settings.instance_variable_set(:@all, nil)
  end

  test "api_token? checks the prefix" do
    assert User.api_token?("#{Settings.api_token_prefix}_x_y")
    assert_not User.api_token?("eyJhbGciOi")
    assert_not User.api_token?(nil)
  end
end
