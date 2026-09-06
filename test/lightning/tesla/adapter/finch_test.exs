defmodule Lightning.Tesla.Adapter.FinchTest do
  @moduledoc """
  Exercises the streaming path over a real socket.

  Everything else in the suite runs against `Lightning.Tesla.Mock`, which never
  drives Tesla's lazy body stream, so none of this is reachable from there. A
  raw listener is used rather than Bypass because these tests deliberately hang
  up mid-response: Bypass links its plug to the test process, so a plug dying on
  the closed socket takes the test with it.
  """
  use ExUnit.Case, async: true

  alias Lightning.Tesla.Adapter.Finch, as: Adapter

  # Deliberately not tight. :receive_timeout covers the wait for the response
  # headers as well as the wait between chunks, so a value chosen to make the
  # test quick expires on the headers instead when the machine is busy, and
  # Tesla.get/2 returns {:error, :timeout} before the body stream is reached.
  # A second is still far below the ten the servers below stay silent for.
  @quiet_timeout 1_000

  # Accepts one connection, hands the socket to `fun`, then closes. The server
  # is unlinked on purpose - see the moduledoc - so the test has to take it
  # down itself: without on_exit, a server still sleeping out its hold time
  # keeps an accepted socket open long after the test that started it passed.
  defp serve(fun) do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen)

    server =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listen)
        {:ok, _request} = :gen_tcp.recv(socket, 0)
        fun.(socket)
        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      Process.exit(server, :kill)
      :gen_tcp.close(listen)
    end)

    port
  end

  defp headers do
    [
      "HTTP/1.1 200 OK\r\n",
      "Content-Type: text/event-stream\r\n",
      "Transfer-Encoding: chunked\r\n\r\n"
    ]
  end

  defp encode(chunk) do
    [Integer.to_string(byte_size(chunk), 16), "\r\n", chunk, "\r\n"]
  end

  # Sends one chunk then holds the connection open in silence.
  defp stalling_server(chunk, hold_ms) do
    serve(fn socket ->
      :gen_tcp.send(socket, [headers(), encode(chunk)])
      Process.sleep(hold_ms)
    end)
  end

  # Never goes quiet for long, so only a deadline on the whole request can stop
  # it.
  defp dripping_server(chunk, every_ms) do
    serve(fn socket ->
      :gen_tcp.send(socket, headers())

      Enum.each(1..40, fn _ ->
        :gen_tcp.send(socket, encode(chunk))
        Process.sleep(every_ms)
      end)
    end)
  end

  defp complete_server(chunks) do
    serve(fn socket ->
      :gen_tcp.send(socket, [headers(), Enum.map(chunks, &encode/1), "0\r\n\r\n"])

      Process.sleep(50)
    end)
  end

  defp drain(port, opts) do
    client =
      Tesla.client(
        [{Tesla.Middleware.BaseUrl, "http://localhost:#{port}"}],
        {Adapter,
         Keyword.merge([name: Lightning.Finch, response: :stream], opts)}
      )

    {:ok, env} = Tesla.get(client, "/stream")
    Enum.to_list(env.body)
  end

  test "a stream that completes leaves no failure behind" do
    port = complete_server(["one", "two"])

    chunks = drain(port, receive_timeout: 2_000)

    assert Enum.join(chunks) == "onetwo"
    assert Adapter.take_stream_error() == nil
  end

  test "a stream that goes quiet is reported as a timeout" do
    port = stalling_server("partial", 10_000)

    chunks = drain(port, receive_timeout: @quiet_timeout)

    # What already arrived is still delivered: the stream halts, it does not
    # raise. Upstream behaves the same - the difference is the reason below,
    # which upstream throws away.
    assert Enum.join(chunks) == "partial"
    assert_went_quiet(Adapter.take_stream_error())
  end

  # The whole-request deadline, which upstream's adapter drops on the floor.
  # Chunks keep arriving well inside receive_timeout, so nothing but
  # request_timeout can end this.
  test "a stream that never goes quiet is still bounded by the request" do
    port = dripping_server("tick", 50)

    chunks = drain(port, receive_timeout: 5_000, request_timeout: 400)

    assert length(chunks) < 40
    assert_went_quiet(Adapter.take_stream_error())
  end

  # The other way a stream dies, and the one that has to read differently to
  # the user: the socket is gone rather than merely quiet.
  test "a dropped connection is reported with its transport reason" do
    port = stalling_server("partial", 200)

    chunks = drain(port, receive_timeout: 10_000)

    assert Enum.join(chunks) == "partial"

    # Finch's own struct, wrapping Mint's. Not a %Mint.TransportError{}, which
    # is why matching only on that one missed this entirely.
    assert %Finch.TransportError{reason: :closed} = Adapter.take_stream_error()
  end

  test "reading the reason clears it, so the next request starts clean" do
    port = stalling_server("partial", 10_000)

    drain(port, receive_timeout: @quiet_timeout)

    assert_went_quiet(Adapter.take_stream_error())
    assert Adapter.take_stream_error() == nil
  end

  # Finch's own deadline and ours are handed the same number, so whichever the
  # scheduler reaches first decides whether the reason arrives as our bare atom
  # or as Finch's struct around the same thing. Both say the stream went quiet,
  # and both produce the same sentence for the user.
  defp assert_went_quiet(reason) do
    assert reason == :timeout or
             match?(%Finch.TransportError{reason: :timeout}, reason)
  end
end
