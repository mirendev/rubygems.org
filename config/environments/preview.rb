# frozen_string_literal: true

# Production-like rendering without production infrastructure or development logins.
require_relative "production"

Rails.application.configure do
  config.assume_ssl = true
  config.cache_store = :memory_store
  config.action_mailer.perform_deliveries = false
  config.good_job.execution_mode = :inline

  # Inline jobs must see the completed push, not a half-written version.
  ActiveSupport.on_load(:active_job) do
    self.enqueue_after_transaction_commit = true
  end

  require_relative "../../lib/gemcutter/middleware/hostess"
  config.middleware.use Gemcutter::Middleware::Hostess
end
