defmodule Lightning.Runtime.LogStream do
  defstruct log_agent: nil, line_or_bytes: :line

  require Logger

  def new do
    %__MODULE__{}
  end

  defimpl Collectable do
    def into(%{log_agent: agent, line_or_bytes: line_or_bytes} = stream) do
      {:ok, into(stream, agent, line_or_bytes)}
    end

    defp into(stream, _agent, :line) do
      fn
        _acc, {:cont, x} ->
          byte_size(x)
          |> IO.inspect(
            label: "Characters count ===============================> "
          )

          for line <- String.split(x, "\n", trim: true) do
            Logger.info(line)
          end

        _acc, _ ->
          stream
      end
    end
  end
end
