defmodule Lightning.AuthProviders.OauthHTTPClient.PinnedAdapter do
  @moduledoc """
  A Tesla adapter for outbound OAuth requests that defends against SSRF and DNS
  rebinding.

  User-controlled endpoint URLs (token, userinfo, revocation, introspection)
  are SSRF sinks. Before any socket is opened, the request host is resolved and
  validated with `Philter.Egress`, which fails closed and blocks internal or
  reserved addresses. The connection is then pinned to a validated IP address
  (never re-resolving the hostname), so DNS cannot swap in an internal address
  between validation and connect.

  For HTTPS, TLS peer verification is always forced on: SNI and certificate
  hostname verification run against the original hostname via Mint's `:hostname`
  option, and any caller-supplied `:verify`/`:verify_fun` is dropped so
  verification cannot be weakened. Redirects are never followed.

  The error surfaced to callers is deliberately generic (`:egress_blocked`); the
  specific egress reason is logged server-side only and never leaked, so the
  adapter cannot be used as an internal-network oracle.

  ## Configuration

  Policy is read from `Application.get_env(:lightning, __MODULE__, [])` and
  merged with per-request adapter options:

    * `:block_private_networks` - block internal ranges. Default `true`.
    * `:allowed_hosts` - host strings that bypass the block. Default `[]`.
    * `:connect_timeout` - overall connect budget in ms. Default `5_000`.
    * `:receive_timeout` - per-recv timeout in ms. Default `15_000`.
    * `:resolver` - a 2-arity resolver, as `Philter.Egress` documents.
    * `:transport_opts` - extra TLS options (private CA, client cert).
  """
  @behaviour Tesla.Adapter

  require Logger

  @egress_opts [:block_private_networks, :allowed_hosts, :resolver, :dns_timeout]

  @impl Tesla.Adapter
  def call(%Tesla.Env{} = env, opts) do
    opts = Keyword.merge(Application.get_env(:lightning, __MODULE__, []), opts)
    uri = env.url |> Tesla.build_url(env.query) |> URI.parse()

    with {:ok, scheme} <- scheme(uri),
         {:ok, host} <- host(uri),
         {:ok, addresses} <- validate(host, env, opts) do
      request(env, opts, scheme, host, port(uri, scheme), addresses, target(uri))
    end
  end

  defp validate(host, env, opts) do
    case Philter.Egress.resolve_and_validate(
           host,
           Keyword.take(opts, @egress_opts)
         ) do
      {:ok, addresses} ->
        {:ok, addresses}

      {:error, reason} ->
        Logger.warning(
          "Blocked OAuth request to a disallowed endpoint (#{inspect(reason)})"
        )

        {:error, %Tesla.Error{env: env, reason: :egress_blocked}}
    end
  end

  defp request(env, opts, scheme, host, port, addresses, target) do
    connect_timeout = Keyword.get(opts, :connect_timeout, 5_000)
    receive_timeout = Keyword.get(opts, :receive_timeout, 15_000)
    transport_opts = Keyword.get(opts, :transport_opts, [])

    case connect(scheme, addresses, port, host, connect_timeout, transport_opts) do
      {:ok, conn} -> exchange(conn, env, target, receive_timeout)
      {:error, reason} -> {:error, %Tesla.Error{env: env, reason: reason}}
    end
  end

  defp exchange(conn, env, target, receive_timeout) do
    method = env.method |> to_string() |> String.upcase()
    acc = %{status: nil, headers: [], body: []}

    try do
      case Mint.HTTP.request(conn, method, target, env.headers, body(env.body)) do
        {:ok, conn, ref} ->
          deadline = System.monotonic_time(:millisecond) + receive_timeout

          case recv_loop(conn, ref, acc, deadline) do
            {:ok, acc} ->
              {:ok,
               %Tesla.Env{
                 env
                 | status: acc.status,
                   headers: finalize_headers(acc.headers),
                   body: finalize(acc.body)
               }}

            {:error, reason} ->
              {:error, %Tesla.Error{env: env, reason: reason}}
          end

        {:error, _conn, reason} ->
          {:error, %Tesla.Error{env: env, reason: reason}}
      end
    after
      Mint.HTTP.close(conn)
    end
  end

  # The timeout is a cumulative deadline for the whole response, not per-recv, so
  # a slow-drip upstream that sends a byte just under each interval cannot hold
  # the connection open indefinitely.
  defp recv_loop(conn, ref, acc, deadline) do
    case deadline - System.monotonic_time(:millisecond) do
      remaining when remaining <= 0 ->
        {:error, %Mint.TransportError{reason: :timeout}}

      remaining ->
        case Mint.HTTP.recv(conn, 0, remaining) do
          {:ok, conn, responses} ->
            case handle_responses(responses, ref, acc) do
              {:done, acc} -> {:ok, acc}
              {:cont, acc} -> recv_loop(conn, ref, acc, deadline)
              {:error, reason} -> {:error, reason}
            end

          {:error, _conn, reason, _responses} ->
            {:error, reason}
        end
    end
  end

  defp handle_responses([], _ref, acc), do: {:cont, acc}

  defp handle_responses([{:status, ref, status} | rest], ref, acc),
    do: handle_responses(rest, ref, %{acc | status: status})

  defp handle_responses([{:headers, ref, headers} | rest], ref, acc),
    do: handle_responses(rest, ref, %{acc | headers: [headers | acc.headers]})

  defp handle_responses([{:data, ref, data} | rest], ref, acc),
    do: handle_responses(rest, ref, %{acc | body: [data | acc.body]})

  defp handle_responses([{:done, ref} | _rest], ref, acc), do: {:done, acc}

  defp handle_responses([{:error, ref, reason} | _rest], ref, _acc),
    do: {:error, reason}

  defp handle_responses([_other | rest], ref, acc),
    do: handle_responses(rest, ref, acc)

  # The resolve-and-pin connect/TLS logic below mirrors `Philter.Transport`
  # deliberately: we reuse `Philter.Egress` for validation but keep our own thin
  # one-shot connection on the stable `Mint` API rather than depend on Philter's
  # internal streaming transport. Keep the TLS posture here in lockstep with it.
  defp connect(scheme, addresses, port, host, connect_timeout, transport_opts) do
    base = [hostname: host, protocols: [:http1], mode: :passive]
    deadline = System.monotonic_time(:millisecond) + connect_timeout

    connect_in_order(
      scheme,
      addresses,
      port,
      base,
      transport_opts,
      deadline,
      nil
    )
  end

  defp connect_in_order(_scheme, [], _port, _base, _caller, _deadline, last) do
    {:error, last || %Mint.TransportError{reason: :nxdomain}}
  end

  defp connect_in_order(
         scheme,
         [address | rest],
         port,
         base,
         caller,
         deadline,
         last
       ) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, last || %Mint.TransportError{reason: :timeout}}
    else
      opts =
        Keyword.put(
          base,
          :transport_opts,
          transport_opts(scheme, caller, remaining)
        )

      case Mint.HTTP.connect(scheme, address, port, opts) do
        {:ok, conn} ->
          {:ok, conn}

        {:error, error} ->
          connect_in_order(scheme, rest, port, base, caller, deadline, error)
      end
    end
  end

  defp transport_opts(:https, caller, timeout) do
    caller
    |> Keyword.drop([:verify, :verify_fun])
    |> Keyword.put(:timeout, timeout)
    |> Keyword.put(:verify, :verify_peer)
  end

  defp transport_opts(:http, caller, timeout) do
    caller
    |> Keyword.drop([:verify, :verify_fun])
    |> Keyword.put(:timeout, timeout)
  end

  defp scheme(%URI{scheme: "https"}), do: {:ok, :https}
  defp scheme(%URI{scheme: "http"}), do: {:ok, :http}
  defp scheme(_uri), do: {:error, %Tesla.Error{reason: :unsupported_scheme}}

  defp host(%URI{host: host}) when is_binary(host) and host != "",
    do: {:ok, host}

  defp host(_uri), do: {:error, %Tesla.Error{reason: :invalid_url}}

  defp port(%URI{port: port}, _scheme) when is_integer(port), do: port
  defp port(_uri, :https), do: 443
  defp port(_uri, :http), do: 80

  defp target(%URI{path: path, query: nil}), do: path || "/"
  defp target(%URI{path: path, query: query}), do: "#{path || "/"}?#{query}"

  defp body(nil), do: nil
  defp body(""), do: nil
  defp body(body), do: body

  defp finalize(chunks), do: chunks |> Enum.reverse() |> IO.iodata_to_binary()

  # Header chunks are prepended per arrival, so reverse to arrival order and
  # concat, avoiding a quadratic `++` when headers span several responses.
  defp finalize_headers(chunks), do: chunks |> Enum.reverse() |> Enum.concat()
end
