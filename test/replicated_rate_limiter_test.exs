defmodule ReplicatedRateLimiterTest do
  use ExUnit.Case, async: false
  import Eventually

  defmodule CrdtEts do
    use ReplicatedRateLimiter,
      default_capacity: 1_000,
      default_refill: 200
  end

  defmodule AnotherRateLimiter do
    use ReplicatedRateLimiter
  end

  test "CrdtEts allows calls directly from the main module" do
    start_supervised!(CrdtEts)

    config = CrdtEts.config() |> Map.new()

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
             CrdtEts.to_list("test_key_2"),
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
      CrdtEts.to_list("test_key_2")
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
