defmodule Lightning.OpenTelemetryTest do
  use ExUnit.Case, async: false

  alias Lightning.OpenTelemetry

  import Mox

  @otel_modules [
    :opentelemetry_cowboy,
    OpentelemetryPhoenix,
    OpentelemetryOban.JobHandler,
    OpentelemetryOban.PluginHandler,
    OpentelemetryEcto
  ]

  setup do
    stub_with(Lightning.MockConfig, Lightning.Config.API)

    # Boot may have attached handlers (a developer with TRACING_ENABLED
    # exported). Start from a known slate.
    Enum.each(otel_handlers(), &:telemetry.detach/1)

    on_exit(fn -> Enum.each(otel_handlers(), &:telemetry.detach/1) end)

    :ok
  end

  test "attaches nothing when tracing is disabled" do
    stub(Lightning.MockConfig, :otel_enabled?, fn -> false end)
    stub(Lightning.MockConfig, :otel_ecto_enabled?, fn -> false end)

    assert otel_handlers() == []
    assert OpenTelemetry.setup() == :ok
    assert otel_handlers() == []
  end

  test "attaches nothing when tracing is disabled, but ecto is enabled" do
    stub(Lightning.MockConfig, :otel_enabled?, fn -> false end)
    stub(Lightning.MockConfig, :otel_ecto_enabled?, fn -> true end)

    assert otel_handlers() == []
    assert OpenTelemetry.setup() == :ok
    assert otel_handlers() == []
  end

  test "doesn't attach ecto handlers - tracing enabled but ecto tracing disabled" do
    stub(Lightning.MockConfig, :otel_enabled?, fn -> true end)
    stub(Lightning.MockConfig, :otel_ecto_enabled?, fn -> false end)

    :ok = OpenTelemetry.setup()

    modules = otel_handlers_by_module()
    assert :opentelemetry_cowboy in modules
    assert OpentelemetryPhoenix in modules
    assert OpentelemetryOban.JobHandler in modules
    refute OpentelemetryEcto in modules
  end

  test "attached all 4 handlers if both tracing and Ecto enabled" do
    stub(Lightning.MockConfig, :otel_enabled?, fn -> true end)
    stub(Lightning.MockConfig, :otel_ecto_enabled?, fn -> true end)

    on_exit(fn -> Enum.each(otel_handlers(), &:telemetry.detach/1) end)

    :ok = OpenTelemetry.setup()

    modules = otel_handlers_by_module()
    assert :opentelemetry_cowboy in modules
    assert OpentelemetryPhoenix in modules
    assert OpentelemetryOban.JobHandler in modules
    assert OpentelemetryEcto in modules
  end

  defp otel_handlers do
    :telemetry.list_handlers([])
    |> Enum.filter(&(handler_module(&1) in @otel_modules))
    |> Enum.map(& &1.id)
  end

  defp otel_handlers_by_module do
    :telemetry.list_handlers([])
    |> Enum.map(&handler_module/1)
    |> Enum.filter(&(&1 in @otel_modules))
    |> Enum.uniq()
  end

  defp handler_module(%{function: fun}) do
    Function.info(fun, :module) |> elem(1)
  end
end
