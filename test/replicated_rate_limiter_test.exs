defmodule ReplicatedRateLimiterTest do
  use ExUnit.Case, async: false
  import Eventually

  defmodule CrdtEts do
    use ReplicatedRateLimiter,
      default_capacity: 10,
      default_refill: 2
  end

  defmodule AnotherRateLimiter do
    use ReplicatedRateLimiter
  end

  test "CrdtEts allows calls directly from the main module" do
    start_supervised!(CrdtEts)

    config = CrdtEts.config() |> Map.new()

    # Check one time (default cost is 1)
    assert match?({:allow, 9}, CrdtEts.allow?("project1"))

    before = System.system_time(:second)

    # Make several calls to hit the limit (default capacity is 10)
    Enum.each(1..9, fn _ -> CrdtEts.allow?("project2") end)

    assert_eventually(
      DeltaCrdt.get(config.crdt_name, {"project2", "#{Node.self()}"})
      |> dbg
      |> elem(0) == 0,
      1_000
    )

    assert {0, last_updated} =
             CrdtEts.to_list("project2"),
           "ETS should be the same as CRDT"

    assert before <= last_updated

    # This should be denied since we consumed all tokens
    assert {:deny, 1000} = CrdtEts.allow?("project2", 10, 2)

    # Node2 enters the dungeon
    {:ok, test_crdt} =
      DeltaCrdt.start_link(DeltaCrdt.AWLWWMap)

    DeltaCrdt.set_neighbours(config.crdt_name, [test_crdt])
    DeltaCrdt.set_neighbours(test_crdt, [config.crdt_name])

    # a time has passed and the bucket is refilled by Node2
    DeltaCrdt.put(
      test_crdt,
      {"project2", "another_node"},
      {10, System.system_time(:second)}
    )

    # Node2 consumes all the credits except one
    Enum.each(1..9, fn i ->
      DeltaCrdt.put(
        test_crdt,
        {"project2", "another_node"},
        {10 - i, System.system_time(:second)}
      )
    end)

    # Wait for the bucket to be updated
    assert_eventually(CrdtEts.to_list("project2") |> elem(0) == 1)

    assert {:allow, 4} = CrdtEts.allow?("project2", 10, 2)
  end

  test "can start multiple rate limiters" do
    start_supervised!(AnotherRateLimiter)
    start_supervised!(CrdtEts)
  end
end
