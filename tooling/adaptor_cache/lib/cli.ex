defmodule AdaptorCache.Cli do
  @moduledoc "Command dispatch for `bin/adaptor_cache`."

  alias AdaptorCache.Cache
  alias AdaptorCache.Publish
  alias AdaptorCache.Scenario

  def main(argv, script: script) do
    ctx = %{
      script: script,
      port: System.get_env("ADAPTOR_CACHE_PORT", "4874"),
      pidfile: Path.join(Cache.run_dir(), "adaptor_cache.pid"),
      logfile: Path.join(Cache.run_dir(), "adaptor_cache.log")
    }

    dispatch(argv, ctx)
  end

  defp dispatch(["up"], ctx),
    do: up(ctx.script, ctx.port, ctx.pidfile, ctx.logfile)

  defp dispatch(["down"], ctx), do: down(ctx.pidfile)
  defp dispatch(["status"], ctx), do: status(ctx.pidfile, ctx.port)
  defp dispatch(["logs"], ctx), do: logs(ctx.logfile)
  defp dispatch(["purge"], _ctx), do: purge()
  defp dispatch(["check"], ctx), do: check(ctx.port)
  defp dispatch(["publish", name, version], _ctx), do: publish(name, version)
  defp dispatch(["scenario", "save", name], _ctx), do: scenario(:save, name)

  defp dispatch(["scenario", "restore", name], _ctx),
    do: scenario(:restore, name)

  defp dispatch(["_serve", port], _ctx), do: serve(String.to_integer(port))
  defp dispatch([], _ctx), do: help()
  defp dispatch(["help"], _ctx), do: help()
  defp dispatch(["--help"], _ctx), do: help()
  defp dispatch(argv, _ctx), do: unknown(argv)

  # --- lifecycle -------------------------------------------------------

  defp up(script, port, pidfile, logfile) do
    if alive?(pidfile) do
      IO.puts("adaptor_cache: already up on #{base_url(port)}")
    else
      File.mkdir_p!(Cache.run_dir())

      elixir_bin =
        System.find_executable("elixir") || raise "elixir not found on PATH"

      # setsid isn't part of the base install on macOS (it ships with
      # util-linux, Linux-only) — fall back to plain nohup there. Detaching
      # stdin/stdout/stderr already covers surviving a closed terminal;
      # setsid additionally detaches the process group, which only matters
      # for a parent shell that sends SIGHUP to its whole group on exit.
      detach =
        if System.find_executable("setsid"), do: "setsid nohup", else: "nohup"

      cmd = """
      #{detach} "#{elixir_bin}" "#{script}" _serve #{port} > "#{logfile}" 2>&1 < /dev/null &
      echo $! > "#{pidfile}"
      """

      case System.shell(cmd) do
        {_, 0} ->
          :ok

        {output, status} ->
          IO.puts(
            :stderr,
            "adaptor_cache: failed to launch (exit #{status}): #{output}"
          )

          System.halt(1)
      end

      cond do
        not wait_for_healthz(port) ->
          IO.puts(
            :stderr,
            "adaptor_cache: did not come up on #{base_url(port)} after 30s."
          )

          IO.puts(
            :stderr,
            "adaptor_cache: run 'bin/adaptor_cache logs' to see why."
          )

          System.halt(1)

        not alive?(pidfile) ->
          # healthz answered, but not from the process we just spawned —
          # something else (a stray daemon from an earlier crash, or an
          # unrelated process) already holds the port.
          IO.puts(
            :stderr,
            "adaptor_cache: #{base_url(port)} is reachable, but not from a process this command started."
          )

          IO.puts(
            :stderr,
            "adaptor_cache: something else is bound to port #{port} — set ADAPTOR_CACHE_PORT to another value, or stop it."
          )

          System.halt(1)

        true ->
          IO.puts("adaptor_cache: up on #{base_url(port)}")
      end
    end

    print_exports(port)
  end

  defp down(pidfile) do
    case read_pid(pidfile) do
      nil ->
        IO.puts("adaptor_cache: not running.")

      pid ->
        System.cmd("kill", [pid], stderr_to_stdout: true)
        wait_for_exit(pid)
        File.rm(pidfile)

        IO.puts(
          "adaptor_cache: down. The cache on disk is intact; 'purge' clears it."
        )
    end
  end

  # Gives the OS a moment to actually release the port before we return, so
  # a following `up` doesn't race the still-shutting-down old process.
  defp wait_for_exit(pid) do
    Enum.reduce_while(1..20, :ok, fn _, _ ->
      if match?({_, 0}, System.cmd("kill", ["-0", pid], stderr_to_stdout: true)) do
        Process.sleep(250)
        {:cont, :ok}
      else
        {:halt, :ok}
      end
    end)
  end

  defp status(pidfile, port) do
    if alive?(pidfile) do
      IO.puts("adaptor_cache: running (pid #{read_pid(pidfile)})")
    else
      IO.puts("adaptor_cache: not running")
    end

    if healthz?(port) do
      IO.puts("adaptor_cache: reachable at #{base_url(port)}")
    else
      IO.puts("adaptor_cache: NOT reachable at #{base_url(port)}")
    end
  end

  defp logs(logfile) do
    if File.exists?(logfile) do
      System.cmd("tail", ["-f", "-n", "100", logfile],
        into: IO.stream(:stdio, :line)
      )
    else
      IO.puts(
        "adaptor_cache: no log file yet at #{logfile} — has it been started?"
      )
    end
  end

  defp purge do
    Cache.purge()
    IO.puts("adaptor_cache: cache cleared. Next request re-fetches live.")
  end

  defp serve(port) do
    {:ok, _} =
      Bandit.start_link(
        plug: AdaptorCache.Router,
        port: port,
        ip: {127, 0, 0, 1}
      )

    Process.sleep(:infinity)
  end

  # --- publish / scenario -----------------------------------------------

  defp publish(name, version) do
    case Publish.run(name, version) do
      :ok ->
        IO.puts(
          "adaptor_cache: published #{name}@#{version} (packument + search response updated)."
        )

      {:error, reason} ->
        IO.puts(:stderr, "adaptor_cache: #{reason}")
        System.halt(1)
    end
  end

  defp scenario(:save, name) do
    case Scenario.save(name) do
      :ok ->
        IO.puts("adaptor_cache: saved scenario #{inspect(name)}.")

      {:error, reason} ->
        IO.puts(:stderr, "adaptor_cache: #{reason}")
        System.halt(1)
    end
  end

  defp scenario(:restore, name) do
    case Scenario.restore(name) do
      :ok ->
        IO.puts("adaptor_cache: restored scenario #{inspect(name)}.")

      {:error, reason} ->
        IO.puts(:stderr, "adaptor_cache: #{reason}")
        System.halt(1)
    end
  end

  # --- check -------------------------------------------------------------

  defp check(port) do
    base = base_url(port)

    unless healthz?(port) do
      IO.puts(
        :stderr,
        "adaptor_cache: not running. Start it with 'bin/adaptor_cache up'."
      )

      System.halt(1)
    end

    IO.puts("adaptor_cache: probing all three prefixes twice each\n")

    results = [
      # %40, not a literal @: matches the wire query Tesla's default query
      # encoding actually sends (see AdaptorCache.Publish), so this probe
      # exercises the same cache key `publish` and real traffic use.
      probe("npm", base <> "/npm/-/v1/search?text=%40openfn&size=250"),
      probe(
        "jsdelivr",
        base <> "/jsdelivr/npm/@openfn/language-common/package.json"
      ),
      probe(
        "github",
        base <> "/github/OpenFn/adaptors/main/packages/common/assets/square.png"
      )
    ]

    IO.puts("")

    if Enum.all?(results, & &1) do
      IO.puts("adaptor_cache: check passed — all three prefixes cache.")
    else
      IO.puts(:stderr, "adaptor_cache: check FAILED")
      System.halt(1)
    end
  end

  defp probe(label, url) do
    with {:ok, first} <- Req.get(url, decode_body: false),
         {:ok, second} <- Req.get(url, decode_body: false) do
      cache_2 =
        second.headers |> Map.get("x-cache-status", ["-"]) |> List.first()

      cache_1 = first.headers |> Map.get("x-cache-status", ["-"]) |> List.first()

      IO.puts(
        "  #{String.pad_trailing(label, 9)} #{first.status} first=#{cache_1} second=#{cache_2}  #{url}"
      )

      if cache_2 != "HIT" do
        IO.puts("            ^ expected the second request to be a HIT")
        false
      else
        true
      end
    else
      {:error, reason} ->
        IO.puts("  #{String.pad_trailing(label, 9)} FAIL  #{inspect(reason)}")
        false
    end
  end

  # --- helpers -------------------------------------------------------------

  defp base_url(port), do: "http://localhost:#{port}"

  defp print_exports(port) do
    base = base_url(port)

    IO.puts("""

    Point Lightning at the cache by exporting these:

      export ADAPTORS_NPM_REGISTRY_URL=#{base}/npm
      export ADAPTORS_NPM_JSDELIVR_URL=#{base}/jsdelivr
      export ADAPTORS_NPM_GITHUB_URL=#{base}/github

    Then: mix lightning.refresh_adaptors
    Watch it work:  bin/adaptor_cache logs
    Prove it works: bin/adaptor_cache check
    """)
  end

  defp wait_for_healthz(port) do
    Enum.reduce_while(1..30, false, fn _, _ ->
      if healthz?(port) do
        {:halt, true}
      else
        Process.sleep(1000)
        {:cont, false}
      end
    end)
  end

  defp healthz?(port) do
    case Req.get(base_url(port) <> "/_healthz",
           receive_timeout: 2_000,
           retry: false
         ) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp alive?(pidfile) do
    case read_pid(pidfile) do
      nil -> false
      pid -> running_and_ours?(pid)
    end
  end

  # kill -0 alone only proves the PID is alive, not that it's still our
  # daemon — after a crash the PID can be reused by an unrelated process.
  # `ps -o command=` (not /proc, which doesn't exist on macOS) catches that.
  defp running_and_ours?(pid) do
    case System.cmd("ps", ["-p", pid, "-o", "command="], stderr_to_stdout: true) do
      {output, 0} -> String.contains?(output, "adaptor_cache")
      _ -> false
    end
  end

  defp read_pid(pidfile) do
    case File.read(pidfile) do
      {:ok, pid} -> String.trim(pid)
      _ -> nil
    end
  end

  defp unknown(argv) do
    IO.puts(
      :stderr,
      "adaptor_cache: unknown command #{inspect(Enum.join(argv, " "))}\n"
    )

    help()
    System.halt(1)
  end

  defp help do
    IO.puts("""
    Lightning Adaptor Cache

    A local record-and-replay reverse proxy in front of the three upstreams
    the Lightning.Adaptors.* subsystem reads from: registry.npmjs.org,
    cdn.jsdelivr.net and raw.githubusercontent.com. See
    tooling/adaptor_cache/README.md.

    Usage: bin/adaptor_cache <command>

      up                        Start the proxy and print the export lines
      down                      Stop the proxy, keeping the cache on disk
      status                    Show whether it's running and reachable
      purge                     Clear all recorded responses
      logs                      Tail the access log (cache=HIT / cache=MISS)
      check                     Probe all three prefixes, prove MISS then HIT
      publish <name> <version>  Record a synthetic adaptor/version
      scenario save <name>      Snapshot the live cache under that name
      scenario restore <name>   Replace the live cache with that snapshot
      --help                    This message

    Environment variables:

      ADAPTOR_CACHE_PORT   Host port to bind (default: 4874)
    """)
  end
end
