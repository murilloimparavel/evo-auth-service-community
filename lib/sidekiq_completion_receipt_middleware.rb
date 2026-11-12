# frozen_string_literal: true

require "digest"
require "json"

# Persists a PostgreSQL receipt after a job returns successfully. If a copied
# job is replayed after completion, the receipt lets the worker acknowledge it
# without repeating the job's side effects.
class SidekiqCompletionReceiptMiddleware
  def call(_worker, job, queue)
    jid = job.fetch("jid")
    payload_sha256 = Digest::SHA256.hexdigest(JSON.generate(job["args"] || []))
    result = nil

    # A transaction-scoped advisory lock serializes the same JID even when a
    # migration briefly leaves copies in both Redis databases. It also makes
    # the successful job and its receipt visible atomically to other workers.
    SidekiqJobReceipt.transaction do
      connection = SidekiqJobReceipt.connection
      quoted_jid = connection.quote(jid)
      connection.select_value("SELECT pg_advisory_xact_lock(hashtextextended(#{quoted_jid}, 0))")

      receipt = SidekiqJobReceipt.find_by(jid: jid)
      if receipt
        unless receipt.payload_sha256 == payload_sha256
          raise "Completed Sidekiq JID #{jid} was replayed with a different payload"
        end
      else
        result = yield
        SidekiqJobReceipt.create!(
          jid: jid,
          job_class: job["wrapped"] || job.fetch("class"),
          queue: queue.to_s,
          payload_sha256: payload_sha256,
          completed_at: Time.current
        )
      end
    end

    result
  end
end
