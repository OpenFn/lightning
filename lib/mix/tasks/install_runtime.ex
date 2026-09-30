defmodule Mix.Tasks.Lightning.InstallRuntime do
  @shortdoc "Install the essential NodeJS packages for running expressions/jobs"

  @moduledoc """
  Installs the following NodeJS packages:

  - cli
  - language-common
  """

  use Mix.Task

  @default_path "priv/openfn"
  @cli_version "1.41.1"

  def run(args) do
    for exe <- ~w(node npm) do
      System.find_executable(exe) ||
        raise "Couldn't find #{exe} in the local environment."
    end

    File.mkdir_p(@default_path)
    |> case do
      {:error, reason} ->
        raise "Couldn't create the runtime directory: #{@default_path}, got :#{reason}."

      _ ->
        nil
    end

    case System.cmd(
           "npm",
           ["install", "--prefix", @default_path, "--global" | packages(args)],
           into: IO.stream(),
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {_, status} -> raise "npm install failed (status #{status})"
    end
  end

  def packages(args \\ []) do
    cli_version =
      case args do
        [version | _] when is_binary(version) -> version
        _ -> @cli_version
      end

    [
      "@openfn/cli@" <> cli_version,
      "@openfn/language-common@latest"
    ]
  end
end
