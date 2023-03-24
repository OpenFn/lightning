defmodule Lightning.Telemetry.Metrics do
  require Logger

  def handle_event(
        [:lightning, :create_dataclip, :start],
        _measurements,
        _metadata,
        _config
      ) do
    Logger.info("Received [:lightning, :create_dataclip, :start] event.")
  end

  def handle_event(
        [:lightning, :create_dataclip, :stop],
        %{duration: duration} = _measurements,
        _metadata,
        _config
      ) do
    Logger.info(
      "Received [:lightning, :create_dataclip, :stop] event. Duration: #{duration}"
    )
  end

  def handle_event(
        [:lightning, :create_dataclip, :exception],
        _measurements,
        _metadata,
        _config
      ) do
    Logger.info("Received [:lightning, :create_dataclip, :exception] event.")
  end

  def handle_event(
        [:lightning, :create_webhook_workorder, :start],
        _measurements,
        _metadata,
        _config
      ) do
    Logger.info(
      "Received [:lightning, :create_webhook_workorder, :start] event."
    )
  end

  def handle_event(
        [:lightning, :create_webhook_workorder, :stop],
        %{duration: duration} = _measurements,
        _metadata,
        _config
      ) do
    Logger.info(
      "Received [:lightning, :create_webhook_workorder, :stop] event. Duration: #{duration}"
    )
  end

  def handle_event(
        [:lightning, :create_webhook_workorder, :exception],
        _measurements,
        _metadata,
        _config
      ) do
    Logger.info(
      "Received [:lightning, :create_webhook_workorder, :exception] event."
    )
  end
end
