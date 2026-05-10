defmodule Mix.Tasks.Lightning.InstallRuntime do
  @shortdoc "Install the essential NodeJS packages for running expressions/jobs"

  @moduledoc """
  Installs the following NodeJS packages:

  - cli
  - language-common
  """

  use Mix.Task

  @default_path "priv/openfn"
  @cli_version "1.35.2"

  def run(args) do
    Rambo.run("/usr/bin/env", ~w(which node))
    |> case do
      {:error, %{status: 1}} ->
        raise "Couldn't find node in the local environment."

      _ ->
        nil
    end

    File.mkdir_p(@default_path)
    |> case do
      {:error, reason} ->
        raise "Couldn't create the runtime directory: #{@default_path}, got :#{reason}."

      _ ->
        nil
    end

    package_list = packages(args) |> Enum.join(" ")

    Rambo.run(
      "/usr/bin/env",
      ["sh", "-c", "npm install --prefix $NODE_PATH --global #{package_list}"],
      log: true,
      env: %{"NODE_PATH" => @default_path}
    )
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
