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
      assert wf1.version_history == ["app:#{@a}"]
      assert count_rows(wf.id) == 1

      # same call again -> still one row; history unchanged
      assert {:ok, wf2} = WorkflowVersions.record_version(wf1, @a, "app")
      assert wf2.version_history == ["app:#{@a}"]
      assert count_rows(wf.id) == 1

      # different hash -> appended
      assert {:ok, wf3} = WorkflowVersions.record_version(wf2, @b, "cli")
      assert wf3.version_history == ["app:#{@a}", "cli:#{@b}"]
      assert count_rows(wf.id) == 2
    end

    test "rejects invalid inputs" do
      wf = insert(:workflow)

      assert {:error, :invalid_input} =
               WorkflowVersions.record_version(wf, "NOTHEX12!!!!", "app")

      assert {:error, :invalid_input} =
               WorkflowVersions.record_version(wf, @a, "web")
    end

    test "does not insert duplicate when hash AND source are same as latest" do
      wf = insert(:workflow)

      # Insert first version
      assert {:ok, wf1} = WorkflowVersions.record_version(wf, @a, "app")
      assert wf1.version_history == ["app:#{@a}"]
      assert count_rows(wf.id) == 1

      # Insert different hash
      assert {:ok, wf2} = WorkflowVersions.record_version(wf1, @b, "cli")
      assert wf2.version_history == ["app:#{@a}", "cli:#{@b}"]
      assert count_rows(wf.id) == 2

      # Try to insert the same hash and source as latest (duplicate)
      assert {:ok, wf3} = WorkflowVersions.record_version(wf2, @b, "cli")
      assert wf3.version_history == ["app:#{@a}", "cli:#{@b}"]
      # Should still be 2, no new row inserted
      assert count_rows(wf.id) == 2

      # Try with different source but same hash - NOT a duplicate, will insert
      assert {:ok, wf4} = WorkflowVersions.record_version(wf3, @b, "app")
      assert wf4.version_history == ["app:#{@a}", "cli:#{@b}", "app:#{@b}"]
      # Now we have 3 rows
      assert count_rows(wf.id) == 3
    end

    test "squashes when source is same as latest version's source" do
      wf = insert(:workflow)

      # Insert first version from app
      assert {:ok, wf1} = WorkflowVersions.record_version(wf, @a, "app")
      assert wf1.version_history == ["app:#{@a}"]
      assert count_rows(wf.id) == 1

      # Insert second version from cli
      assert {:ok, wf2} = WorkflowVersions.record_version(wf1, @b, "cli")
      assert wf2.version_history == ["app:#{@a}", "cli:#{@b}"]
      assert count_rows(wf.id) == 2

      # Insert third version from cli (same source as latest) - should squash in DB
      assert {:ok, wf3} = WorkflowVersions.record_version(wf2, @c, "cli")
      # Version history keeps all entries (doesn't remove old ones)
      assert wf3.version_history == ["app:#{@a}", "cli:#{@c}"]
      # Still 2 rows (deleted @b, added @c in database)
      assert count_rows(wf.id) == 2

      # Verify @b was actually deleted from the database
      refute Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @b)
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @c)
    end

    test "does not squash the first version even when source is the same" do
      wf = insert(:workflow)

      # Insert first version from app
      assert {:ok, wf1} = WorkflowVersions.record_version(wf, @a, "app")
      assert wf1.version_history == ["app:#{@a}"]
      assert count_rows(wf.id) == 1

      # Try to insert second version with same source - should NOT squash (first version protected)
      assert {:ok, wf2} = WorkflowVersions.record_version(wf1, @b, "app")
      assert wf2.version_history == ["app:#{@a}", "app:#{@b}"]
      # Should have 2 rows, not squashed
      assert count_rows(wf.id) == 2

      # Both versions should exist in the database
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @a)
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @b)

      # Now third version with same source should squash the second (not the first)
      assert {:ok, wf3} = WorkflowVersions.record_version(wf2, @c, "app")
      assert wf3.version_history == ["app:#{@a}", "app:#{@c}"]
      # Still 2 rows (first protected, second replaced by third)
      assert count_rows(wf.id) == 2

      # First and third should exist, second should be gone
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @a)
      refute Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @b)
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @c)
    end

    test "squashing multiple times in sequence" do
      wf = insert(:workflow)

      # Build up a history
      assert {:ok, wf1} = WorkflowVersions.record_version(wf, @a, "app")
      assert {:ok, wf2} = WorkflowVersions.record_version(wf1, @b, "cli")
      assert wf2.version_history == ["app:#{@a}", "cli:#{@b}"]

      # Multiple squashes from cli
      assert {:ok, wf3} = WorkflowVersions.record_version(wf2, @c, "cli")
      # @b replaced by @c
      assert wf3.version_history == ["app:#{@a}", "cli:#{@c}"]

      assert {:ok, wf4} = WorkflowVersions.record_version(wf3, @d, "cli")
      # @c replaced by @d
      assert wf4.version_history == ["app:#{@a}", "cli:#{@d}"]

      # Only @a and @d should exist in database
      assert count_rows(wf.id) == 2
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @a) != nil
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @b) == nil
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @c) == nil
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @d) != nil
    end

    test "does not squash when sources are different" do
      wf = insert(:workflow)

      # Alternate between app and cli sources
      assert {:ok, wf1} = WorkflowVersions.record_version(wf, @a, "app")
      assert {:ok, wf2} = WorkflowVersions.record_version(wf1, @b, "cli")
      assert {:ok, wf3} = WorkflowVersions.record_version(wf2, @c, "app")
      assert {:ok, wf4} = WorkflowVersions.record_version(wf3, @d, "cli")

      # All versions should be preserved
      assert wf4.version_history == [
               "app:#{@a}",
               "cli:#{@b}",
               "app:#{@c}",
               "cli:#{@d}"
             ]

      assert count_rows(wf.id) == 4

      # All hashes should exist in database
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @a) != nil
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @b) != nil
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @c) != nil
      assert Repo.get_by(WorkflowVersion, workflow_id: wf.id, hash: @d) != nil
    end

    test "handles edge case: first version (no latest to compare)" do
      wf = insert(:workflow)

      # First version should work normally
      assert {:ok, wf1} = WorkflowVersions.record_version(wf, @a, "app")
      assert wf1.version_history == ["app:#{@a}"]
      assert count_rows(wf.id) == 1
    end
  end

  describe "ensure_version_recorded/1" do
    test "records a version when workflow has no version_history" do
      wf = insert(:workflow)
      _job = insert(:job, workflow: wf, name: "TestJob", body: "test code")

      # Workflow starts with no versions
      assert count_rows(wf.id) == 0
      assert wf.version_history == []

      # Ensure version recorded
      assert {:ok, updated_wf} = WorkflowVersions.ensure_version_recorded(wf)

      # Should now have one version
      assert count_rows(wf.id) == 1
      assert length(updated_wf.version_history) == 1

      # Version should be valid
      [version_entry] = updated_wf.version_history
      assert String.match?(version_entry, ~r/^app:[a-f0-9]{12}$/)
    end

    test "does nothing when workflow already has version_history" do
      wf = insert(:workflow)

      # Record an initial version
      assert {:ok, wf1} = WorkflowVersions.record_version(wf, @a, "app")
      assert wf1.version_history == ["app:#{@a}"]
      assert count_rows(wf.id) == 1

      # Call ensure_version_recorded
      assert {:ok, wf2} = WorkflowVersions.ensure_version_recorded(wf1)

      # Should be unchanged (idempotent)
      assert wf2.version_history == ["app:#{@a}"]
      assert count_rows(wf.id) == 1
    end

    test "is idempotent when called multiple times" do
      wf = insert(:workflow)
      insert(:job, workflow: wf, name: "TestJob")

      # First call
      assert {:ok, wf1} = WorkflowVersions.ensure_version_recorded(wf)
      first_count = count_rows(wf.id)
      first_history = wf1.version_history

      # Second call
      assert {:ok, wf2} = WorkflowVersions.ensure_version_recorded(wf1)

      # Should be unchanged
      assert count_rows(wf.id) == first_count
      assert wf2.version_history == first_history
    end
  end

  describe "history_for/1" do
    test "uses version_history array when present" do
      wf = insert(:workflow, version_history: ["app:#{@a}", "cli:#{@b}"])
      assert WorkflowVersions.history_for(wf) == ["app:#{@a}", "cli:#{@b}"]
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

      assert WorkflowVersions.history_for(wf) == [
               "cli:#{@a}",
               "app:#{@b}",
               "app:#{@c}"
             ]
    end
  end

  describe "latest_hash/1" do
    test "uses List.last(version_history) when present" do
      wf =
        insert(:workflow,
          version_history: ["app:#{@a}", "cli:#{@b}", "app:#{@c}"]
        )

      assert WorkflowVersions.latest_hash(wf) == "app:#{@c}"
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

      assert WorkflowVersions.latest_hash(wf) == "app:#{@c}"
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
      assert updated.version_history == ["app:#{@a}", "cli:#{@b}", "app:#{@c}"]

      assert Repo.reload!(%Workflow{id: wf.id}).version_history == [
               "app:#{@a}",
               "cli:#{@b}",
               "app:#{@c}"
             ]
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

  describe "generate_hash/1" do
    test "generates consistent hash for same workflow structure" do
      project = insert(:project)

      workflow =
        insert(:workflow,
          project: project,
          name: "Test Workflow"
        )

      job1 =
        insert(:job,
          workflow: workflow,
          name: "Job A",
          body: "fn(state) => state",
          adaptor: "@openfn/language-http@latest"
        )

      job2 =
        insert(:job,
          workflow: workflow,
          name: "Job B",
          body: "fn(state) => ({ ...state, processed: true })",
          adaptor: "@openfn/language-common@latest"
        )

      trigger =
        insert(:trigger,
          workflow: workflow,
          type: :webhook,
          enabled: true
        )

      insert(:edge,
        workflow: workflow,
        source_trigger: trigger,
        target_job: job1,
        condition_type: :always,
        enabled: true
      )

      insert(:edge,
        workflow: workflow,
        source_job: job1,
        target_job: job2,
        condition_type: :on_job_success,
        enabled: true
      )

      # Reload to get all associations
      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges])

      hash1 = WorkflowVersions.generate_hash(workflow)
      hash2 = WorkflowVersions.generate_hash(workflow)

      assert hash1 == hash2
      assert String.length(hash1) == 12
      assert Regex.match?(~r/^[a-f0-9]{12}$/, hash1)
    end

    test "generates different hashes for different workflow structures" do
      project = insert(:project)

      workflow1 = insert(:workflow, project: project, name: "Workflow 1")
      workflow2 = insert(:workflow, project: project, name: "Workflow 2")

      _job1 = insert(:job, workflow: workflow1, name: "Job A", body: "code1")
      _job2 = insert(:job, workflow: workflow2, name: "Job A", body: "code2")

      workflow1 = Repo.preload(workflow1, [:triggers, :jobs, :edges])
      workflow2 = Repo.preload(workflow2, [:triggers, :jobs, :edges])

      hash1 = WorkflowVersions.generate_hash(workflow1)
      hash2 = WorkflowVersions.generate_hash(workflow2)

      refute hash1 == hash2
    end

    test "ignores kafka configuration changes" do
      workflow = insert(:workflow, name: "Test")

      trigger =
        insert(:trigger,
          workflow: workflow,
          type: :kafka,
          kafka_configuration:
            build(:triggers_kafka_configuration, topics: ["1"])
        )

      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges])
      hash1 = WorkflowVersions.generate_hash(workflow)

      # Update kafka config
      updated_trigger =
        trigger
        |> Lightning.Workflows.Trigger.changeset(%{
          kafka_configuration: %{topics: ["22"]}
        })
        |> Repo.update!()

      assert updated_trigger.kafka_configuration.topics == ["22"]

      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges], force: true)
      hash2 = WorkflowVersions.generate_hash(workflow)

      refute updated_trigger.kafka_configuration.topics ==
               trigger.kafka_configuration.topics

      assert hash1 == hash2
    end

    test "hash changes when job body changes" do
      workflow = insert(:workflow, name: "Test")
      job = insert(:job, workflow: workflow, name: "Job", body: "original")

      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges])
      hash1 = WorkflowVersions.generate_hash(workflow)

      # Update job body
      job |> Ecto.Changeset.change(body: "modified") |> Repo.update!()
      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges], force: true)
      hash2 = WorkflowVersions.generate_hash(workflow)

      refute hash1 == hash2
    end

    test "hash changes when edge condition changes" do
      workflow = insert(:workflow, name: "Test")
      job1 = insert(:job, workflow: workflow, name: "Job A")
      job2 = insert(:job, workflow: workflow, name: "Job B")

      edge =
        insert(:edge,
          workflow: workflow,
          source_job: job1,
          target_job: job2,
          condition_type: :always
        )

      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges])
      hash1 = WorkflowVersions.generate_hash(workflow)

      # Update edge condition
      edge
      |> Ecto.Changeset.change(condition_type: :on_job_failure)
      |> Repo.update!()

      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges], force: true)
      hash2 = WorkflowVersions.generate_hash(workflow)

      refute hash1 == hash2
    end

    test "properly orders triggers by type" do
      workflow = insert(:workflow, name: "Test")

      # Insert triggers in reverse order
      insert(:trigger, workflow: workflow, type: :webhook)
      insert(:trigger, workflow: workflow, type: :kafka)

      insert(:trigger,
        workflow: workflow,
        type: :cron,
        cron_expression: "0 * * * *"
      )

      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges])

      # Generate hash multiple times with shuffled triggers
      hashes =
        for _ <- 1..5 do
          workflow = %{workflow | triggers: Enum.shuffle(workflow.triggers)}
          WorkflowVersions.generate_hash(workflow)
        end

      # All hashes should be identical despite shuffling
      assert Enum.uniq(hashes) |> length() == 1
    end

    test "properly orders jobs by name" do
      workflow = insert(:workflow, name: "Test")

      insert(:job, workflow: workflow, name: "Charlie")
      insert(:job, workflow: workflow, name: "Alice")
      insert(:job, workflow: workflow, name: "Bob")

      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges])

      # Generate hash multiple times with shuffled jobs
      hashes =
        for _ <- 1..5 do
          workflow = %{workflow | jobs: Enum.shuffle(workflow.jobs)}
          WorkflowVersions.generate_hash(workflow)
        end

      # All hashes should be identical despite shuffling
      assert Enum.uniq(hashes) |> length() == 1
    end

    test "properly names and orders edges" do
      workflow = insert(:workflow, name: "Test")

      job_a = insert(:job, workflow: workflow, name: "Alpha")
      job_b = insert(:job, workflow: workflow, name: "Beta")
      job_c = insert(:job, workflow: workflow, name: "Gamma")

      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      # Create edges with different sources and targets
      insert(:edge,
        workflow: workflow,
        source_trigger: trigger,
        target_job: job_a
      )

      insert(:edge, workflow: workflow, source_job: job_a, target_job: job_b)
      insert(:edge, workflow: workflow, source_job: job_b, target_job: job_c)

      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges])

      # Generate hash multiple times with shuffled edges
      hashes =
        for _ <- 1..5 do
          workflow = %{workflow | edges: Enum.shuffle(workflow.edges)}
          WorkflowVersions.generate_hash(workflow)
        end

      # All hashes should be identical despite shuffling
      assert Enum.uniq(hashes) |> length() == 1
    end

    test "handles workflow positions correctly" do
      workflow1 =
        insert(:workflow,
          name: "Test",
          positions: %{"node1" => %{"x" => 100, "y" => 200}}
        )

      workflow2 =
        insert(:workflow,
          name: "Test",
          positions: %{"node1" => %{"x" => 150, "y" => 200}}
        )

      workflow1 = Repo.preload(workflow1, [:triggers, :jobs, :edges])
      workflow2 = Repo.preload(workflow2, [:triggers, :jobs, :edges])

      hash1 = WorkflowVersions.generate_hash(workflow1)
      hash2 = WorkflowVersions.generate_hash(workflow2)

      # Different positions should generate different hashes
      refute hash1 == hash2
    end

    test "handles nil and empty values consistently" do
      workflow = insert(:workflow, name: "Test", positions: nil)

      _job =
        insert(:job,
          workflow: workflow,
          name: "Job",
          body: "",
          project_credential_id: nil
        )

      _trigger =
        insert(:trigger,
          workflow: workflow,
          type: :cron,
          cron_expression: nil
        )

      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges])

      hash1 = WorkflowVersions.generate_hash(workflow)
      hash2 = WorkflowVersions.generate_hash(workflow)

      assert hash1 == hash2
      assert String.length(hash1) == 12
    end

    test "edge name generation for trigger->job edges" do
      workflow = insert(:workflow, name: "Test")
      job = insert(:job, workflow: workflow, name: "ProcessData")
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      insert(:edge,
        workflow: workflow,
        source_trigger: trigger,
        target_job: job,
        condition_type: :always
      )

      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges])

      # The edge name should be "webhook-ProcessData"
      # Generate hash to ensure it processes correctly
      hash = WorkflowVersions.generate_hash(workflow)
      assert String.length(hash) == 12
    end

    test "edge name generation for job->job edges" do
      workflow = insert(:workflow, name: "Test")
      job1 = insert(:job, workflow: workflow, name: "ExtractData")
      job2 = insert(:job, workflow: workflow, name: "TransformData")

      insert(:edge,
        workflow: workflow,
        source_job: job1,
        target_job: job2,
        condition_type: :on_job_success
      )

      workflow = Repo.preload(workflow, [:triggers, :jobs, :edges])

      # The edge name should be "ExtractData-TransformData"
      # Generate hash to ensure it processes correctly
      hash = WorkflowVersions.generate_hash(workflow)
      assert String.length(hash) == 12
    end

    test "generates the same hash for this simple workflow" do
      predetermined_hash = "05c455a228e6"

      simple_workflow = %{
        name: "Simple Workflow",
        positions: nil,
        jobs: [
          %{
            id: "job1",
            name: "First Job",
            body: "fn(state) => state",
            adaptor: "@openfn/language-common@latest",
            project_credential_id: "credential1",
            keychain_credential_id: nil
          },
          %{
            id: "job2",
            name: "Second Job",
            body: "fn(state) => state",
            adaptor: "@openfn/language-http@latest",
            project_credential_id: nil,
            keychain_credential_id: nil
          }
        ],
        triggers: [
          %{
            id: "trigger1",
            type: :webhook,
            cron_expression: nil,
            enabled: true
          }
        ],
        edges: [
          %{
            source_trigger_id: "trigger1",
            target_job_id: "job1",
            source_job_id: nil,
            condition_type: :always,
            condition_label: nil,
            condition_expression: nil,
            enabled: true
          },
          %{
            source_trigger_id: nil,
            source_job_id: "job1",
            target_job_id: "job2",
            condition_type: :on_job_success,
            condition_label: nil,
            condition_expression: nil,
            enabled: true
          }
        ]
      }

      for _i <- 1..5 do
        assert WorkflowVersions.generate_hash(simple_workflow) ==
                 predetermined_hash
      end
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
      assert wf_reloaded.version_history == ["app:#{@a}"]
    end
  end
end
