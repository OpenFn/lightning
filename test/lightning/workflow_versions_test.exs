defmodule Lightning.WorkflowVersionsTest do
  use Lightning.DataCase, async: true

  import Ecto.Query
  import Lightning.Factories

  alias Lightning.Repo
  alias Lightning.WorkflowVersions
  alias Lightning.Workflows.{Workflow, WorkflowVersion}

  @a "aaaaaaaaaaaa"
  @b "bbbbbbbbbbbb"
  @c "cccccccccccc"
  @d "dddddddddddd"

  defp count_rows(workflow_id) do
    from(v in WorkflowVersion, where: v.workflow_id == ^workflow_id)
    |> Repo.aggregate(:count, :id)
  end

  describe "record_version/3" do
    test "inserts a row and appends to workflow.version_history (idempotent)" do
      wf = insert(:workflow)

      assert {:ok, wf1} = WorkflowVersions.record_version(wf, @a, "app")
      assert wf1.version_history == [@a]
      assert count_rows(wf.id) == 1

      # same call again -> still one row; history unchanged
      assert {:ok, wf2} = WorkflowVersions.record_version(wf1, @a, "app")
      assert wf2.version_history == [@a]
      assert count_rows(wf.id) == 1

      # different hash -> appended
      assert {:ok, wf3} = WorkflowVersions.record_version(wf2, @b, "cli")
      assert wf3.version_history == [@a, @b]
      assert count_rows(wf.id) == 2
    end

    test "rejects invalid inputs" do
      wf = insert(:workflow)

      assert {:error, :invalid_input} =
               WorkflowVersions.record_version(wf, "NOTHEX12!!!!", "app")

      assert {:error, :invalid_input} =
               WorkflowVersions.record_version(wf, @a, "web")
    end
  end

  describe "record_versions/3 (bulk)" do
    test "deduplicates input, ignores preexisting rows, preserves order in version_history, returns inserted_count" do
      wf = insert(:workflow)

      # initial bulk with a duplicate in the list
      assert {:ok, wf1, inserted} =
               WorkflowVersions.record_versions(wf, [@a, @a, @b], "app")

      assert inserted == 2
      assert wf1.version_history == [@a, @b]
      assert count_rows(wf.id) == 2

      # bulk that mixes old and new; order preserved; only new counted
      assert {:ok, wf2, inserted2} =
               WorkflowVersions.record_versions(wf1, [@b, @c], "cli")

      assert inserted2 == 1
      assert wf2.version_history == [@a, @b, @c]
      assert count_rows(wf.id) == 3
    end

    test "invalid input returns {:error, :invalid_input}" do
      wf = insert(:workflow)

      assert {:error, :invalid_input} =
               WorkflowVersions.record_versions(wf, [@a, "NOTHEX"], "app")

      assert {:error, :invalid_input} =
               WorkflowVersions.record_versions(wf, [@a, @b], "nope")
    end
  end

  describe "history_for/1" do
    test "uses version_history array when present" do
      wf = insert(:workflow, version_history: [@a, @b])
      assert WorkflowVersions.history_for(wf) == [@a, @b]
    end

    test "falls back to table ordered by inserted_at, id when array empty" do
      wf = insert(:workflow, version_history: [])

      # Insert with deterministic inserted_at values
      t0 = DateTime.utc_now(:microsecond)
      t1 = DateTime.add(t0, 1, :microsecond)
      t2 = DateTime.add(t0, 2, :microsecond)

      rows = [
        %{workflow_id: wf.id, hash: @b, source: "app", inserted_at: t1},
        %{workflow_id: wf.id, hash: @a, source: "cli", inserted_at: t0},
        %{workflow_id: wf.id, hash: @c, source: "app", inserted_at: t2}
      ]

      Repo.insert_all(WorkflowVersion, rows)

      assert WorkflowVersions.history_for(wf) == [@a, @b, @c]
    end
  end

  describe "latest_hash/1" do
    test "uses List.last(version_history) when present" do
      wf = insert(:workflow, version_history: [@a, @b, @c])
      assert WorkflowVersions.latest_hash(wf) == @c
    end

    test "queries table when version_history empty; deterministic by inserted_at desc, id desc" do
      wf = insert(:workflow, version_history: [])

      t0 = DateTime.utc_now(:microsecond)
      t1 = DateTime.add(t0, 1, :microsecond)
      t2 = DateTime.add(t0, 2, :microsecond)

      rows = [
        %{workflow_id: wf.id, hash: @a, source: "app", inserted_at: t0},
        %{workflow_id: wf.id, hash: @b, source: "cli", inserted_at: t1},
        %{workflow_id: wf.id, hash: @c, source: "app", inserted_at: t2}
      ]

      Repo.insert_all(WorkflowVersion, rows)

      assert WorkflowVersions.latest_hash(wf) == @c
    end
  end

  describe "reconcile_history!/1" do
    test "rebuilds version_history from workflow_versions and persists it" do
      wf = insert(:workflow, version_history: [])

      t0 = DateTime.utc_now(:microsecond)
      t1 = DateTime.add(t0, 1, :microsecond)
      t2 = DateTime.add(t0, 2, :microsecond)

      Repo.insert_all(WorkflowVersion, [
        %{workflow_id: wf.id, hash: @a, source: "app", inserted_at: t0},
        %{workflow_id: wf.id, hash: @b, source: "cli", inserted_at: t1},
        %{workflow_id: wf.id, hash: @c, source: "app", inserted_at: t2}
      ])

      updated = WorkflowVersions.reconcile_history!(wf)
      assert updated.version_history == [@a, @b, @c]
      assert Repo.reload!(%Workflow{id: wf.id}).version_history == [@a, @b, @c]
    end
  end

  describe "classification helpers" do
    test "classify_with_delta and classify return expected shapes" do
      # same
      assert {:same, 0} =
               WorkflowVersions.classify_with_delta([@a, @b], [@a, @b])

      assert :same == WorkflowVersions.classify([@a], [@a])

      # right extends left
      assert {:ahead, :right, 1} =
               WorkflowVersions.classify_with_delta([@a], [@a, @b])

      assert {:ahead, :right} == WorkflowVersions.classify([@a], [@a, @b])

      # left extends right
      assert {:ahead, :left, 2} =
               WorkflowVersions.classify_with_delta([@a, @b, @c], [@a])

      assert {:ahead, :left} ==
               WorkflowVersions.classify([@a, @b], [@a])

      # diverged
      assert {:diverged, 1} =
               WorkflowVersions.classify_with_delta([@a, @b], [@a, @c])

      assert :diverged == WorkflowVersions.classify([@a, @b], [@a, @c, @d])
    end
  end

  describe "concurrency safety (no duplicate append under contention)" do
    test "many concurrent record_version calls append only once and insert one row" do
      wf = insert(:workflow, version_history: [])

      # spawn N tasks that block on a :go message, then all call record_version
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            receive do
              :go -> WorkflowVersions.record_version(wf, @a, "app")
            end
          end)
        end

      # Allow sandbox access for each task, then release them simultaneously
      Enum.each(tasks, fn %Task{pid: pid} ->
        Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
      end)

      Enum.each(tasks, fn %Task{pid: pid} -> send(pid, :go) end)
      results = Enum.map(tasks, &Task.await(&1, 5_000))

      # All calls either {:ok, %Workflow{}} or {:error, ...} (none should crash)
      assert Enum.all?(results, fn
               {:ok, %Workflow{}} -> true
               {:error, _} -> true
               _ -> false
             end)

      # Only one row in versions table; version_history has the hash once
      assert count_rows(wf.id) == 1

      wf_reloaded = Repo.reload!(%Workflow{id: wf.id})
      assert wf_reloaded.version_history == [@a]
    end
  end
end
