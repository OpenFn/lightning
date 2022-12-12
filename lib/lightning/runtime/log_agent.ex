defmodule Lightning.Runtime.LogAgent do
  @type logline ::
          {timestamp :: integer(), type :: :stdout | :stderr, line :: binary()}

  defmodule LogState do
    @typep buffer :: [binary()]
    @typep chunk_state :: {bitstring(), bitstring()}

    @type t :: {buffer :: buffer(), chunk_state :: chunk_state()}

    @spec new() :: t()
    def new() do
      {[], {"", ""}}
    end

    @spec buffer(state :: LogState.t()) :: [binary()]
    def buffer({buffer, _}), do: buffer

    # @spec pending(state :: LogState.t()) :: [binary()]
    # def pending({{pending, _}, _}), do: pending

    @spec process_chunk(data :: any(), state :: LogState.t()) ::
            {binary() | nil, LogState.t()}
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
          case grapheme_result do
            # char is utf-8
            {next_char, rest} ->
              if String.valid?(next_char) do
                {:cont, merge_grapheme_result(chunk, {next_char, rest})}
              else
                {:halt, {nil, {chunk, next_char <> rest}}}
              end

            nil ->
              {:halt, {chunk, {"", ""}}}
          end
        end
      )
    end

    defp merge_grapheme_result(chunk, {next_char, rest}) do
      {chunk <> IO.iodata_to_binary(next_char),
       String.next_grapheme(rest) || {"", ""}}
    end
  end

  use Agent

  def start_link(_ \\ []) do
    Agent.start_link(&LogState.new/0)
  end

  def buffer(agent) do
    Agent.get(agent, &LogState.buffer/1)
  end

  def process_chunk(agent, {_type, data}) when is_pid(agent) do
    agent |> Agent.get_and_update(&LogState.process_chunk(data, &1))
  end
end
