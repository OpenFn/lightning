defmodule Lightning.OpenTelemetry.RedactingProcessorTest do
  use ExUnit.Case, async: true

  alias Lightning.OpenTelemetry.RedactingProcessor

  require Record

  Record.defrecordp(
    :span_rec,
    :span,
    Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  defp span_with(attrs, count_limit \\ 128, value_length_limit \\ :infinity) do
    span_rec(
      name: :GET,
      kind: :server,
      attributes: :otel_attributes.new(attrs, count_limit, value_length_limit)
    )
  end

  defp attrs_of(span), do: :otel_attributes.map(span_rec(span, :attributes))

  describe "on_start/3" do
    test "redacts both URL keys and leaves everything else alone" do
      span =
        span_with(%{
          "url.path": "/users/reset_password/tok",
          "url.query": "token=tok",
          "http.request.method": :GET
        })

      redacted = RedactingProcessor.on_start(:otel_ctx.new(), span, %{})

      assert attrs_of(redacted) == %{
               "url.path": "[redacted]",
               "url.query": "[redacted]",
               "http.request.method": :GET
             }
    end

    test "redacts if only url.path is present" do
      span =
        span_with(%{
          "url.path": "/users/reset_password/tok",
          "http.request.method": :GET
        })

      redacted = RedactingProcessor.on_start(:otel_ctx.new(), span, %{})

      assert attrs_of(redacted) == %{
               "url.path": "[redacted]",
               "http.request.method": :GET
             }
    end

    test "redacts if only url.query is present" do
      span =
        span_with(%{
          "url.query": "token=tok",
          "http.request.method": :GET
        })

      redacted = RedactingProcessor.on_start(:otel_ctx.new(), span, %{})

      assert attrs_of(redacted) == %{
               "url.query": "[redacted]",
               "http.request.method": :GET
             }
    end

    test "does not modify a span that lacks query and path keys" do
      span = span_with(%{"db.system": :postgresql})

      assert RedactingProcessor.on_start(:otel_ctx.new(), span, %{}) == span
    end

    test "redacts even when the span has already hit its attribute limit" do
      # Note: This is actually testing the OpenTelemetry library's behaviour
      # rather than our own code. Given the impact of getting this wrong,
      # I am erring on the side of an overlapping test.
      #
      # Built in two steps on purpose: a map bigger than the limit would have
      # possibly drop url.path itself, and the test would be flaky.
      base =
        :otel_attributes.new(
          %{
            "url.path": "/users/reset_password/tok",
            "url.query": "token=tok",
            "http.request.method": :GET
          },
          3,
          :infinity
        )

      full = :otel_attributes.set(:b, 2, base)

      assert :otel_attributes.dropped(full) == 1

      redacted =
        RedactingProcessor.on_start(
          :otel_ctx.new(),
          span_rec(attributes: full),
          %{}
        )

      assert attrs_of(redacted) == %{
               "url.path": "[redacted]",
               "url.query": "[redacted]",
               "http.request.method": :GET
             }
    end
  end

  describe "on_end/2" do
    test "returns the atom true" do
      assert RedactingProcessor.on_end(:a_span, %{}) == true
    end

    test "returns true whatever the config" do
      assert RedactingProcessor.on_end(:a_span, %{some: :config}) == true
    end
  end

  describe "force_flush/1" do
    test "returns :ok" do
      assert RedactingProcessor.force_flush(%{}) == :ok
    end

    test "returns :ok whatever the config" do
      assert RedactingProcessor.force_flush(%{some: :config}) == :ok
    end
  end

  describe "the processor contract" do
    test "does not export start_link/1 as it is not required" do
      Code.ensure_loaded!(RedactingProcessor)

      refute function_exported?(RedactingProcessor, :start_link, 1)
    end

    test "declares the :otel_span_processor behaviour" do
      # This is the test that lets the compiler cover the rest: with
      # `@behaviour :otel_span_processor` declared and `warnings_as_errors:
      # true`, a missing or misarityed on_start/3, on_end/2 or force_flush/1
      # fails the build. Drop the attribute and all three go quietly missing
      # until a span is ended in production.
      behaviours =
        RedactingProcessor.module_info(:attributes)
        |> Keyword.get(:behaviour, [])

      assert :otel_span_processor in behaviours
    end
  end
end
