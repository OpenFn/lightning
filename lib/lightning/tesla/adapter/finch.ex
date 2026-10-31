defmodule Lightning.Tesla.Adapter.Finch do
  @moduledoc """
  Enough of Tesla's Finch adapter for the Apollo client, with the failure reason
  preserved on a streamed response.

  Not a faithful copy: it drops upstream's `build/4` clauses for multipart,
  stream and function request bodies, and hands the body to `Finch.build/4` as
  it stands. Anything but a plain body therefore fails further down, in Mint,
  rather than here. Apollo sends JSON.

  Upstream's streaming path returns `nil` from its `Stream.unfold` for a
  mid-stream error, a mid-stream timeout, and a clean end alike, discarding the
  reason. Every AI chat therefore ended up reporting "Stream ended without
  complete response" whatever had actually happened - a hung Apollo, a severed
  connection, and a genuinely short answer were indistinguishable.

  A sentinel inside the stream is not an option: `Tesla.Middleware.SSE`
  concatenates elements as binaries and would fail on anything else. But the
  `Stream.unfold` body runs in the calling process, so the reason is left in
  that process's dictionary and read back with `take_stream_error/0` once the
  stream has been consumed.

  Also passes `:request_timeout` through to Finch, which the 1.18.3 we pin
  drops.

  Both are fixed upstream, in separate releases: the option pass-through in
  1.19.0 ([tesla#879](https://github.com/elixir-tesla/tesla/pull/879)), the
  stream reason in 1.21.1
  ([tesla#912](https://github.com/elixir-tesla/tesla/issues/912)). This module
  exists only because we pin `~> 1.18.2`; bumping to 1.21.1 deletes it, and the
  reason then arrives as a raised `Tesla.Error` rather than through
  `take_stream_error/0`, so the caller in `Lightning.AiAssistant` changes with
  it. Tracked in [#5080](https://github.com/OpenFn/lightning/issues/5080).
  """

  @behaviour Tesla.Adapter

  # receive_timeout covers two waits: for status and headers in stream/3, and
  # each gap between chunks in body_stream/3.
  @defaults [receive_timeout: 15_000]
  @stream_error_key {__MODULE__, :stream_error}

  @doc """
  Why the last streamed response stopped, if it stopped badly.

  Returns `nil` when the stream ended cleanly. Reading clears it, so a later
  request cannot pick up an earlier one's failure.
  """
  @spec take_stream_error() :: term() | nil
  def take_stream_error, do: Process.delete(@stream_error_key)

  @impl Tesla.Adapter
  def call(%Tesla.Env{} = env, opts) do
    Process.delete(@stream_error_key)

    opts = Tesla.Adapter.opts(@defaults, env, opts)

    name = Keyword.fetch!(opts, :name)
    url = Tesla.build_url(env)

    req_opts =
      Keyword.take(opts, [:pool_timeout, :receive_timeout, :request_timeout])

    req = Finch.build(env.method, url, env.headers, env.body)

    case request(req, name, req_opts, opts) do
      {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
        {:ok, %Tesla.Env{env | status: status, headers: headers, body: body}}

      # Upstream unwraps %Mint.TransportError{} here. Finch wraps every Mint
      # transport error in one of its own before returning, so that clause
      # cannot fire and is left out.
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(req, name, req_opts, opts) do
    case opts[:response] do
      :stream -> stream(req, name, req_opts)
      nil -> Finch.request(req, name, req_opts)
      other -> raise "Unknown response option: #{inspect(other)}"
    end
  end

  defp stream(req, name, opts) do
    owner = self()
    ref = make_ref()

    # Upstream's two `{:error, _}` clauses are left out: Finch.stream/5 passes
    # only :status, :headers, :data and :trailers here and reports failures
    # through its return value, which handle_stream_response/3 reads.
    fun = fn
      {:status, status}, _acc ->
        status

      {:headers, headers}, status ->
        send(owner, {ref, {:status, status, headers}})

      {:data, data}, _acc ->
        send(owner, {ref, {:data, data}})

      {:trailers, trailers}, _acc ->
        trailers
    end

    task =
      Task.async(fn ->
        req
        |> Finch.stream(name, nil, fun, opts)
        |> handle_stream_response(ref, owner)
      end)

    receive do
      {^ref, {:status, status, headers}} ->
        {:ok,
         %Finch.Response{
           status: status,
           headers: headers,
           body: body_stream(ref, task, opts)
         }}

      {^ref, {:error, error}} ->
        Task.shutdown(task, :brutal_kill)
        {:error, error}
    after
      opts[:receive_timeout] ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  defp body_stream(ref, task, opts) do
    Stream.unfold(nil, fn _ ->
      receive do
        {^ref, {:data, data}} ->
          {data, nil}

        {^ref, :eof} ->
          Task.await(task)
          nil

        # The two clauses upstream discards. Both still halt the stream; the
        # difference is that the reason survives.
        {^ref, {:error, error}} ->
          Process.put(@stream_error_key, error)
          Task.shutdown(task, :brutal_kill)
          nil
      after
        opts[:receive_timeout] ->
          Process.put(@stream_error_key, :timeout)
          Task.shutdown(task, :brutal_kill)
          nil
      end
    end)
  end

  # Upstream's third clause is gated on Finch below 0.20. We pin 0.23, where
  # Finch.stream/5 returns only {:ok, acc} or {:error, exception, acc}.
  defp handle_stream_response({:ok, _acc}, ref, owner) do
    send(owner, {ref, :eof})
  end

  defp handle_stream_response({:error, error, _acc}, ref, owner) do
    send(owner, {ref, {:error, error}})
  end
end
