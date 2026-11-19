defmodule Lightning.OpenTelemetry.RedactionCanaryTest do
  @moduledoc """
  End-to-end guard on what actually leaves the instance in a span.

  Three mechanisms are under test here:

    1. `Lightning.OpenTelemetry.FilteringExporter`, which wraps the real traces
       exporter and rewrites every finished span before it is handed on. On
       the way out it keeps only allowlisted attributes, blanks the status
       description, and drops links. It runs at export rather than at span
       start because a span processor cannot see a span's final state:
       `on_end/2` returns a boolean rather than a span, so attributes set
       after a span starts, the status and links were all out of a
       processor's reach.
    2. `event_count_limit: 0`, which stops any span event being recorded at
       all. This is what keeps `exception.message` out of traces.
    3. The bootstrap raise on the two OS variables that would undo the first
       two: `OTEL_TRACES_EXPORTER` replaces the wrapping exporter, and
       `OTEL_SPAN_EVENT_COUNT_LIMIT` restores events. This file only asserts
       they are absent from the environment it runs in; the raise itself is
       tested in `test/lightning/config/bootstrap_test.exs`.

  Every test ends in the same checks over the exported span. Every attribute
  key must be on the allowlist, and none of the known-sensitive keys may
  appear. Then a sweep runs over every string the span carries: the string
  canary, the two IP canaries, and then any token that `:inet` will parse as
  an address, of either family. That last sweep needs nothing planted in it,
  which is the point. It covers the loopback peer address, which this test
  does not get to choose, and an address reaching a field nobody has thought
  about yet. It parses rather than matching a shape because a regex loose
  enough to catch IPv6 also catches things like a `12:34:56` timestamp, while
  `1.11.0` from a user agent has the shape of nothing at all.

  Only cowboy's handler is attached, so Phoenix's `http.route` never reaches
  these HTTP spans. Attributes set after span start are covered instead by a
  span built by hand, which is what that handler amounts to: a
  `set_attributes/2` on a span that has already started.

  Where a comment here describes a dependency's behaviour, it was read from
  opentelemetry 1.7.0, opentelemetry_cowboy 1.0.0 and otel_http 0.2.0. They
  name the handler or function responsible rather than a line, so a bump that
  moves code leaves them standing; one that reworks these paths will not.
  """
  use ExUnit.Case, async: false

  require Record
  require OpenTelemetry.Tracer

  alias Lightning.OpenTelemetry.FilteringExporter

  @span_fields Record.extract(
                 :span,
                 from_lib: "opentelemetry/include/otel_span.hrl"
               )
  Record.defrecordp(:span_rec, :span, @span_fields)

  Record.defrecordp(
    :span_limits,
    Record.extract(
      :span_limits,
      from_lib: "opentelemetry/include/otel_span.hrl"
    )
  )

  # The SDK's own state, read back so that `setup_all` can check the pipeline
  # actually running rather than the configuration it was given. Both are
  # private records; `_build/test/lib/opentelemetry/src` symlinks to `deps/`,
  # so `from_lib` reaches them.
  #
  # Extracting from a module rather than a header means `epp` parses the whole
  # module and every record use in it is expanded. These modules
  # `-include("otel_span.hrl")`, which lives in `include/`, not beside them
  # in `src/`. rebar3 adds that directory when it compiles them; nothing adds
  # it here, so it is passed explicitly. `Record.extract/2` hands options
  # other than `:from`/`:from_lib` to `:epp.parse_file/2`.
  @otel_includes [Path.join(:code.lib_dir(:opentelemetry), "include")]

  Record.defrecordp(
    :tracer_server_state,
    :state,
    Record.extract(
      :state,
      from_lib: "opentelemetry/src/otel_tracer_server.erl",
      includes: @otel_includes
    )
  )

  Record.defrecordp(
    :batch_processor_data,
    :data,
    Record.extract(
      :data,
      from_lib: "opentelemetry/src/otel_batch_processor.erl",
      includes: @otel_includes
    )
  )

  @canary "random-canary-niTae9zae2"

  # Reserved for documentation - RFC 5737 TEST-NET-2 and RFC 3849 - so neither
  # can ever be a real peer of this test. They are only in a span because a
  # request below put them there.
  #
  # Both are written in the form `inet:ntoa/1` produces, because that is what
  # cowboy stores: an address that round-trips differently
  # (`2001:DB8:0:0:0:0:DEAD:BEEF`) would not match a literal comparison in the
  # sweep.
  @canary_ipv4 "198.51.100.23"
  @canary_ipv6 "2001:db8::dead:beef"

  # Carried in the forwarded host alongside the IPv4 canary, so that
  # `server.port` can act as the control for `server.address`.
  @forwarded_port 8443

  # The OS variables the SDK reads that can undo a data protection. Mirrors
  # the list in `Lightning.Config.Bootstrap`; see the bootstrap tests for the
  # raise.
  @bypass_vars ~w(OTEL_TRACES_EXPORTER OTEL_SPAN_EVENT_COUNT_LIMIT)

  # Keys that must never be exported, listed independently of the
  # allowlist. The allowlist check alone would pass if one of these were
  # added to the allowlist itself; this list is what makes that a red test
  # rather than a quiet widening.
  @denied [
    :"url.path",
    :"url.query",
    :"client.address",
    :"client.port",
    :"network.peer.address",
    :"network.peer.port",
    :"server.address",
    :"network.local.address",
    :"network.local.port",
    :"network.transport",
    :"user_agent.original",
    :"db.url",
    :"db.statement"
  ]

  @otel_modules [:opentelemetry_cowboy]

  import Mox

  setup_all do
    # Neither bypass may be in the environment this suite runs in. Bootstrap
    # would have refused to boot with tracing on, but the suite normally runs
    # with tracing off, so that raise does not reach here. And an OS value
    # would beat every `put_env` override below.
    for var <- @bypass_vars do
      assert System.get_env(var) == nil,
             "#{var} is set in the environment - unset it to run this file"
    end

    # The exporter that bootstrap configured, before this file overrides it:
    # the filter wrapping the real OTLP exporter. If this fails, the
    # override below would be testing a wiring production does not have.
    assert {FilteringExporter, %{exporter: {:opentelemetry_exporter, _}}} =
             Application.get_env(:opentelemetry, :traces_exporter)

    # The application-env half of the event suppression. Checked separately
    # from the effective limit below so that a removal from
    # `Lightning.Config.Bootstrap.setup_opentelemetry/0` fails with a message
    # pointing at our config rather than at the SDK.
    assert Application.get_env(:opentelemetry, :event_count_limit) == 0,
           "event_count_limit is not 0 - exception messages can reach spans"

    # Settings to enable tracing that is observable in the test.
    #
    # The exporter override keeps the filter and swaps only what it wraps. A
    # bare `{:otel_exporter_pid, ...}` here would replace the filter, and
    # this file would be testing an unfiltered pipeline.
    #
    # Deliberately absent: event_count_limit and attribute_value_length_limit.
    # Those are settings under test, so they have to arrive from the real
    # configuration rather than from here.
    overrides =
      [
        sdk_disabled: false,
        sampler: :always_on,
        traces_exporter:
          {FilteringExporter,
           %{exporter: {:otel_exporter_pid, :otel_canary_collector}}},
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

    assert_exporting_through_filter()

    # The *effective* limits, read back after the SDK has started.
    # OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT is not a bypass - it can only
    # shorten values - but it would truncate a canary and turn every sweep
    # below into a vacuous pass.
    assert span_limits(
             attribute_value_length_limit: :infinity,
             event_count_limit: 0
           ) = :otel_span_limits.get()

    had_handlers? = otel_handlers() != []

    # Detach any handlers that may have been attached by the application
    Enum.each(otel_handlers(), &:telemetry.detach/1)
    :opentelemetry_cowboy.setup(%{public_endpoint: true})

    on_exit(fn ->
      Enum.each(otel_handlers(), &:telemetry.detach/1)

      Application.stop(:opentelemetry)

      Enum.each(current_settings, fn
        {key, {:ok, value}} -> Application.put_env(:opentelemetry, key, value)
        {key, :error} -> Application.delete_env(:opentelemetry, key)
      end)

      {:ok, _} = Application.ensure_all_started(:opentelemetry)

      if had_handlers?, do: :opentelemetry_cowboy.setup(%{public_endpoint: true})
    end)
  end

  setup do
    # Create a global mock that will be reachable from the cowboy process.
    set_mox_global()
    stub_with(Lightning.MockConfig, Lightning.Config.API)

    Process.register(self(), :otel_canary_collector)

    [port: LightningWeb.Endpoint.config(:http)[:port]]
  end

  test "confirm that traces are being exported", %{port: port} do
    response =
      Finch.build(:get, "http://localhost:#{port}/health_check")
      |> Finch.request(Lightning.Finch)

    assert {:ok, %Finch.Response{status: 200}} = response

    assert_receive {:span, span_rec(kind: :server, attributes: attrs) = span},
                   2_000

    # Positive controls: attributes that survive the allowlist. They
    # straddle the span lifecycle - method at request start, status at
    # request stop - so together they prove the span started, ended and was
    # exported through the filter. Without them, every absence assertion in
    # this file is also satisfied by a span with no attributes at all.
    assert %{
             "http.request.method": :GET,
             "http.response.status_code": 200
           } = :otel_attributes.map(attrs)

    refute_leaks_in(span)
  end

  test "a request's path and query string are not exported", %{port: port} do
    response =
      Finch.build(
        :get,
        "http://localhost:#{port}/health_check?canary=#{@canary}"
      )
      |> Finch.request(Lightning.Finch)

    assert {:ok, %Finch.Response{status: 200}} = response

    assert_receive {:span, span_rec(kind: :server, attributes: attrs) = span},
                   2_000

    otel_attrs = :otel_attributes.map(attrs)

    # The control: the span is populated, so the absences below are the
    # filter's doing rather than an empty span's.
    assert %{"http.request.method": :GET} = otel_attrs

    refute Map.has_key?(otel_attrs, :"url.path")
    refute Map.has_key?(otel_attrs, :"url.query")

    refute_leaks_in(span)
  end

  test "a caller's IPv4 address does not leave in a span", %{port: port} do
    response =
      Finch.build(
        :get,
        "http://localhost:#{port}/health_check",
        [
          {"x-forwarded-for", @canary_ipv4},
          {"x-forwarded-host", "#{@canary_ipv4}:#{@forwarded_port}"},
          {"x-forwarded-proto", "https"}
        ]
      )
      |> Finch.request(Lightning.Finch)

    assert {:ok, %Finch.Response{status: 200}} = response

    assert_receive {:span, span_rec(kind: :server, attributes: attrs) = span},
                   2_000

    otel_attrs = :otel_attributes.map(attrs)

    # The control, and the only reason `x-forwarded-proto` is sent at all.
    #
    # The filter erases provenance: once `client.address` is absent, the span
    # no longer says whether cowboy took the address from our header or from
    # the socket peer that `extract_client_address/2` falls back to when no
    # forwarded header parses. A header name this test got wrong would
    # therefore look exactly like a pass, and the canary would be proving
    # nothing.
    #
    # `url.scheme` comes from the sibling forwarded header through the same
    # `otel_http` extraction, in cowboy's `extract_scheme/2`, and is
    # allowlisted - it is `http` or `https` and carries no caller data. An
    # `https` here, on a request actually made over `http`, is what proves the
    # forwarded headers this test sends are reaching the instrumentation.
    assert %{"url.scheme": :https} = otel_attrs

    # `server.port` falls out of the same parse of the forwarded host as
    # `server.address`, and is allowlisted, so it is the control for that
    # half: the forwarded port arriving proves the header was read and its
    # address dropped, rather than the header having been ignored.
    assert %{"server.port": @forwarded_port} = otel_attrs

    # All three address attributes cowboy sets at span start: the forwarded
    # client, the real socket peer, and our own address as the caller named
    # it in the forwarded host.
    refute Map.has_key?(otel_attrs, :"client.address")
    refute Map.has_key?(otel_attrs, :"network.peer.address")
    refute Map.has_key?(otel_attrs, :"server.address")

    refute_leaks_in(span)
  end

  test "a caller's IPv6 address does not leave in a span", %{port: port} do
    # `forwarded` rather than `x-forwarded-for`, for two reasons.
    #
    # The first is that an IPv6 address only survives
    # `otel_http:extract_ip_port/1` in the RFC 7239 quoted-and-bracketed form:
    # the clause that parses one matches on the two empty leading segments the
    # quotes produce, and a bare or merely bracketed address falls through to
    # `{undefined, undefined}`. That is also the trap in this test - an
    # unparsed address sends cowboy back to the socket peer, which is dropped
    # too, so a mangled header here passes while proving nothing. `proto`
    # below is the guard against the header as a whole being wrong; nothing
    # can vouch for the `for` directive alone.
    #
    # The second is that `forwarded` and `x-forwarded-for` are of equal
    # priority in `otel_http`'s client header ordering, over a header *map*,
    # so which one wins is not defined. Sending both would make this test's
    # address depend on map ordering.
    response =
      Finch.build(
        :get,
        "http://localhost:#{port}/health_check",
        [{"forwarded", ~s(for="[#{@canary_ipv6}]";proto=https)}]
      )
      |> Finch.request(Lightning.Finch)

    assert {:ok, %Finch.Response{status: 200}} = response

    assert_receive {:span, span_rec(kind: :server, attributes: attrs) = span},
                   2_000

    otel_attrs = :otel_attributes.map(attrs)

    # Same control as the IPv4 test, from the `proto` directive of the same
    # header this time.
    assert %{"url.scheme": :https} = otel_attrs

    # What this test adds is reach, not a second filtering path: the filter
    # works by attribute *key*, so the family of the value never enters into
    # it. What the family does change is everything around that - whether the
    # sweep below can recognise an address at all, and whether some
    # downstream renders one into a field the filter does not reach.
    refute Map.has_key?(otel_attrs, :"client.address")
    refute Map.has_key?(otel_attrs, :"network.peer.address")

    refute_leaks_in(span)
  end

  test "a request that produces an error does not leak the canary", %{
    port: port
  } do
    url =
      "http://localhost:#{port}/users/reset_password/#{@canary}?token=#{@canary}"

    response =
      Finch.build(
        :put,
        url,
        [
          {"content-type", "application/x-nope"},
          # The address rides along on the provocation too: the exception path
          # is where a request's data is most likely to be re-rendered into
          # somewhere the filter does not reach.
          {"x-forwarded-for", @canary_ipv4}
        ],
        "body_text"
      )
      |> Finch.request(Lightning.Finch)

    assert {:ok, %Finch.Response{status: 403}} = response

    assert_receive {:span,
                    span_rec(kind: :server, attributes: attrs, events: events) =
                      span},
                   2_000

    otel_attrs = :otel_attributes.map(attrs)

    # Pin the provocation. Cowboy's exception handler sets `error.type` to the
    # bare exception struct module rather than a formatted string, so this is
    # an exact match and it proves *which* exception reached cowboy. Without it,
    # a future change that raises something else — or nothing — leaves the
    # assertions below green while testing nothing: a request that never raised
    # has no exception event to suppress either.
    #
    # `error.type` is set after the span starts, so this is also an
    # allowlisted late attribute surviving the filter end to end.
    assert %{"error.type": Plug.CSRFProtection.InvalidCSRFTokenError} =
             otel_attrs

    # Only exceptions carrying a literal `:message` *field* reach
    # record_exception at all - that same handler matches on one.
    # `Plug.CSRFProtection.InvalidCSRFTokenError` defines `:message`, which is
    # why this provocation exercises the event sink where a
    # FunctionClauseError-shaped one would not: it would fall through to the
    # catch-all branch and record nothing.
    #
    # Its message is a compile-time constant, so the canary sweep alone would
    # prove very little here. What the next two assertions prove is the
    # mechanism: cowboy *did* offer an exception event, and it was refused.
    assert :otel_events.list(events) == [],
           "an exception event was recorded - event_count_limit is not holding"

    # The dropped counter is the positive half. `list == []` is equally true of
    # a span nobody ever offered an event to; a non-zero dropped count means
    # one was offered and refused. `:otel_events` does that counting and
    # `:otel_span_ets` persists the count onto the span. Not pinned to exactly
    # 1 — the count is incidental, none landing is the point.
    assert :otel_events.dropped(events) > 0,
           "no event was offered - this test is not exercising suppression"

    refute_leaks_in(span)
  end

  test "a caller's traceparent is not exported as a link", %{port: port} do
    injected_trace_id = "decafbaddecafbaddecafbaddecafbad"

    response =
      Finch.build(
        :get,
        "http://localhost:#{port}/health_check",
        [{"traceparent", "00-#{injected_trace_id}-1111111111111111-01"}]
      )
      |> Finch.request(Lightning.Finch)

    assert {:ok, %Finch.Response{status: 200}} = response

    assert_receive {:span,
                    span_rec(
                      kind: :server,
                      trace_id: trace_id,
                      parent_span_id: parent_span_id,
                      links: links
                    ) = span},
                   2_000

    # `public_endpoint: true` in force: the caller's context did not become
    # the parent, so the span is a fresh root on a trace of our own.
    assert parent_span_id == :undefined
    refute trace_id == String.to_integer(injected_trace_id, 16)

    # With `public_endpoint: true`, cowboy records the caller's context as a
    # link instead, so the link's trace and span ids are the caller's choice.
    # The filter drops links.
    #
    # Once the link is dropped, nothing in the exported span can prove the
    # header was parsed. The evidence is this test's red state against code
    # that does not drop links: it fails on this assertion, with the link
    # present.
    assert :otel_links.list(links) == [],
           "a link was exported - a caller can choose its trace id"

    refute_leaks_in(span)
  end

  test "attributes set after a span starts are filtered too" do
    # `on_start` redaction could never reach these: Phoenix's `http.route`,
    # cowboy's response status and `error.type`, and anything Lightning's own
    # code adds with `set_attributes/2`. This is the case the move to the
    # exporter exists for.
    span_ctx = OpenTelemetry.Tracer.start_span(:canary_late_attributes)

    OpenTelemetry.Span.set_attributes(span_ctx, %{
      # Allowlisted, so it must survive: the control.
      "http.route": "/canary/:id",
      # Not allowlisted: an attribute nobody has reviewed yet.
      "lightning.canary": @canary,
      # Denied, and set late, as a careless handler might.
      "client.address": @canary_ipv4
    })

    :otel_span.end_span(span_ctx)

    assert_receive {:span,
                    span_rec(name: :canary_late_attributes, attributes: attrs) =
                      span},
                   2_000

    otel_attrs = :otel_attributes.map(attrs)

    assert %{"http.route": "/canary/:id"} = otel_attrs
    refute Map.has_key?(otel_attrs, :"lightning.canary")
    refute Map.has_key?(otel_attrs, :"client.address")

    refute_leaks_in(span)
  end

  test "a span's status description does not leave the instance" do
    # OpentelemetryEcto puts the driver's error message in the status, and for
    # Postgrex that carries the `detail` field - the value a unique violation
    # collided on, say. Cowboy puts its reason term there on the two paths
    # where a request ends without a response. A span built by hand is the
    # stand-in for both: neither is reachable from this file without
    # switching on Ecto spans or breaking a connection mid-request.
    span_ctx = OpenTelemetry.Tracer.start_span(:canary_status)

    OpenTelemetry.Span.set_status(
      span_ctx,
      :opentelemetry.status(
        :error,
        "duplicate key #{@canary} from #{@canary_ipv4} and [#{@canary_ipv6}]"
      )
    )

    :otel_span.end_span(span_ctx)

    assert_receive {:span,
                    span_rec(name: :canary_status, status: status) = span},
                   2_000

    # The code survives - a trace still says the span failed - and only the
    # description is blanked.
    assert {:status, :error, ""} = status

    refute_leaks_in(span)
  end

  test "no caller of record_exception can attach an event to a span" do
    # Generalises the HTTP test above to every record_exception caller,
    # including the one this file cannot drive end to end:
    # OpentelemetryOban.JobHandler.handle_job_exception/4 goes through the
    # *Elixir* wrapper, OpenTelemetry.Span.record_exception/4,
    # which caps neither exception.message nor exception.stacktrace — and the
    # latter renders function arguments for VM-raised errors. It is the worse
    # of the two paths, so suppression has to cover it too.
    span_ctx = OpenTelemetry.Tracer.start_span(:canary_record_exception)

    # Both families in the message: an exception is the one place in this file
    # where an address appears as free text rather than as an attribute, which
    # is exactly the shape the sweep's parse has to cope with.
    {exception, stacktrace} =
      try do
        raise RuntimeError,
              "boom #{@canary} from #{@canary_ipv4} and [#{@canary_ipv6}]"
      rescue
        e -> {e, __STACKTRACE__}
      end

    # Note the return value: the API reports success even though nothing was
    # stored, because the ETS element really was updated — with an events
    # record whose dropped count went up. Only the span reveals the truth, so
    # never let a caller's return value stand in for the assertions below.
    assert OpenTelemetry.Span.record_exception(
             span_ctx,
             exception,
             stacktrace,
             []
           )

    :otel_span.end_span(span_ctx)

    assert_receive {:span,
                    span_rec(name: :canary_record_exception, events: events) =
                      span},
                   2_000

    assert :otel_events.list(events) == [],
           "record_exception landed an event on the span"

    assert :otel_events.dropped(events) > 0,
           "no event was offered - this test is not exercising suppression"

    refute_leaks_in(span)
  end

  # The exporter the running batch processor holds, as opposed to the one the
  # application env asks for. Two things separate them. The SDK merges OS
  # variables over the app env when it starts. And an exporter whose `init/1`
  # raises or returns `:ignore` leaves the processor holding `undefined`, with
  # span inserts switched off. That fails every test below as an
  # `assert_receive` timeout that names no cause.
  #
  # The processor is found through the global tracer provider's list of
  # processors it started, which records the name each one registered under.
  # That avoids hardcoding `otel_batch_processor_global`, a name that exists
  # only because of the SDK's deprecated single-processor `set_exporter` hack.
  #
  # A batch processor's state-enter callback initialises its exporter before
  # the process handles any message, so this is safe to call as soon as
  # `ensure_all_started` returns.
  defp assert_exporting_through_filter do
    tracer_server_state(processors: processors) =
      :sys.get_state(:otel_tracer_provider_global)

    assert [{:otel_batch_processor, %{reg_name: reg_name}}] = processors

    {_state_name,
     batch_processor_data(exporter_config: config, exporter: exporter)} =
      :sys.get_state(reg_name)

    # What was asked for, after the OS-env merge.
    assert {FilteringExporter,
            %{exporter: {:otel_exporter_pid, :otel_canary_collector}}} = config

    # What `otel_exporter:init/1` made of it: `{Module, State}`, where the
    # filter's state is the inner exporter and that exporter's own state.
    assert match?(
             {FilteringExporter, {:otel_exporter_pid, :otel_canary_collector}},
             exporter
           ),
           "the batch processor is not exporting through FilteringExporter: " <>
             inspect(exporter)
  end

  # Every exported span gets the same treatment, whatever the test asserted
  # first.
  #
  # There is deliberately no `:otel_attributes.dropped/1 == 0` check. The
  # filter rebuilds the attribute record, which resets the counter, so the
  # check would always pass. And an attribute dropped at the count limit is
  # not exported, so it cannot leak.
  defp refute_leaks_in(
         span_rec(
           attributes: attrs,
           status: status,
           events: events,
           links: links
         )
       ) do
    attrs_map = :otel_attributes.map(attrs)

    assert_only_allowed(attrs_map)

    for {key, value} <- attrs_map,
        scanned <- scannable(key) ++ scannable(value) do
      refute_leak(scanned, "attribute #{inspect(key)} => #{inspect(value)}")
    end

    # Status is neither an attribute nor an event, so nothing else in this file
    # would catch a description carrying request data.
    for scanned <- terms(status) do
      refute_leak(scanned, "span status: #{inspect(status)}")
    end

    recorded_events = :otel_events.list(events)

    for scanned <- terms(recorded_events) do
      refute_leak(scanned, "span events: #{inspect(recorded_events)}")
    end

    recorded_links = :otel_links.list(links)

    for scanned <- terms(recorded_links) do
      refute_leak(scanned, "span links: #{inspect(recorded_links)}")
    end
  end

  # Two checks, against two independent lists. The allowlist comes from the
  # filter itself, so this proves the wiring; its contents are pinned by
  # `filtering_exporter_test.exs`. The denied list lives here, so widening the
  # allowlist to cover one of its keys fails this file as well.
  defp assert_only_allowed(attrs_map) do
    allowed = FilteringExporter.allowed_attributes()

    outside =
      attrs_map |> Map.keys() |> Enum.reject(&(&1 in allowed)) |> Enum.sort()

    assert outside == [], "attributes outside the allowlist: #{inspect(outside)}"

    denied = attrs_map |> Map.keys() |> Enum.filter(&(&1 in @denied))

    assert denied == [], "denied attributes exported: #{inspect(denied)}"
  end

  # The sweeps, run over every string the span carries. The canary checks are
  # subsets of `addresses_in/1` and `String.contains?/2` is not what makes
  # them worth keeping - the failure message is. A canary names the request
  # that leaked; a bare address does not.
  defp refute_leak(scanned, where) do
    refute String.contains?(scanned, @canary), "canary leaked in #{where}"

    for canary_ip <- [@canary_ipv4, @canary_ipv6] do
      refute String.contains?(scanned, canary_ip),
             "canary IP #{canary_ip} leaked in #{where}"
    end

    case addresses_in(scanned) do
      [] ->
        :ok

      found ->
        flunk("IP address #{Enum.join(found, ", ")} in #{where}")
    end
  end

  # Addresses of either family, found by parsing rather than by shape, so that
  # `::1` counts and `mint/1.11.0` does not. The strict parsers are what makes
  # this usable: the lenient ones accept `1.11` as 1.0.0.11, which would make
  # every version string a failure.
  #
  # Tokens are split on everything an address cannot contain, so a bracketed
  # and ported form such as `[2001:db8::1]:8080` still yields the address
  # itself. The split is deliberately generous about what it hands to the
  # parser - a term like `<<1::8>>` reduces to `1::8`, which is a legal
  # address and will fail here. That is the same trade as `scannable/1` below:
  # a surprise is for a human to look at, not for the test to wave through.
  defp addresses_in(scanned) do
    scanned
    |> String.split(~r/[^0-9A-Fa-f.:]+/, trim: true)
    |> Enum.filter(fn token ->
      match?({:ok, _}, :inet.parse_strict_address(String.to_charlist(token)))
    end)
  end

  defp otel_handlers do
    :telemetry.list_handlers([])
    |> Enum.filter(
      &((Function.info(&1.function, :module) |> elem(1)) in @otel_modules)
    )
    |> Enum.map(& &1.id)
    |> Enum.uniq()
  end

  # Attribute values get the strict treatment: an unrecognised value type is a
  # flunk rather than a skip, because a type we have not seen before is exactly
  # the thing a human should look at before it ships.
  defp scannable(value) when is_binary(value), do: [value]
  defp scannable(value) when is_atom(value), do: [Atom.to_string(value)]
  defp scannable(value) when is_number(value), do: []

  defp scannable(value) when is_list(value) do
    # A charlist is indistinguishable from a legal integer array at runtime,
    # so scan the printable form as well as the elements.
    printable =
      if List.ascii_printable?(value), do: [List.to_string(value)], else: []

    printable ++ Enum.flat_map(value, &scannable/1)
  end

  defp scannable(value) do
    flunk("unhandled attribute value type: #{inspect(value)}")
  end

  # Statuses, events and links are arbitrary nested terms — records, which
  # are tuples, holding further records — so this walk is tolerant where
  # `scannable/1` is strict: the goal is to reach every string in the
  # structure, not to enumerate the shapes it can take.
  defp terms(term) when is_binary(term), do: [term]
  defp terms(term) when is_atom(term), do: [Atom.to_string(term)]
  defp terms(term) when is_tuple(term), do: term |> Tuple.to_list() |> terms()
  defp terms(term) when is_map(term), do: term |> Map.to_list() |> terms()

  defp terms(term) when is_list(term) do
    printable =
      if List.ascii_printable?(term), do: [List.to_string(term)], else: []

    printable ++ Enum.flat_map(term, &terms/1)
  end

  defp terms(_other), do: []
end
