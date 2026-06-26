defmodule Mix.Tasks.Lightning.InstallRuntime do
  @shortdoc "Install the essential NodeJS packages for running expressions/jobs"

  @moduledoc """
  Installs the following NodeJS packages:

  - cli
  - language-common
  """

  use Mix.Task

  @default_path "priv/openfn"
  @cli_version "1.38.1"

  def run(args) do
    case Rambo.run("/usr/bin/env", ~w(which node)) do
      {:ok, _} ->
        :ok

      {:error, %Rambo{status: 1}} ->
        raise "Couldn't find node in the local environment."

      {:error, reason} ->
        raise """
        Failed to invoke Rambo while checking for node: #{inspect(reason)}

        The rambo binary may be missing or not executable. On architectures
        without a precompiled binary (e.g. aarch64/arm64), Rust is required
        so rambo can be built from source. See ./bin/bootstrap output.
        """
    end

    File.mkdir_p(@default_path)
    |> case do
      {:error, reason} ->
        raise "Couldn't create the runtime directory: #{@default_path}, got :#{reason}."

      _ ->
        nil
    end

    package_list = packages(args) |> Enum.join(" ")

    case Rambo.run(
           "/usr/bin/env",
           [
             "sh",
             "-c",
             "npm install --prefix $NODE_PATH --global #{package_list}"
           ],
           log: true,
           env: %{"NODE_PATH" => @default_path}
         ) do
      {:ok, result} ->
        result

      {:error, %Rambo{status: status, err: err}} ->
        raise "npm install failed (status #{status}): #{err}"

      {:error, reason} ->
        raise "Failed to invoke Rambo for npm install: #{inspect(reason)}"
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
