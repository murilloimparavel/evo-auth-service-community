# frozen_string_literal: true

require Rails.root.join("lib/sidekiq_completion_receipt_middleware")

if defined?(Sidekiq)
  Sidekiq.configure_server do |config|
    config.server_middleware do |chain|
      chain.add SidekiqCompletionReceiptMiddleware
    end
  end
end
