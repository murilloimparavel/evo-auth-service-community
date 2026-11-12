# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidekiqCompletionReceiptMiddleware do
  subject(:middleware) { described_class.new }

  let(:job) do
    {
      "jid" => "receipt-test-jid",
      "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
      "wrapped" => "Licensing::HeartbeatJob",
      "args" => [{ "job_class" => "Licensing::HeartbeatJob", "arguments" => [] }]
    }
  end

  before { SidekiqJobReceipt.where(jid: job.fetch("jid")).delete_all }

  it "writes a durable receipt only after perform returns successfully" do
    expect { middleware.call(nil, job, "licensing") { :performed } }
      .to change { SidekiqJobReceipt.where(jid: job.fetch("jid")).count }.from(0).to(1)

    receipt = SidekiqJobReceipt.find_by!(jid: job.fetch("jid"))
    expect(receipt.job_class).to eq("Licensing::HeartbeatJob")
    expect(receipt.queue).to eq("licensing")
    expect(receipt.payload_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(receipt.completed_at).to be_present
  end

  it "does not write a receipt when perform raises" do
    expect do
      middleware.call(nil, job, "licensing") { raise "simulated failure" }
    end.to raise_error("simulated failure")

    expect(SidekiqJobReceipt.exists?(jid: job.fetch("jid"))).to be(false)
  end

  it "acknowledges a duplicate JID without running it again" do
    middleware.call(nil, job, "licensing") { :first_run }

    expect do
      middleware.call(nil, job, "licensing") { raise "duplicate must not run" }
    end.not_to raise_error
    expect(SidekiqJobReceipt.where(jid: job.fetch("jid")).count).to eq(1)
  end

  it "rejects a reused JID when its class or queue changes" do
    middleware.call(nil, job, "licensing") { :first_run }

    expect do
      middleware.call(nil, job.merge("wrapped" => "Licensing::SetupJob"), "licensing") { :wrong_class }
    end.to raise_error(/different payload/)

    expect do
      middleware.call(nil, job, "default") { :wrong_queue }
    end.to raise_error(/different payload/)
  end
end
