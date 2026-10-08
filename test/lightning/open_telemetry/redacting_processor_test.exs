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
    test "redacts every key in the list and leaves everything else alone" do
      # The whole list in one span, which is the only test here that pins what
      # the list *is*. `server.address` is a hostname rather than an address
      # on purpose: it goes because the caller's `host` header chooses it, not
      # because of what it happens to contain.
      span =
        span_with(%{
          "url.path": "/users/reset_password/tok",
          "url.query": "token=tok",
          "client.address": "198.51.100.23",
          "network.peer.address": "2001:db8::dead:beef",
          "server.address": "lightning.example.com",
          "network.local.address": "10.0.0.7",
          "http.request.method": :GET
        })

      redacted = RedactingProcessor.on_start(:otel_ctx.new(), span, %{})

      assert attrs_of(redacted) == %{
               "url.path": "[redacted]",
               "url.query": "[redacted]",
               "client.address": "[redacted]",
               "network.peer.address": "[redacted]",
               "server.address": "[redacted]",
               "network.local.address": "[redacted]",
               "http.request.method": :GET
             }
    end

    test "redacts if only url.path is present" do
      # Deliberately *not* carrying the address attributes. The assertion is
      # an equality, so a span holding one key from the list and none of the
      # others is what proves redaction rewrites rather than inserts - were
      # `Map.new/2` to run over the whole list instead of the keys present,
      # this is the test that fails.
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
      # Same role as the test above: one key from the list, the rest absent
      # and required to stay absent.
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

    test "redacts if only client.address is present" do
      # One test per address key, each the mirror of the two URL tests above:
      # the key under test present, every other key in the list absent and
      # required to stay absent. A cowboy span always carries a `url.path`
      # alongside these, so without this group the address keys are only ever
      # exercised in company - and it is the filter over `@redactions`, one
      # key at a time, that decides each of them.
      span =
        span_with(%{
          "client.address": "198.51.100.23",
          "http.request.method": :GET
        })

      redacted = RedactingProcessor.on_start(:otel_ctx.new(), span, %{})

      assert attrs_of(redacted) == %{
               "client.address": "[redacted]",
               "http.request.method": :GET
             }
    end

    test "redacts if only network.peer.address is present" do
      # IPv6, because the attribute holds whichever family the socket used and
      # nothing else in this file would say so.
      span =
        span_with(%{
          "network.peer.address": "2001:db8::dead:beef",
          "http.request.method": :GET
        })

      redacted = RedactingProcessor.on_start(:otel_ctx.new(), span, %{})

      assert attrs_of(redacted) == %{
               "network.peer.address": "[redacted]",
               "http.request.method": :GET
             }
    end

    test "redacts if only server.address is present" do
      span =
        span_with(%{
          "server.address": "lightning.example.com",
          "http.request.method": :GET
        })

      redacted = RedactingProcessor.on_start(:otel_ctx.new(), span, %{})

      assert attrs_of(redacted) == %{
               "server.address": "[redacted]",
               "http.request.method": :GET
             }
    end

    test "redacts if only network.local.address is present" do
      # The opt-in attribute. Nothing emits it today, which is exactly why it
      # is worth a test: switching the cowboy opt-in attributes on should not
      # be the moment anyone discovers whether it was covered.
      span =
        span_with(%{
          "network.local.address": "10.0.0.7",
          "http.request.method": :GET
        })

      redacted = RedactingProcessor.on_start(:otel_ctx.new(), span, %{})

      assert attrs_of(redacted) == %{
               "network.local.address": "[redacted]",
               "http.request.method": :GET
             }
    end

    test "does not modify a span that has none of the redacted keys" do
      # The identity branch (`[] -> attrs`), so this span has to stay free of
      # every key in the list.
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
      #
      # Left on two redaction keys rather than six: what is under test is that
      # `:otel_attributes.set/2` can overwrite a key in a full table, and that
      # does not get truer with more keys - while a limit of 3 and a map of
      # seven entries would make which key survives a matter of ordering.
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
