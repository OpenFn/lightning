defmodule Lightning.DistributedRateLimiterTest do
  @moduledoc false
  use ExUnit.Case

  alias Lightning.DistributedRateLimiter

  @default_capacity 10

  describe "check_rate/2" do
    test "allows up to the capacity and refills on multiple buckets" do
      initial_capacity = @default_capacity
      bucket1 = "project#{System.unique_integer()}"
      bucket2 = "project#{System.unique_integer()}"

      Enum.each(1..initial_capacity, fn i ->
        level = initial_capacity - i

        assert match?(
                 {:allow, ^level},
                 DistributedRateLimiter.check_rate(bucket1)
               )

        assert match?(
                 {:allow, ^level},
                 DistributedRateLimiter.check_rate(bucket2)
               )
      end)
    end

    test "denies after consuming the bucket" do
      initial_capacity = @default_capacity
      bucket1 = "project#{System.unique_integer()}"
      bucket2 = "project#{System.unique_integer()}"

      Enum.each(1..initial_capacity, fn i ->
        assert {:allow, level} = DistributedRateLimiter.check_rate(bucket1)
        assert level == initial_capacity - i
      end)

      assert {:allow, level} = DistributedRateLimiter.check_rate(bucket2)
      assert level == initial_capacity - 1

      assert {:deny, wait_ms} = DistributedRateLimiter.check_rate(bucket1) |> dbg
      assert 500 < wait_ms and wait_ms <= 1_000
    end

    # Synthetic cluster not working.
    # For testing use manual procedure:
    # 0. Disable Endpoint server
    # 1. Run node1 on one terminal: iex --sname node1@localhost --cookie hordecookie -S mix phx.server
    # 2. Run node2 on another terminal: iex --sname node2@localhost --cookie hordecookie -S mix phx.server
    # 3. Call Lightning.DistributedRateLimiter.inspect_table() on both iex and they show the same ets table process and node.
    @tag skip: true
    test "consumes the bucket remotely" do
      {:ok, peer, _node1, node2} = start_nodes(:node1, :node2, ~c"localhost")

      :rpc.call(node2, Application, :ensure_all_started, [:mix])
      :rpc.call(node2, Application, :ensure_all_started, [:lightning])

      # Copy current code paths to the peer node
      :rpc.call(node2, :code, :add_paths, [:code.get_path()])

      assert [
               {Lightning.DistributedSupervisor, :node1@localhost},
               {Lightning.DistributedSupervisor, :node2@localhost}
             ] = Horde.Cluster.members(Lightning.DistributedSupervisor)

      # initial_capacity = @default_capacity
      bucket = "project#{System.unique_integer()}"

      dbg(DistributedRateLimiter.check_rate(bucket))

      # dbg :rpc.block_call(node1, DistributedRateLimiter, :inspect, [DistributedRateLimiter])
      # dbg :rpc.block_call(node2, DistributedRateLimiter, :inspect, [DistributedRateLimiter])

      # Enum.each(1..initial_capacity-1, fn i ->
      #   assert {:allow, level} = :rpc.call(node2, DistributedRateLimiter, :check_rate, [bucket, 1])
      #   assert level == initial_capacity - i - 1
      # end)

      # assert {:deny, wait_ms} = DistributedRateLimiter.check_rate(bucket)
      # assert 0 < wait_ms and wait_ms < 1_000

      :peer.stop(peer)
    end
  end

  defp start_nodes(node1, node2, host) do
    # Start the main node
    node1_sname = :"#{node1}@#{host}"
    {:ok, _pid} = Node.start(node1_sname, :shortnames)
    true = Node.set_cookie(:delicious_cookie)
    cookie = Node.get_cookie() |> to_charlist()

    # Start the peer node
    {:ok, peer, node2_sname} =
      :peer.start(%{
        name: node2,
        host: host,
        cookie: cookie,
        args: [~c"-setcookie", cookie]
      })

    assert node2_sname in Node.list()

    {:ok, peer, node1_sname, node2_sname}
  end
end
