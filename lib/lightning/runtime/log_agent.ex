defmodule Lightning.Runtime.LogAgent do
  @moduledoc """
  Agent facility to consume STDOUT/STDERR byte by byte.

  Since it works on a byte by byte basis, you will need to perform line-splitting
  yourself.

  Usage:

  ```
  {:ok, log} = LogAgent.start_link()
  "foo" = LogAgent.process_chunk(log, {:stdout, "foo"})
  "foobar" = LogAgent.process_chunk(log, {:stdout, "bar"})
  ```
  """
  use Agent

  @type logline ::
          {timestamp :: integer(), type :: :stdout | :stderr, line :: binary()}

  defmodule StringBuffer do
    @moduledoc """
    Internal datastructure to hold and process new bytes for a list of
    characters.

    By checking the if the buffer is a complete grapheme, emitting the buffer
    once valid and returning `nil` otherwise.

    In the case of emojis and other language character sets, a character
    (in UTF-8) can be between 1-4 bytes - when streaming logs for example
    it's quite easy to receive less than the whole character which can
    result in crashes or corrupt text.
    """
    @typep buffer :: [binary()]
    @typep chunk_state :: {bitstring(), bitstring()}

    @type t :: {buffer :: buffer(), chunk_state :: chunk_state()}

    @spec new() :: t()
    def new do
      {[], {"", ""}}
    end

    @spec buffer(state :: StringBuffer.t()) :: [binary()]
    def buffer({buffer, _}), do: buffer

    @spec process_chunk(data :: any(), state :: StringBuffer.t()) ::
            {binary() | nil, StringBuffer.t()}
    def process_chunk(data, {buffer, chunk_state}) do
      reduce_chunk(data, chunk_state)
      |> case do
        {nil, chunk_state} ->
          {nil, {buffer, chunk_state}}

        {chunk, {"", pending_chunks}} ->
          {chunk, {buffer ++ [chunk], {"", pending_chunks}}}
      end
    end

    @spec reduce_chunk(data :: any(), chunk_state :: chunk_state()) ::
            {binary() | nil, chunk_state()}
    def reduce_chunk(data, {partial, pending}) do
      next = pending <> data

      Enum.reduce_while(
        0..byte_size(next),
        {partial, String.next_grapheme(next)},
        fn _, {chunk, grapheme_result} ->
          maybe_merge_grapheme(chunk, grapheme_result)
        end
      )
    end

    defp merge_grapheme_result(chunk, {next_char, rest}) do
      {chunk <> IO.iodata_to_binary(next_char),
       String.next_grapheme(rest) || {"", ""}}
    end

    defp maybe_merge_grapheme(chunk, {next_char, rest}) do
      # char is utf-8
      if String.valid?(next_char) do
        {:cont, merge_grapheme_result(chunk, {next_char, rest})}
      else
        {:halt, {nil, {chunk, next_char <> rest}}}
      end
    end

    defp maybe_merge_grapheme(chunk, nil) do
      {:halt, {chunk, {"", ""}}}
    end
  end

  def start_link(_ \\ []) do
    Agent.start_link(&StringBuffer.new/0)
  end

  def buffer(agent) do
    Agent.get(agent, &StringBuffer.buffer/1)
  end

  def process_chunk(agent, {_type, data}) when is_pid(agent) do
    agent |> Agent.get_and_update(&StringBuffer.process_chunk(data, &1))
  end
end
