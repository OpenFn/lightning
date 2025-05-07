defmodule Lightning.DistributedRateLimiterTest do
  @moduledoc false
  use ExUnit.Case

  alias Lightning.DistributedRateLimiter

  @default_capacity 10

  describe "inspect_table/0" do
    test "shows the process info of the ets" do
      %{table: table} =
        Horde.DynamicSupervisor.which_children(Lightning.DistributedSupervisor)
        |> then(fn [{:undefined, pid, :worker, _name}] ->
          :sys.get_state(pid)
        end)

      ets_info = :ets.info(table)
      assert ^ets_info = DistributedRateLimiter.inspect_table()
      assert Keyword.has_key?(ets_info, :node)
    end
  end

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

      assert {:deny, wait_ms} = DistributedRateLimiter.check_rate(bucket1)
      assert 500 < wait_ms and wait_ms <= 1_000
    end

    # Run this distributed integration test case separately to avoid interfering with the tests above.
    # For testing the replication use `bin/local_cluster` on the shell:
    # 1. In one shell run `./bin/local_cluster`
    # 2. On another shell run `./bin/local_cluster connect 2`
    # 3. Type `Lightning.DistributedRateLimiter.inspect_table()` to see that the ETS table is distributed
    # (on node1 or vice-versa if it was spawned on node2 when you connect to node 1).
    @tag :dist_integration
    test "works on top of a single worker of a distributed dynamic supervisor" do
      {:ok, peer, _node1, node2} = start_nodes(:node1, :node2, ~c"localhost")

      :rpc.call(node2, Application, :ensure_all_started, [:mix])
      :rpc.call(node2, Application, :ensure_all_started, [:lightning])

      # Copy current code paths to the peer node
      :rpc.call(node2, :code, :add_paths, [:code.get_path()])

      assert [
               {Lightning.DistributedSupervisor, :node1@localhost},
               {Lightning.DistributedSupervisor, :node2@localhost}
             ] = Horde.Cluster.members(Lightning.DistributedSupervisor)

      assert [{:undefined, _pid, :worker, [Lightning.DistributedRateLimiter]}] =
               Horde.DynamicSupervisor.which_children(
                 Lightning.DistributedSupervisor
               )

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
