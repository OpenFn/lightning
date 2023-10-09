defmodule TelemetryCSVLogger do
  require Logger

  def handle_event(
        [:lightning, :workorder, :webhook, :stop] = event,
        %{duration: duration} = measurements,
        _metadata,
        output_file: file
      ) do
    log_received(event, measurements)

    IO.binwrite(file, "lightning.create_webhook_workorder.stop, #{duration}\n")
  end

  def handle_event(event, _measurements, _metadata, _config) do
    log_received(event)
  end

  defp native_to_microsecond(duration) do
    System.convert_time_unit(duration, :native, :microsecond)
  end

  defp log_received(event, %{duration: duration}) do
    duration = native_to_microsecond(duration)

    Logger.info(
      "Received #{event |> Enum.join(".")} event. Duration: #{duration}µs"
    )
  end

  defp log_received(event) do
    Logger.info("Received #{event |> Enum.join(".")} event.")
  end
end

defmodule LoadTestingPrep do
  def init(output_file) do
    telemetry_events = [
      [:lightning, :workorder, :webhook, :stop],
    ]

    :ok =
      :telemetry.attach_many(
        "lightning-load-testing-events",
        telemetry_events,
        &TelemetryCSVLogger.handle_event/4,
        output_file: output_file
      )
  end

  def fin(file) do
    File.close(file)
  end
end
