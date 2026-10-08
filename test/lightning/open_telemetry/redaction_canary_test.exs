defmodule Lightning.OpenTelemetry.RedactionCanaryTest do
  use ExUnit.Case, async: false

  require Record

  @span_fields Record.extract(
                 :span,
                 from_lib: "opentelemetry/include/otel_span.hrl"
               )
  Record.defrecordp(:span_rec, :span, @span_fields)

  @canary "random-canary-niTae9zae2"
  @otel_modules [:opentelemetry_cowboy]

  import Mox

  setup do
    # Do we have processors configured
    assert Application.get_env(:opentelemetry, :processors),
           "no :processors configured - nothing to test"

    # At the time of writing, OpenTelemetry overrides the processors
    # with whatever is set in :span_processor. This is an early-warning that
    # our redaction filter is not going to be having any effect.
    refute Application.get_env(:opentelemetry, :span_processor),
           "span processor overrides :processors"

    # Create a global mock that will be rechable from the cowboy process.
    set_mox_global()
    stub_with(Lightning.MockConfig, Lightning.Config.API)

    # Settings to enable tracing that is observable in the test.
    overrides =
      [
        sdk_disabled: false,
        sampler: :always_on,
        traces_exporter: {:otel_exporter_pid, self()},
        bsp_scheduled_delay_ms: 50
      ]

    current_settings =
      Enum.map(overrides, fn {key, _} ->
        {key, Application.fetch_env(:opentelemetry, key)}
      end)

    Application.stop(:opentelemetry)

    Enum.each(overrides, fn {key, value} ->
      Application.put_env(:opentelemetry, key, value)
    end)

    {:ok, _} = Application.ensure_all_started(:opentelemetry)

    had_handlers? = otel_handlers() != []

    # Detach any handlers that may have been attached by the application
    Enum.each(otel_handlers(), &:telemetry.detach/1)
    :opentelemetry_cowboy.setup()

    on_exit(fn ->
      Enum.each(otel_handlers(), &:telemetry.detach/1)

      Application.stop(:opentelemetry)

      Enum.each(current_settings, fn
        {key, {:ok, value}} -> Application.put_env(:opentelemetry, key, value)
        {key, :error} -> Application.delete_env(:opentelemetry, key)
      end)

      {:ok, _} = Application.ensure_all_started(:opentelemetry)

      if had_handlers?, do: :opentelemetry_cowboy.setup()
    end)

    [port: LightningWeb.Endpoint.config(:http)[:port]]
  end

  test "confirm that traces are being exported", %{port: port} do
    response =
      Finch.build(:get, "http://localhost:#{port}/health_check")
      |> Finch.request(Lightning.Finch)

    assert {:ok, %Finch.Response{status: 200}} = response

    assert_receive {:span, span_rec(kind: :server, attributes: attrs)}, 2_000

    assert %{
             "http.request.method": :GET,
             "http.response.status_code": 200
           } = :otel_attributes.map(attrs)
  end

  test "confim that traces are exported with redaction", %{port: port} do
    response =
      Finch.build(
        :get,
        "http://localhost:#{port}/health_check?canary=#{@canary}"
      )
      |> Finch.request(Lightning.Finch)

    assert {:ok, %Finch.Response{status: 200}} = response

    assert_receive {:span, span_rec(kind: :server, attributes: attrs)}, 2_000

    otel_attrs = :otel_attributes.map(attrs)

    # Confirm that the span has contents
    assert %{"url.path": "[redacted]", "url.query": "[redacted]"} = otel_attrs

    # Confirm that no attributes were dropped, i..e this is not a partial export
    assert :otel_attributes.dropped(attrs) == 0
  end

  defp otel_handlers do
    :telemetry.list_handlers([])
    |> Enum.filter(
      &((Function.info(&1.function, :module) |> elem(1)) in @otel_modules)
    )
    |> Enum.map(& &1.id)
  end
end
