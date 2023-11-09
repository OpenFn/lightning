defmodule Lightning.Runtime.ChildProcess do
  @moduledoc """
  Provides an interface between a `RunSpec` and the shell.

  Internally it calls `node`, and more specifically the
  [OpenFn core](https://github.com/openfn/core) CLI.
  """
  alias Lightning.Runtime.{RunSpec, Result}
  require Logger

  def run(%RunSpec{} = runspec, opts \\ []) do
    command = build_command(runspec)

    Logger.debug(fn ->
      # coveralls-ignore-start
      "ChildProcess.run/2 called with #{inspect(runspec)}"
      # coveralls-ignore-stop
    end)

    env = build_env(runspec, opts[:env])

    rambo_opts =
      Keyword.merge(
        [timeout: nil, log: false],
        opts |> Keyword.take([:timeout, :log])
      )
      |> Keyword.put(:env, env)

    Logger.debug(fn ->
      # coveralls-ignore-start
      """
      env:
      #{Enum.map_join(rambo_opts[:env], " ", fn {k, v} -> "#{k}=#{v}" end)}
      cmd:
      #{command}
      """

      # coveralls-ignore-stop
    end)

    Rambo.run(
      "/usr/bin/env",
      ["sh", "-c", command],
      rambo_opts
    )
    |> case do
      {msg, %Rambo{} = res} ->
        {msg,
         Result.new(
           exit_reason: msg,
           log: String.split(res.out <> res.err, "\n"),
           final_state_path: runspec.final_state_path
         )}

      {:error, _} ->
        raise "Command failed to execute."
    end
  end

  @doc """
  Builds up a string for shell execution based on the RunSpec
  """
  @spec build_command(runspec :: RunSpec.t()) :: binary()
  def build_command(%RunSpec{} = runspec) do
    flags =
      [
        {"-a", runspec.adaptor},
        {"-s", runspec.state_path},
        {"--no-strict-output", nil},
        {"-l", "info"},
        if(runspec.final_state_path, do: {"-o", runspec.final_state_path}),
        {runspec.expression_path, nil}
      ]
      |> Enum.map(&to_shell_args/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" \\\n  ")

    ~s"""
    openfn execute \\
      #{flags}
    """
  end

  defp to_shell_args(nil), do: nil
  defp to_shell_args({key, nil}), do: key
  defp to_shell_args({key, value}), do: "#{key} #{value}"

  def build_env(%RunSpec{memory_limit: memory_limit}, env)
      when not is_nil(memory_limit) do
    %{"NODE_OPTIONS" => "--max-old-space-size=#{memory_limit}"}
    |> Map.merge(env || %{})
  end

  def build_env(_runspec, env), do: env
end
