defmodule Lightning.CLI do
  require Logger
  @config Application.compile_env(:lightning, CLI, child_process_mod: Rambo)

  defmodule Result do
    @type t :: %__MODULE__{
            start_time: integer(),
            end_time: integer(),
            logs: list(),
            status: integer()
          }

    defstruct start_time: nil, end_time: nil, logs: [], status: nil

    def new(data) when is_map(data) do
      struct!(__MODULE__, data)
    end

    def parse(result, extra \\ []) do
      new(%{
        logs: decode(result.out),
        status: result.status,
        start_time: extra[:start_time],
        end_time: extra[:end_time]
      })
    end

    def get_messages(%__MODULE__{logs: logs}) do
      logs
      |> Enum.reduce([], fn l, messages ->
        if Map.keys(l) == ["message"] do
          messages ++ l["message"]
        else
          messages
        end
      end)
    end

    defp decode(stdout) do
      stdout
      |> String.split("\n")
      |> Enum.filter(&String.match?(&1, ~r/^{.+}$/))
      |> Enum.map(&Jason.decode/1)
      |> Enum.map(fn
        {:ok, res} -> res
        {:error, _} -> nil
      end)
      |> Enum.reject(&is_nil/1)
    end
  end

  @spec execute(command :: String.t()) :: Result.t()
  def execute(command) do
    start_time = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    {_, result} = run("/usr/bin/env", ["sh", "-c", command], opts())

    end_time = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    Result.parse(
      result,
      start_time: start_time,
      end_time: end_time
    )
  end

  @spec metadata(state :: map(), adaptor_path :: String.t()) :: Result.t()
  def metadata(state, adaptor_path) when is_binary(adaptor_path) do
    state = Jason.encode_to_iodata!(state)

    execute(
      ~s(openfn metadata --log-json -S '#{state}' -a #{adaptor_path} --log debug)
    )
  end

  defp opts() do
    adaptors_path =
      Application.get_env(:lightning, :adaptor_service, [])
      |> Keyword.get(:adaptors_path)

    env = %{
      "NODE_PATH" => adaptors_path,
      "PATH" => "#{adaptors_path}/bin:#{System.get_env("PATH")}"
    }

    [timeout: nil, log: true, env: env]
  end

  defp run(command, args, opts) do
    log_command(command, args, opts)
    @config[:child_process_mod].run(command, args, opts)
  end

  defp log_command(command, args, opts) do
    Logger.debug(fn ->
      # coveralls-ignore-start
      """
      env:
      #{Enum.map_join(opts[:env], " ", fn {k, v} -> "#{k}=#{v}" end)}
      cmd:
      #{command} #{args}
      """

      # coveralls-ignore-stop
    end)
  end
end
