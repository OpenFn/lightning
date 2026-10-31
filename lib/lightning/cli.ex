defmodule Lightning.CLI do
  @moduledoc """
  Module providing facilities to make calls to the OpenFn CLI.

  See [@openfn/cli](https://github.com/OpenFn/kit/tree/main/packages/cli#openfncli)
  """
  require Logger

  @timeout :timer.minutes(2)

  defmodule Result do
    @moduledoc """
    Struct that wraps the output of an OpenFn CLI call.

    Containing the keys:

    - `start_time`
    - `end_time`
    - `status`
    - `logs`

    ## Logs

    The OpenFn CLI returns JSON formatted log lines, which are decoded and added
    to a `Result` struct.

    There are two kinds of output:

    ```
    {"level":"<<level>>","name":"<<module>>","message":"..."],"time":<<timestamp>>}
    ```

    These are usually for general logging, and debugging.

    ```
    {"message":["<<message|filepath|output>>"]}
    ```

    The above is the equivalent of the output of a command
    """
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

    @doc """
    Returns `message` type log lines from a `Result`.
    """
    @spec get_messages(Result.t()) :: [String.t()]
    def get_messages(%__MODULE__{logs: logs}) do
      logs
      |> Enum.filter(&Map.has_key?(&1, "message"))
      |> Enum.map(&Map.get(&1, "message"))
      |> List.flatten()
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

  @spec execute(command :: [String.t()], opts :: keyword()) ::
          {:ok, Result.t()} | {:error, :enoent | :timeout}
  defp execute(command, opts) when is_list(command) do
    start_time = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    Logger.debug(fn -> "cmd: openfn #{Enum.join(command, " ")}" end)

    case Lightning.OsProcess.run(
           "/usr/bin/env",
           ["openfn" | command],
           opts() ++ opts
         ) do
      {:ok, result} ->
        end_time = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

        if result.status != 0 do
          Logger.warning(
            "openfn #{List.first(command)} exited with status #{result.status}" <>
              stderr_excerpt(result.err)
          )
        end

        {:ok, Result.parse(result, start_time: start_time, end_time: end_time)}

      {:error, {:timeout, %{err: err}}} ->
        Logger.warning(
          "openfn #{List.first(command)} timed out after #{@timeout}ms and was killed" <>
            stderr_excerpt(err)
        )

        {:error, :timeout}

      {:error, :enoent} ->
        {:error, :enoent}
    end
  end

  # The CLI's JSON logs all go to stdout, so stderr only carries Node's own
  # output: crash traces, warnings, a missing binary.
  @stderr_excerpt_bytes 2_000

  defp stderr_excerpt(""), do: ""

  defp stderr_excerpt(err) do
    excerpt =
      if byte_size(err) > @stderr_excerpt_bytes,
        do: binary_part(err, 0, @stderr_excerpt_bytes) <> "…",
        else: err

    ", stderr: " <> String.trim(excerpt)
  end

  @doc """
  Retrieve metadata for a given adaptor and configuration.

  The state is handed to the CLI in a file inside a directory only this user
  can enter, rather than on the command line, where other processes could
  read it. The directory is private before the file exists, so there is no
  window where the file is readable by others.
  """
  @spec metadata(state :: map(), adaptor_path :: String.t()) ::
          {:ok, Result.t()} | {:error, :enoent | :timeout}
  def metadata(state, adaptor_path) when is_binary(adaptor_path) do
    dir = Lightning.OsProcess.make_tmp_dir!()
    state_path = Path.join(dir, "state.json")

    try do
      File.write!(state_path, Jason.encode!(state))

      execute(
        [
          "metadata",
          "--log-json",
          "-s",
          state_path,
          "-a",
          adaptor_path,
          "--log",
          "debug"
        ],
        cleanup_paths: [dir]
      )
    after
      File.rm_rf(dir)
    end
  end

  defp opts do
    adaptors_path =
      Application.get_env(:lightning, :adaptor_service, [])
      |> Keyword.get(:adaptors_path)

    [
      timeout: @timeout,
      env: %{
        "NODE_PATH" => adaptors_path,
        "PATH" => "#{adaptors_path}/bin:#{System.get_env("PATH")}"
      }
    ]
  end
end
