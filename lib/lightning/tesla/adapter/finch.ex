defmodule Lightning.Tesla.Adapter.Finch do
  @moduledoc """
  Tesla's Finch adapter, with the failure reason preserved on a streamed
  response.

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

  Also passes `:request_timeout` through to Finch, which the 1.18.3 we are
  pinned to drops. That one is already fixed upstream, in 1.19.0 and later, so
  a Tesla upgrade would cover it without this module.

  Reported upstream as
  [tesla#912](https://github.com/elixir-tesla/tesla/issues/912). Delete this
  module once a release carries the fix; the reason will arrive as a raised
  `Tesla.Error` rather than through `take_stream_error/0`, so the callers in
  `Lightning.AiAssistant` change with it.
  """

  @behaviour Tesla.Adapter

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

      {:error, %Mint.TransportError{reason: reason}} ->
        {:error, reason}

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

    fun = fn
      {:status, status}, _acc ->
        status

      {:headers, headers}, status ->
        send(owner, {ref, {:status, status, headers}})

      {:data, data}, _acc ->
        send(owner, {ref, {:data, data}})

      {:trailers, trailers}, _acc ->
        trailers

      {:error, error}, _acc ->
        send(owner, {ref, {:error, error}})

      {:error, error, _}, _acc ->
        send(owner, {ref, {:error, error}})
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

        # The two clauses upstream discards. Both still halt the stream, so a
        # consumer sees what it would on upstream; the difference is that the
        # reason survives.
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

  # Upstream carries a third clause for a bare `{:error, reason}`. Finch.stream/5
  # returns only `{:ok, acc}` or `{:error, exception, acc}`, so dialyzer proves
  # that clause unreachable; it is left out rather than ignored. Restore it if a
  # Finch upgrade widens the return.
  defp handle_stream_response({:ok, _acc}, ref, owner) do
    send(owner, {ref, :eof})
  end

  defp handle_stream_response({:error, error, _acc}, ref, owner) do
    send(owner, {ref, {:error, error}})
  end
end
