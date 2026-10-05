defmodule Lightning.OsProcessTest do
  use ExUnit.Case, async: true

  alias Lightning.OsProcess

  describe "run/3" do
    test "returns stdout and stderr separately, then removes the stderr file" do
      # The program's parent is the wrapper, whose arguments name the
      # directory holding the stderr file.
      assert {:ok, %{status: 0, out: out, err: "err\n"}} =
               OsProcess.run("sh", ["-c", "ps -o args= -p $PPID; echo err >&2"])

      assert [_, dir] = Regex.run(~r/--remove (\S+)/, out)
      refute File.exists?(dir)
    end

    test "merges stderr into stdout when asked" do
      assert {:ok, %{status: 0, out: "out\nerr\n", err: ""}} =
               OsProcess.run("sh", ["-c", "echo out; echo err >&2"],
                 stderr_to_stdout: true
               )
    end

    test "returns a non-zero exit status" do
      assert {:ok, %{status: 3}} = OsProcess.run("sh", ["-c", "exit 3"])
    end

    test "reports a program killed by a signal as 128 + the signal" do
      assert {:ok, %{status: 137}} = OsProcess.run("sh", ["-c", "kill -9 $$"])
    end

    @tag :tmp_dir
    test "passes cd and env to the program", %{tmp_dir: dir} do
      assert {:ok, %{status: 0, out: out}} =
               OsProcess.run("sh", ["-c", "echo $(pwd) $FOO"],
                 cd: dir,
                 env: %{"FOO" => "bar"}
               )

      assert out == "#{dir} bar\n"
    end

    test "returns :enoent for a missing program" do
      assert {:error, :enoent} = OsProcess.run("definitely-not-a-program", [])
      assert {:error, :enoent} = OsProcess.run("/no/such/program", [])
    end

    test "kills processes the program spawned on timeout" do
      assert {:error, {:timeout, %{out: out}}} =
               OsProcess.run("sh", ["-c", "sleep 30 & echo $!; wait"],
                 timeout: 500
               )

      assert_dead(String.trim(out))
    end

    @tag :tmp_dir
    test "resolves a relative program against cd", %{tmp_dir: dir} do
      File.mkdir_p!(Path.join(dir, "bin"))
      script = Path.join(dir, "bin/hello")
      File.write!(script, "#!/bin/sh\necho hello\n")
      File.chmod!(script, 0o755)

      assert {:ok, %{status: 0, out: "hello\n"}} =
               OsProcess.run("./bin/hello", [], cd: dir)
    end

    @tag :tmp_dir
    test "looks the program up on the PATH given in env", %{tmp_dir: dir} do
      script = Path.join(dir, "only-on-this-path")
      File.write!(script, "#!/bin/sh\necho found\n")
      File.chmod!(script, 0o755)

      assert {:ok, %{status: 0, out: "found\n"}} =
               OsProcess.run("only-on-this-path", [],
                 env: %{"PATH" => "#{dir}:#{System.get_env("PATH")}"}
               )
    end

    test "returns the stderr so far on timeout" do
      assert {:error, {:timeout, %{err: "started\n"}}} =
               OsProcess.run("sh", ["-c", "echo started >&2; sleep 30"],
                 timeout: 500
               )
    end
  end

  describe "open/3" do
    test "returns the pid of a program that exits straight away" do
      assert {:ok, port, os_pid} = OsProcess.open("sh", ["-c", "exit 3"])
      assert is_integer(os_pid)
      assert_receive {^port, {:exit_status, 3}}, 2_000
    end

    test "kills the program when the owning process dies" do
      test_pid = self()

      owner =
        spawn(fn ->
          {:ok, port, _os_pid} =
            OsProcess.open("sh", ["-c", "echo $$; exec sleep 30"])

          receive do
            {^port, {:data, pid}} -> send(test_pid, {:child, String.trim(pid)})
          end

          Process.sleep(:infinity)
        end)

      assert_receive {:child, child_pid}, 2_000
      assert alive?(child_pid)

      Process.exit(owner, :kill)

      assert_dead(child_pid)
    end

    test "removes cleanup paths when the owning process dies" do
      dir = OsProcess.make_tmp_dir!()
      test_pid = self()

      owner =
        spawn(fn ->
          {:ok, _port, _os_pid} =
            OsProcess.open("sleep", ["30"], cleanup_paths: [dir])

          send(test_pid, :started)
          Process.sleep(:infinity)
        end)

      assert_receive :started
      Process.exit(owner, :kill)

      assert_eventually(fn -> not File.exists?(dir) end)
    end

    test "on SIGTERM, lets the program shut down, then removes cleanup paths" do
      dir = OsProcess.make_tmp_dir!()

      # The program checks the directory is still there mid-shutdown and
      # exits with its own status, which should reach the owner.
      {:ok, port, os_pid} =
        OsProcess.open(
          "sh",
          [
            "-c",
            "trap 'sleep 0.2; [ -d \"$0\" ] && echo kept; exit 7' TERM; " <>
              "echo ready; while :; do sleep 0.05; done",
            dir
          ],
          cleanup_paths: [dir]
        )

      assert_receive {^port, {:data, "ready\n"}}, 2_000
      System.cmd("kill", ["-TERM", "#{os_pid}"])

      assert_receive {^port, {:data, "kept\n"}}, 2_000
      assert_receive {^port, {:exit_status, 7}}, 2_000
      refute File.exists?(dir)
    end

    test "leaves cleanup paths to the owner when the program exits normally" do
      dir = OsProcess.make_tmp_dir!()
      on_exit(fn -> File.rm_rf(dir) end)

      {:ok, port, _os_pid} =
        OsProcess.open("sh", ["-c", "echo ready"], cleanup_paths: [dir])

      assert_receive {^port, {:exit_status, 0}}, 2_000

      # The port closing after exit is what the wrapper watches for, so
      # give a wrongly surviving watcher time to act.
      Process.sleep(200)
      assert File.dir?(dir)
    end
  end

  describe "port_wrapper" do
    test "holds the program back until the owner sends a line" do
      port =
        Port.open(
          {:spawn_executable, OsProcess.wrapper()},
          [:binary, :exit_status, args: ["--", "/bin/sh", "-c", "echo started"]]
        )

      refute_receive {^port, _}, 500
      assert {:os_pid, _} = Port.info(port, :os_pid)

      Port.command(port, "\n")
      assert_receive {^port, {:data, "started\n"}}, 2_000
      assert_receive {^port, {:exit_status, 0}}, 2_000
    end
  end

  describe "make_tmp_dir!/0" do
    test "creates a directory only this user can enter" do
      dir = OsProcess.make_tmp_dir!()
      on_exit(fn -> File.rm_rf(dir) end)

      assert Bitwise.band(File.stat!(dir).mode, 0o777) == 0o700
    end
  end

  describe "sweep_tmp_dirs/1" do
    test "removes old temporary directories and keeps recent ones" do
      old = OsProcess.make_tmp_dir!()
      recent = OsProcess.make_tmp_dir!()

      other =
        Path.join(
          System.tmp_dir!(),
          "not-ours-#{System.unique_integer([:positive])}"
        )

      File.mkdir!(other)
      on_exit(fn -> Enum.each([old, recent, other], &File.rm_rf/1) end)

      File.touch!(old, System.os_time(:second) - 7200)
      File.touch!(other, System.os_time(:second) - 7200)

      assert :ok = OsProcess.sweep_tmp_dirs(3600)

      refute File.exists?(old)
      assert File.dir?(recent)
      assert File.dir?(other)
    end
  end

  defp assert_dead(os_pid, attempts \\ 20) do
    assert os_pid =~ ~r/^\d+$/, "expected an OS pid, got #{inspect(os_pid)}"

    cond do
      not alive?(os_pid) ->
        :ok

      attempts == 0 ->
        flunk("process #{os_pid} is still running")

      true ->
        Process.sleep(50)
        assert_dead(os_pid, attempts - 1)
    end
  end

  defp assert_eventually(fun, attempts \\ 40) do
    cond do
      fun.() -> :ok
      attempts == 0 -> flunk("condition never became true")
      true -> Process.sleep(50) && assert_eventually(fun, attempts - 1)
    end
  end

  defp alive?(os_pid) do
    {_, status} = System.cmd("kill", ["-0", os_pid], stderr_to_stdout: true)
    status == 0
  end
end
