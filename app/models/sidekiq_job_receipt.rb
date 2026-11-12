# frozen_string_literal: true

# Durable evidence that Sidekiq returned successfully from a job's perform
# method. Receipts live in PostgreSQL so they survive a Redis database cutover.
class SidekiqJobReceipt < ApplicationRecord
  self.table_name = "sidekiq_job_receipts"

  validates :jid, presence: true, uniqueness: true
  validates :job_class, :queue, :payload_sha256, :completed_at, presence: true
end
