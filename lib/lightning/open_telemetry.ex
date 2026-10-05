defmodule Lightning.OpenTelemetry do
  @moduledoc """
  Attaches OpenTelemetry's `:telemetry` handlers.

  Gated separately from the SDK's own `sdk_disabled`: these handlers are
  attached process-wide and cannot be detached per-request, and they build
  their full attribute set before consulting the sampler, so a disabled SDK
  makes them cheap but not free. See the comment at
  `deps/opentelemetry_ecto/lib/opentelemetry_ecto.ex:60`.
  """

  def setup do
    if Lightning.Config.otel_enabled?() do
      :opentelemetry_cowboy.setup()
      OpentelemetryPhoenix.setup(adapter: :cowboy2, liveview: false)
      OpentelemetryOban.setup()

      if Lightning.Config.otel_ecto_enabled?() do
        OpentelemetryEcto.setup([:lightning, :repo])
      end
    end

    :ok
  end
end
