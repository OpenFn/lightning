defmodule LightningWeb.WorkerPresenceTest do
  use LightningWeb.ChannelCase, async: false

  alias LightningWeb.WorkerPresence

  describe "track_worker/3" do
    test "tracks a worker with given capacity" do
      {:ok, _ref} = WorkerPresence.track_worker(self(), "worker-1", 5)

      # Give presence a moment to sync
      Process.sleep(50)

      assert WorkerPresence.total_worker_capacity() == 5
    end

    test "tracks multiple workers with different capacities" do
      pid1 = spawn(fn -> Process.sleep(1000) end)
      pid2 = spawn(fn -> Process.sleep(1000) end)

      {:ok, _ref1} = WorkerPresence.track_worker(pid1, "worker-1", 3)
      {:ok, _ref2} = WorkerPresence.track_worker(pid2, "worker-2", 7)

      # Give presence a moment to sync
      Process.sleep(50)

      assert WorkerPresence.total_worker_capacity() == 10

      # Clean up
      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end

    test "handles worker with zero capacity" do
      {:ok, _ref} = WorkerPresence.track_worker(self(), "worker-1", 0)

      # Give presence a moment to sync
      Process.sleep(50)

      assert WorkerPresence.total_worker_capacity() == 0
    end
  end

  describe "total_worker_capacity/0" do
    test "returns 0 when no workers are present" do
      assert WorkerPresence.total_worker_capacity() == 0
    end

    test "sums capacity across all tracked workers" do
      pid1 = spawn(fn -> Process.sleep(1000) end)
      pid2 = spawn(fn -> Process.sleep(1000) end)
      pid3 = spawn(fn -> Process.sleep(1000) end)

      {:ok, _ref1} = WorkerPresence.track_worker(pid1, "worker-1", 2)
      {:ok, _ref2} = WorkerPresence.track_worker(pid2, "worker-2", 4)
      {:ok, _ref3} = WorkerPresence.track_worker(pid3, "worker-3", 6)

      # Give presence a moment to sync
      Process.sleep(50)

      assert WorkerPresence.total_worker_capacity() == 12

      # Clean up
      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
      Process.exit(pid3, :kill)
    end

    test "updates when workers disconnect" do
      pid1 = spawn(fn -> Process.sleep(1000) end)
      pid2 = spawn(fn -> Process.sleep(1000) end)

      {:ok, _ref1} = WorkerPresence.track_worker(pid1, "worker-1", 5)
      {:ok, _ref2} = WorkerPresence.track_worker(pid2, "worker-2", 3)

      # Give presence a moment to sync
      Process.sleep(50)

      assert WorkerPresence.total_worker_capacity() == 8

      # Disconnect one worker
      Process.exit(pid1, :kill)

      # Give presence a moment to sync
      Process.sleep(50)

      assert WorkerPresence.total_worker_capacity() == 3

      # Clean up
      Process.exit(pid2, :kill)
    end
  end
end
