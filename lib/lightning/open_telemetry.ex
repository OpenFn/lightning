defmodule Lightning.OpenTelemetry do
  @moduledoc """
  Attaches OpenTelemetry's `:telemetry` handlers.

  Gated separately from the SDK's own `sdk_disabled`: these handlers are
  attached process-wide and cannot be detached per-request, and they build
  their full attribute set before consulting the sampler, so a disabled SDK
  makes them cheap but not free.
  """

  def setup do
    if Lightning.Config.otel_enabled?() do
      # When changing the cowboy configuration, please look for any
      # calls to :opentelemetry_cowboy.setup/1 in the tests and update them
      # appropriately. As of October 2026, this would be
      # Lightning.OpenTelemetry.RedactionCanaryTest.
      :opentelemetry_cowboy.setup(%{public_endpoint: true})

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
end
