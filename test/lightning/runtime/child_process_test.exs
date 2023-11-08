defmodule Lightning.Runtime.ChildProcessTest do
  use ExUnit.Case, async: true

  alias Lightning.Runtime.{RunSpec, ChildProcess}
  import Lightning.Runtime.TestUtil

  @tag skip: true
  test "works" do
    {:ok, %Rambo{}} =
      ChildProcess.run(%RunSpec{adaptors_path: "./", adaptor: ""})
  end

  test "allows a memory limit to be set" do
    run_spec = run_spec_fixture(memory_limit: "5")

    assert {:error, result} =
             ChildProcess.run(run_spec,
               env: %{"PATH" => "./priv/openfn/bin:#{System.get_env("PATH")}"}
             )

    assert result.exit_reason == :error

    assert String.contains?(Enum.join(result.log, "\n"), "heap out of memory")
  end
end
