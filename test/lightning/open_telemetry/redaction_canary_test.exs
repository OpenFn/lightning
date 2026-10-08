defmodule Lightning.OpenTelemetry.RedactionCanaryTest do
  @moduledoc """
  End-to-end guard on what actually leaves the instance in a span.

  Two independent mechanisms are under test here:

    1. `Lightning.OpenTelemetry.RedactingProcessor`, which rewrites the
       request-derived attributes at span *start*: `url.path`, `url.query`,
       and every attribute that can hold an address — `client.address`,
       `network.peer.address` and `server.address`.
    2. `event_count_limit: 0`, which stops any span event being recorded at
       all. This is what keeps `exception.message` out of traces. A span
       processor cannot touch a span after it starts — `on_end/2` returns a
       boolean, not a span, per the `:otel_span_processor` behaviour — so
       redaction is structurally incapable of reaching an exception event,
       which is added mid-span by `otel_span:record_exception/6`. Suppressing
       events is.

  Every test ends in the same sweep over each string the exported span
  carries: the string canary, the two IP canaries, and then any token that
  `:inet` will parse as an address, of either family. That last sweep needs
  nothing planted in it, which is the point — it covers the loopback peer
  address, which this test does not get to choose, and an address reaching a
  field nobody has thought about yet. It parses rather than matching a shape
  because a regex loose enough to catch IPv6 also catches things like a
  `12:34:56` timestamp, while `1.11.0` from a user agent has the shape of
  nothing at all.

  Where a comment here describes a dependency's behaviour, it was read from
  opentelemetry 1.7.0, opentelemetry_cowboy 1.0.0 and otel_http 0.2.0. They
  name the handler or function responsible rather than a line, so a bump that
  moves code leaves them standing; one that reworks these paths will not.

  Known gap, deliberately not closed here: a span's `status` *description* is
  a separate field from its attributes and its events, so neither mechanism
  above reaches it. Redaction rewrites attributes, and a description is not an
  event. Two things write one:

    * cowboy itself, on the two paths where a request ends without a response
      of its own: a `[cowboy, request, stop]` with no response status, and a
      `[cowboy, request, early_error]`. Both pass cowboy's reason term
      straight through. Those reasons describe the protocol rather than the
      request, and this file drives neither path: a handled exception arrives
      as `[cowboy, request, exception]`, which sets an empty description.
    * `OpentelemetryEcto`, which puts `Exception.message/1` of the driver
      error in. For Postgrex that message carries the `detail` field, which
      names column values: the email address a unique violation collided on,
      say. Only reachable with `TRACING_ECTO_ENABLED`, which is off by
      default.

  The sweep below covers `status` for both, so switching Ecto spans on in this
  test's config is the change that would surface the second.
  """
  use ExUnit.Case, async: false

  require Record
  require OpenTelemetry.Tracer

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

  @otel_modules [:opentelemetry_cowboy]

  import Mox

  setup_all do
    # Do we have processors configured
    assert Application.get_env(:opentelemetry, :processors),
           "no :processors configured - nothing to test"

    # At the time of writing, OpenTelemetry overrides the processors
    # with whatever is set in :span_processor. This is an early-warning that
    # our redaction filter is not going to be having any effect.
    refute Application.get_env(:opentelemetry, :span_processor),
           "span processor overrides :processors"

    # The application-env half of the event suppression. Checked separately
    # from the effective limit below so that a removal from
    # `Lightning.Config.Bootstrap.setup_opentelemetry/0` fails with a message
    # pointing at our config rather than at the SDK.
    assert Application.get_env(:opentelemetry, :event_count_limit) == 0,
           "event_count_limit is not 0 - exception messages can reach spans"

    # Settings to enable tracing that is observable in the test.
    #
    # Deliberately absent: event_count_limit and attribute_value_length_limit.
    # Those are the settings under test, so they have to arrive from the real
    # configuration rather than from here.
    overrides =
      [
        sdk_disabled: false,
        sampler: :always_on,
        traces_exporter: {:otel_exporter_pid, :otel_canary_collector},
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

    # The *effective* limits, read back after the SDK has started. This is the
    # assertion that carries the weight, because the OS environment wins over
    # application config in this SDK an exported OTEL_SPAN_EVENT_COUNT_LIMIT
    # silently restores exception events, and
    # OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT would truncate the canary and
    # turn every sweep below into a vacuous pass.
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

    assert_receive {:span, span_rec(kind: :server, attributes: attrs)}, 2_000

    assert %{
             "http.request.method": :GET,
             "http.response.status_code": 200
           } = :otel_attributes.map(attrs)
  end

  test "confirm that traces are exported with redaction", %{port: port} do
    response =
      Finch.build(
        :get,
        "http://localhost:#{port}/health_check?canary=#{@canary}"
      )
      |> Finch.request(Lightning.Finch)

    assert {:ok, %Finch.Response{status: 200}} = response

    assert_receive {:span,
                    span_rec(
                      kind: :server,
                      attributes: attrs,
                      status: status,
                      events: events
                    )},
                   2_000

    otel_attrs = :otel_attributes.map(attrs)

    # Confirm that the span has contents
    assert %{"url.path": "[redacted]", "url.query": "[redacted]"} = otel_attrs

    # Confirm that no attributes were dropped, i.e. this is not a partial export
    assert :otel_attributes.dropped(attrs) == 0

    refute_leaks_in(otel_attrs, status, events)
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

    assert_receive {:span,
                    span_rec(
                      kind: :server,
                      attributes: attrs,
                      status: status,
                      events: events
                    )},
                   2_000

    otel_attrs = :otel_attributes.map(attrs)

    # The control, and the only reason `x-forwarded-proto` is sent at all.
    #
    # Redaction erases provenance: once `client.address` reads "[redacted]",
    # the span no longer says whether it held the address from our header or
    # the socket peer that cowboy's `extract_client_address/2` falls back to
    # when no forwarded header parses. A header name this test got wrong would
    # therefore look exactly like a pass, and the canary would be proving
    # nothing.
    #
    # `url.scheme` comes from the sibling forwarded header through the same
    # `otel_http` extraction, in cowboy's `extract_scheme/2`, and is not
    # redacted - it is `http` or `https` and carries no caller data. An
    # `https` here, on a request actually made over `http`, is what proves the
    # forwarded headers this test sends are reaching the instrumentation.
    assert %{"url.scheme": :https} = otel_attrs

    # Both address attributes cowboy sets at span start: `client.address` is
    # the forwarded address, `network.peer.address` is always the real socket
    # peer, whatever a header claims. The keys
    # have to still be there - an absent key would satisfy the sweep below
    # while saying nothing about redaction.
    assert %{
             "client.address": "[redacted]",
             "network.peer.address": "[redacted]"
           } = otel_attrs

    # `server.address` is the instance's own address rather than the caller's,
    # but cowboy's `extract_server_address/2` reads it from a header the
    # caller supplies, so an IP in it is an IP a caller chose - which is why
    # it is redacted too, and why the canary above is sent as the forwarded
    # host as well as the forwarded client.
    #
    # `server.port` falls out of the same parse and is not redacted, so it is
    # the control for this half: the forwarded port arriving proves the header
    # was read and its address scrubbed, rather than the header having been
    # ignored and the real host left to stand.
    assert %{"server.address": "[redacted]", "server.port": @forwarded_port} =
             otel_attrs

    # Confirm that no attributes were dropped, i.e. this is not a partial export
    assert :otel_attributes.dropped(attrs) == 0

    refute_leaks_in(otel_attrs, status, events)
  end

  test "a caller's IPv6 address does not leave in a span", %{port: port} do
    # `forwarded` rather than `x-forwarded-for`, for two reasons.
    #
    # The first is that an IPv6 address only survives
    # `otel_http:extract_ip_port/1` in the RFC 7239 quoted-and-bracketed form:
    # the clause that parses one matches on the two empty leading segments the
    # quotes produce, and a bare or merely bracketed address falls through to
    # `{undefined, undefined}`. That is also the trap in this test - an
    # unparsed address sends cowboy back to the socket peer, which is redacted
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

    assert_receive {:span,
                    span_rec(
                      kind: :server,
                      attributes: attrs,
                      status: status,
                      events: events
                    )},
                   2_000

    otel_attrs = :otel_attributes.map(attrs)

    # Same control as the IPv4 test, from the `proto` directive of the same
    # header this time.
    assert %{"url.scheme": :https} = otel_attrs

    # What this test adds is reach, not a second redaction path: the processor
    # rewrites by attribute *key*, so the family of the value never enters
    # into it. What the family does change is everything around that - whether
    # the sweep below can recognise an address at all, and whether some
    # downstream renders one into a field redaction cannot reach.
    assert %{
             "client.address": "[redacted]",
             "network.peer.address": "[redacted]"
           } = otel_attrs

    # Confirm that no attributes were dropped, i.e. this is not a partial export
    assert :otel_attributes.dropped(attrs) == 0

    refute_leaks_in(otel_attrs, status, events)
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
          # somewhere attribute redaction cannot reach.
          {"x-forwarded-for", @canary_ipv4}
        ],
        "body_text"
      )
      |> Finch.request(Lightning.Finch)

    assert {:ok, %Finch.Response{status: 403}} = response

    assert_receive {:span,
                    span_rec(
                      kind: :server,
                      attributes: attrs,
                      status: status,
                      events: events
                    )},
                   2_000

    otel_attrs = :otel_attributes.map(attrs)

    assert %{"url.path": "[redacted]", "url.query": "[redacted]"} = otel_attrs

    # Pin the provocation. Cowboy's exception handler sets `error.type` to the
    # bare exception struct module rather than a formatted string, so this is
    # an exact match and it proves *which* exception reached cowboy. Without it,
    # a future change that raises something else — or nothing — leaves the
    # assertions below green while testing nothing: a request that never raised
    # has no exception event to suppress either.
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

    refute_leaks_in(otel_attrs, status, events)
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
                    span_rec(
                      name: :canary_record_exception,
                      attributes: attrs,
                      status: status,
                      events: events
                    )},
                   2_000

    assert :otel_events.list(events) == [],
           "record_exception landed an event on the span"

    assert :otel_events.dropped(events) > 0,
           "no event was offered - this test is not exercising suppression"

    refute_leaks_in(:otel_attributes.map(attrs), status, events)
  end

  defp refute_leaks_in(attrs_map, status, events) do
    for {key, value} <- attrs_map,
        scanned <- scannable(key) ++ scannable(value) do
      refute_leak(scanned, "attribute #{inspect(key)} => #{inspect(value)}")
    end

    # Status is neither an attribute nor an event, so nothing else in this file
    # would catch a description carrying request data.
    for scanned <- terms(status) do
      refute_leak(scanned, "span status: #{inspect(status)}")
    end

    recorded = :otel_events.list(events)

    for scanned <- terms(recorded) do
      refute_leak(scanned, "span events: #{inspect(recorded)}")
    end
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

  # Statuses and events are arbitrary nested terms — records, which are tuples,
  # holding further records — so this walk is tolerant where `scannable/1` is
  # strict: the goal is to reach every string in the structure, not to
  # enumerate the shapes it can take.
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
