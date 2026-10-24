# frozen_string_literal: true

class GrantAiKnowledgePermissions < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:roles)

    { 'super_admin' => %w[read create update delete publish],
      'account_owner' => %w[read create update delete publish],
      'agent' => %w[read create update] }.each do |key, actions|
      role = Role.find_by(key: key)
      next unless role

      actions.each do |action|
        role.role_permissions_actions.find_or_create_by!(permission_key: "ai_knowledge.#{action}")
      end
    end
  end

  def down
    return unless table_exists?(:roles)

    Role.where(key: %w[super_admin account_owner agent]).find_each do |role|
      role.role_permissions_actions.where(permission_key: %w[read create update delete publish].map { |a| "ai_knowledge.#{a}" }).destroy_all
    end
  end
end
