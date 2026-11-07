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
class User < ApplicationRecord
  has_secure_password
  has_secure_password :api_token, validations: false, reset_token: false

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true

  before_update :revoke_sign_ins, if: :will_save_change_to_password_digest?

  def self.find_by_api_token(token)
    return if api_token?(token).blank?

    id, secret = token.delete_prefix("#{Settings.api_token_prefix}_").split("_", 2)
    return if id.blank? || secret.blank?

    find_by(id:)&.authenticate_api_token(secret).presence
  end

  def self.api_token?(token)
    token.to_s.start_with?("#{Settings.api_token_prefix}_")
  end

  def revoke_tokens!
    increment!(:token_version)
    revoke_api_token!
  end

  def generate_api_token!
    secret = SecureRandom.base58(40)
    update!(api_token: secret)
    [ Settings.api_token_prefix, id, secret ].join("_")
  end

  def revoke_api_token!
    update!(api_token_digest: nil)
  end

  def api_token? = api_token_digest.present?

  private

  def revoke_sign_ins
    self.token_version += 1
    self.api_token_digest = nil
  end
end
