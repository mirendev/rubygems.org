# frozen_string_literal: true

return if Rails.env.local? || Rails.env.preview? # Don't report from development, test, or previews

Rails.logger.silence(:error) do
  require "honeybadger"

  Honeybadger.configure do |config|
    config.before_notify do |notice|
      notice.halt! if ActionDispatch::ExceptionWrapper.rescue_responses.key?(notice.error_class)
    end

    config.logger = SemanticLogger[Honeybadger]

    config.insights.enabled = false
  end
end
