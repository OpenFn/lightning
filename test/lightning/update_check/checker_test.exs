defmodule Lightning.UpdateCheck.CheckerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Lightning.UpdateCheck.Checker

  defp start_checker(check_fun) do
    start_supervised!(
      {Checker,
       name: nil,
       check_fun: check_fun,
       interval: :timer.hours(1),
       initial_delay: :timer.hours(1)}
    )
  end

  test "status is nil until a check completes, then holds the result" do
    checker = start_checker(fn -> {:ok, %{latest: "2.19.2"}} end)

    assert Checker.status(checker) == nil
    assert Checker.check_now(checker) == {:ok, %{latest: "2.19.2"}}
    assert Checker.status(checker) == %{latest: "2.19.2"}
  end

  test "a failed check keeps the previous result" do
    {:ok, results} =
      Agent.start_link(fn -> [{:ok, %{latest: "1"}}, {:error, :boom}] end)

    checker =
      start_checker(fn ->
        Agent.get_and_update(results, fn [next | rest] -> {next, rest} end)
      end)

    assert {:ok, _} = Checker.check_now(checker)

    log =
      capture_log(fn ->
        assert Checker.check_now(checker) == {:error, :boom}
      end)

    assert log =~ "Update check failed: :boom"
    assert Checker.status(checker) == %{latest: "1"}
  end

  test "a check that raises is reported as an error" do
    checker = start_checker(fn -> raise "nope" end)

    capture_log(fn ->
      assert {:error, %RuntimeError{message: "nope"}} =
               Checker.check_now(checker)
    end)

    assert Process.alive?(checker)
  end

  test "status answers while a check is in flight" do
    test = self()

    checker =
      start_checker(fn ->
        send(test, :checking)
        receive do: (:go -> {:ok, %{latest: "2"}})
      end)

    send(checker, :check)
    assert_receive :checking
    assert Checker.status(checker) == nil
  end

  test "status is nil and check_now is disabled when no checker runs" do
    assert Checker.status(:no_such_checker) == nil
    assert Checker.check_now(:no_such_checker) == {:error, :disabled}
  end
end
