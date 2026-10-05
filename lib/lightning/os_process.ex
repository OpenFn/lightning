defmodule Lightning.OsProcess do
  @moduledoc """
  Runs external programs through `priv/runtime/port_wrapper`, which SIGKILLs
  the program's whole process group when its stdin closes. Closing the port,
  or the owning process exiting, takes the program and anything it spawned
  down with it, so nothing outlives its owner.

  Arguments are passed straight to the program; there is no shell. The
  program's stdout is the port's output and nothing else: stderr stays
  separate unless `:stderr_to_stdout` is given.

  Options:

    * `:cd` - working directory
    * `:env` - map or list of `{name, value}` string pairs; a `nil` value
      unsets the variable
    * `:cleanup_paths` - paths the wrapper deletes if the owner goes away
      before the program finishes. On a normal exit the owner is still
      around and removes them itself.
    * `:line` - deliver output as `{:eol | :noeol, data}` lines of at most
      this many bytes (`open/3` only)
    * `:stderr` - file to write the program's stderr to (`open/3` only;
      `run/3` captures it into `err`). Without it or `:stderr_to_stdout`,
      stderr goes to the BEAM's own stderr.
    * `:stderr_to_stdout` - merge stderr into the output
    * `:timeout` - milliseconds before `run/3` kills the program (default
      `:infinity`)
  """

  @type result :: %{status: non_neg_integer(), out: binary(), err: binary()}

  @tmp_prefix "lightning-os-process-"

  @doc """
  Starts the program and returns the port, which the caller owns and receives
  `{port, {:data, _}}` and `{port, {:exit_status, _}}` messages from.
  """
  @spec open(String.t(), [String.t()], keyword()) ::
          {:ok, port(), non_neg_integer()} | {:error, :enoent | :exited}
  def open(cmd, args, opts \\ []) do
    {wrapper_opts, opts} = Keyword.split(opts, [:cleanup_paths, :stderr])

    with {:ok, exe} <- find_executable(cmd, opts) do
      port =
        Port.open(
          {:spawn_executable, wrapper()},
          [
            :binary,
            :exit_status,
            :use_stdio,
            :hide,
            args:
              Enum.flat_map(wrapper_opts, &wrapper_arg/1) ++ ["--", exe | args]
          ] ++ Enum.flat_map(opts, &port_opt/1)
        )

      release(port)
    end
  end

  # The wrapper holds the program back until it reads a newline, so a program
  # that exits straight away can't close the port before its pid is read. The
  # wrapper itself can still die first (bash missing, killed from outside).
  defp release(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} ->
        Port.command(port, "\n")
        {:ok, port, os_pid}

      nil ->
        {:error, :exited}
    end
  rescue
    ArgumentError -> {:error, :exited}
  end

  @doc """
  Runs the program to completion and returns its exit status, stdout and
  stderr. On timeout the program is killed and the output so far is returned.
  """
  @spec run(String.t(), [String.t()], keyword()) ::
          {:ok, result()}
          | {:error, :enoent | :exited}
          | {:error, {:timeout, %{out: binary(), err: binary()}}}
  def run(cmd, args, opts \\ []) do
    {timeout, opts} = Keyword.pop(opts, :timeout, :infinity)
    opts = Keyword.drop(opts, [:line, :stderr])

    if opts[:stderr_to_stdout] do
      with {:ok, port, _os_pid} <- open(cmd, args, opts) do
        collect(port, [], deadline(timeout), nil)
      end
    else
      dir = make_tmp_dir!()
      err_path = Path.join(dir, "stderr")

      opts =
        opts
        |> Keyword.put(:stderr, err_path)
        |> Keyword.update(:cleanup_paths, [dir], &[dir | &1])

      try do
        with {:ok, port, _os_pid} <- open(cmd, args, opts) do
          collect(port, [], deadline(timeout), err_path)
        end
      after
        File.rm_rf(dir)
      end
    end
  end

  @doc """
  Creates a new directory only this OS user can enter, for files that belong
  to one program run. Pass it in `:cleanup_paths` and remove it when done;
  `sweep_tmp_dirs/1` catches any left behind by a crash.
  """
  @spec make_tmp_dir!() :: Path.t()
  def make_tmp_dir! do
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    dir = Path.join(System.tmp_dir!(), @tmp_prefix <> suffix)

    # mkdir fails if the path exists, so nobody can plant a directory or
    # symlink here first; it is empty until the chmod makes it private.
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)

    # Under a permissive umask the directory is open to others until the
    # chmod, and anything planted there in that window survives it.
    if File.ls!(dir) != [] do
      File.rm_rf!(dir)

      raise File.Error,
        reason: :eexist,
        action: "make private directory",
        path: dir
    end

    dir
  end

  @doc """
  Removes directories made by `make_tmp_dir!/0` that are older than
  `max_age_seconds`. They are only left behind when the wrapper itself was
  SIGKILLed or the host went down, so this runs once at boot.
  """
  @spec sweep_tmp_dirs(non_neg_integer()) :: :ok
  def sweep_tmp_dirs(max_age_seconds \\ 3600) do
    tmp = System.tmp_dir() || "/tmp"
    cutoff = System.os_time(:second) - max_age_seconds

    names =
      case File.ls(tmp) do
        {:ok, names} -> names
        {:error, _} -> []
      end

    for name <- names,
        String.starts_with?(name, @tmp_prefix),
        path = Path.join(tmp, name),
        {:ok, %File.Stat{type: :directory, mtime: mtime}} <-
          [File.lstat(path, time: :posix)],
        mtime < cutoff do
      File.rm_rf(path)
    end

    :ok
  end

  defp collect(port, out, deadline, err_path) do
    receive do
      {^port, {:data, data}} ->
        collect(port, [out | data], deadline, err_path)

      {^port, {:exit_status, status}} ->
        out = IO.iodata_to_binary([out | drain(port)])
        {:ok, %{status: status, out: out, err: read_err(err_path)}}
    after
      remaining(deadline) ->
        # Read stderr before closing: closing makes the wrapper delete it.
        err = read_err(err_path)
        Port.close(port)
        out = IO.iodata_to_binary([out | drain(port)])

        receive do
          {^port, {:exit_status, _}} -> :ok
        after
          0 -> :ok
        end

        {:error, {:timeout, %{out: out, err: err}}}
    end
  end

  defp read_err(nil), do: ""

  defp read_err(path) do
    case File.read(path) do
      {:ok, err} -> err
      {:error, _} -> ""
    end
  end

  defp drain(port) do
    receive do
      {^port, {:data, data}} -> [data | drain(port)]
    after
      0 -> []
    end
  end

  defp deadline(:infinity), do: :infinity

  defp deadline(timeout) when is_integer(timeout),
    do: System.monotonic_time(:millisecond) + timeout

  defp remaining(:infinity), do: :infinity

  defp remaining(deadline),
    do: max(deadline - System.monotonic_time(:millisecond), 0)

  # Resolved the way a shell would from inside `:cd` with `:env` applied, so
  # a relative path or an overridden PATH behaves as it did under `sh -c`.
  defp find_executable(cmd, opts) do
    path =
      cond do
        Path.type(cmd) == :absolute ->
          cmd

        String.contains?(cmd, "/") ->
          Path.expand(cmd, opts[:cd] || File.cwd!())

        search_path = env_path(opts[:env]) ->
          :os.find_executable(to_charlist(cmd), to_charlist(search_path))
          |> then(&(&1 && to_string(&1)))

        true ->
          System.find_executable(cmd)
      end

    if path && File.regular?(path), do: {:ok, path}, else: {:error, :enoent}
  end

  defp env_path(nil), do: nil

  defp env_path(env) do
    Enum.find_value(env, fn
      {"PATH", path} when is_binary(path) -> path
      _ -> nil
    end)
  end

  @doc false
  def wrapper, do: Application.app_dir(:lightning, "priv/runtime/port_wrapper")

  defp wrapper_arg({:stderr, path}), do: ["--stderr", path]

  defp wrapper_arg({:cleanup_paths, paths}),
    do: Enum.flat_map(paths, &["--remove", &1])

  defp port_opt({:cd, dir}), do: [cd: dir]
  defp port_opt({:line, n}), do: [line: n]
  defp port_opt({:stderr_to_stdout, true}), do: [:stderr_to_stdout]
  defp port_opt({:stderr_to_stdout, false}), do: []

  defp port_opt({:env, env}) do
    [
      env:
        Enum.map(env, fn
          {k, nil} -> {String.to_charlist(k), false}
          {k, v} -> {String.to_charlist(k), String.to_charlist(v)}
        end)
    ]
  end
end
