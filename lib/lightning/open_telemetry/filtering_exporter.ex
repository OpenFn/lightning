defmodule Lightning.OpenTelemetry.FilteringExporter do
  @moduledoc """
  Wraps a traces exporter. For now it hands every batch on unchanged; span
  filtering is added in later commits.
  """

  @behaviour :otel_exporter_traces

  @impl true
  def init(%{exporter: {mod, opts}}) do
    case mod.init(opts) do
      {:ok, state} -> {:ok, {mod, state}}
      :ignore -> :ignore
    end
  end

  @impl true
  def export(tab, resource, {mod, state}), do: mod.export(tab, resource, state)

  @impl true
  def shutdown({mod, state}), do: mod.shutdown(state)

  def allowed_attributes do
    []
  end
end
