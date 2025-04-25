defmodule ReplicatedRateLimiterTest do
  use ExUnit.Case, async: false
  import Eventually
  require Logger

  # Setup to log and ensure proper cleanup
  # setup do
  #   Logger.info("Starting new test")

  #   on_exit(fn ->
  #     Logger.info("Test completed, cleaning up")

  #     # Let's explicitly clean up supervised processes
  #     Supervisor.which_children(ReplicatedRateLimiterTest.CrdtEts)
  #     |> Enum.each(fn {id, pid, _, _} ->
  #       Logger.info("Terminating child #{inspect(id)} with pid #{inspect(pid)}")
  #       Process.exit(pid, :shutdown)
  #     end)

  #     Supervisor.which_children(ReplicatedRateLimiterTest.AnotherRateLimiter)
  #     |> Enum.each(fn {id, pid, _, _} ->
  #       Logger.info("Terminating child #{inspect(id)} with pid #{inspect(pid)}")
  #       Process.exit(pid, :shutdown)
  #     end)

  #     :ok
  #   end)

  #   :ok
  # end

  defmodule CrdtEts do
    use ReplicatedRateLimiter,
      default_capacity: 1_000,
      default_refill: 200
  end

  defmodule AnotherRateLimiter do
    use ReplicatedRateLimiter
  end

  test "CrdtEts allows calls directly from the main module" do
    start_link_supervised!(CrdtEts)


    config = CrdtEts.config() |> IO.inspect(label: "config") |> Map.new()

    # Test using the main module's allow? function
    result = CrdtEts.allow?("test_key")
    assert match?({:allow, 999}, result)

    before = System.system_time(:second)

    # Make several calls to hit the limit
    Enum.each(1..10, fn _ -> CrdtEts.allow?("test_key_2", 5, 1) end)

    assert {0, last_updated} =
             DeltaCrdt.get(config.crdt_name, {"test_key_2", "#{Node.self()}"}),
           "CRDT should have 0 tokens"

    assert {0, ^last_updated} =
             CrdtEts.inspect("test_key_2"),
           "ETS should be the same as CRDT"

    assert before <= last_updated

    # This should be denied since we consumed all tokens
    assert {:deny, 1000} = CrdtEts.allow?("test_key_2", 5, 1)

    # Another node enters the dungeon
    {:ok, test_crdt} =
      DeltaCrdt.start_link(DeltaCrdt.AWLWWMap)

    DeltaCrdt.set_neighbours(config.crdt_name, [test_crdt])
    DeltaCrdt.set_neighbours(test_crdt, [config.crdt_name])

    # and updates the bucket
    DeltaCrdt.put(
      test_crdt,
      {"test_key_2", "another_node"},
      {10, System.system_time(:second) + 1}
    )

    # Wait for the bucket to be updated
    assert_eventually(
      CrdtEts.inspect("test_key_2")
      |> Tuple.to_list()
      |> List.first() == 10
    )

    assert {:allow, 4} = CrdtEts.allow?("test_key_2", 5, 1)

  end

  test "can start multiple rate limiters" do
    start_supervised!(AnotherRateLimiter)
    start_supervised!(CrdtEts)

  end
end
