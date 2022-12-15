defmodule Lightning.Runtime.LogAgentTest do
  use ExUnit.Case, async: true

  alias Lightning.Runtime.LogAgent

  test "process_chunk/2" do
    {:ok, agent} = LogAgent.start_link()

    example = ~s[
      "national_id_no": "39-7008-858-6",
      "name_last": "มมซึฆเ",
      "name_first": "ศผ่องรี",
      "date_of_birth": "1969-02-16",
      "age": 52,
    ]

    example
    |> chunk_string(64)
    |> Enum.each(fn chunk ->
      LogAgent.process_chunk(agent, {:stdout, chunk})
    end)

    buffer = LogAgent.buffer(agent)
    assert length(buffer) == 2
    assert buffer |> Enum.join() == example

    Agent.stop(agent)

    {:ok, agent} = LogAgent.start_link()

    emoji_string = String.duplicate(".", 63) <> "💣"

    first_chunk =
      LogAgent.process_chunk(agent, {:stdout, binary_part(emoji_string, 0, 64)})

    second_chunk =
      LogAgent.process_chunk(agent, {:stdout, binary_part(emoji_string, 64, 3)})

    assert first_chunk == nil
    assert second_chunk == emoji_string

    Agent.stop(agent)
  end

  defp chunk_string(str, chunksize) do
    :binary.bin_to_list(str)
    |> Enum.chunk_every(chunksize)
    |> Enum.map(&:binary.list_to_bin/1)
  end
end
