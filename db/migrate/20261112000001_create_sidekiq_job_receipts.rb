# frozen_string_literal: true

class CreateSidekiqJobReceipts < ActiveRecord::Migration[7.1]
  def change
    create_table :sidekiq_job_receipts, id: :uuid do |t|
      t.string :jid, null: false
      t.string :job_class, null: false
      t.string :queue, null: false
      t.string :payload_sha256, null: false, limit: 64
      t.datetime :completed_at, null: false, precision: 6
      t.timestamps precision: 6
    end

    add_index :sidekiq_job_receipts, :jid, unique: true
    add_index :sidekiq_job_receipts, :completed_at
  end
end
