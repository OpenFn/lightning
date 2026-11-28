defmodule Lightning.OpenTelemetry do
  @moduledoc """
  Attaches OpenTelemetry's `:telemetry` handlers.

  Gated separately from the SDK's own `sdk_disabled`: these handlers are
  attached process-wide and cannot be detached per-request, and they build
  their full attribute set before consulting the sampler, so a disabled SDK
  makes them cheap but not free.
  """

  @cowboy_config %{public_endpoint: true}

  def setup do
    if Lightning.Config.otel_enabled?() do
      :opentelemetry_cowboy.setup(cowboy_config())

      OpentelemetryPhoenix.setup(adapter: :cowboy2, liveview: false)

      # Oban.Stager events can be quite noisy, so disable until we have
      # an idea of ROI.
      OpentelemetryOban.setup(plugin: :disabled)

      if Lightning.Config.otel_ecto_enabled?() do
        OpentelemetryEcto.setup([:lightning, :repo])
      end
    end

    :ok
  end

  def cowboy_config, do: @cowboy_config
end
