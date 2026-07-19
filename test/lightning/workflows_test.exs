defmodule Lightning.WorkflowsTest do
  use Lightning.DataCase, async: false
  use Mimic

  import ExUnit.CaptureLog
  import Lightning.Factories

  alias Lightning.Auditing.Audit
  alias Lightning.Workflows
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Triggers.Events
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerUpdated

  describe "go_live/2 and switch_to_draft/2" do
    setup do
      %{user: insert(:user)}
    end

    test "go_live sets state to :live and enables triggers", %{user: user} do
      {:ok, workflow} =
        insert(:simple_workflow)
        |> Workflows.update_triggers_enabled_state(false)
        |> Ecto.Changeset.put_change(:state, :draft)
        |> Workflows.save_workflow(user)

      assert workflow.state == :draft

      {:ok, live} = Workflows.go_live(workflow, user)

      assert live.state == :live

      assert Repo.preload(live, :triggers, force: true).triggers
             |> Enum.all?(& &1.enabled)
    end

    test "switch_to_draft sets state to :draft and disables triggers", %{
      user: user
    } do
      {:ok, live} = Workflows.go_live(insert(:simple_workflow), user)
      assert live.state == :live

      {:ok, draft} = Workflows.switch_to_draft(live, user)

      assert draft.state == :draft

      refute Repo.preload(draft, :triggers, force: true).triggers
             |> Enum.any?(& &1.enabled)
    end
  end

  describe "workflows" do
    test "list_workflows/0 returns all workflows" do
      workflow = insert(:workflow)

      assert Workflows.list_workflows() |> Enum.map(fn w -> w.id end) == [
               workflow.id
             ]
    end

    test "get_workflow!/1 returns the workflow with given id" do
      workflow = insert(:workflow)

      assert Workflows.get_workflow!(workflow.id) |> unload_relation(:project) ==
               workflow |> unload_relation(:project)

      assert_raise Ecto.NoResultsError, fn ->
        Workflows.get_workflow!(Ecto.UUID.generate())
      end
    end

    test "get_workflow/1 returns the workflow with given id" do
      assert Workflows.get_workflow(Ecto.UUID.generate()) == nil

      workflow = insert(:workflow)

      assert Workflows.get_workflow(workflow.id) |> unload_relation(:project) ==
               workflow |> unload_relation(:project)
    end

    test "save_workflow/1 with valid data creates a workflow" do
      user = insert(:user)
      project = insert(:project)
      valid_attrs = %{name: "some-name", project_id: project.id}

      assert {:ok, workflow} = Workflows.save_workflow(valid_attrs, user)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Workflows.save_workflow(valid_attrs, user)

      assert %{
               name: [
                 "A workflow with this name already exists (possibly pending deletion) in this project."
               ]
             } = errors_on(changeset)

      assert workflow.name == "some-name"
    end

    test "save_workflow/1 with valid data updates the workflow" do
      workflow = insert(:workflow)
      update_attrs = %{name: "some-updated-name"}

      assert {:ok, workflow} =
               Workflows.change_workflow(workflow, update_attrs)
               |> Workflows.save_workflow(insert(:user))

      assert workflow.name == "some-updated-name"
    end

    test "save_workflow/1 for a deleted workflow returns an error" do
      user = insert(:user)
      workflow = insert(:workflow, deleted_at: DateTime.utc_now())
      update_attrs = %{name: "some-updated-name"}

      assert {:error, :workflow_deleted} =
               Workflows.change_workflow(workflow, update_attrs)
               |> Workflows.save_workflow(user)
    end

    test "save_workflow/1 with changeset audits creation of the snapshot" do
      %{id: user_id} = user = insert(:user)
      %{id: workflow_id} = workflow = insert(:workflow)
      update_attrs = %{name: "some-updated-name"}

      workflow
      |> Workflows.change_workflow(update_attrs)
      |> Workflows.save_workflow(user)

      %{id: snapshot_id} = Snapshot |> Repo.one!()

      assert %{
               event: "snapshot_created",
               item_type: "workflow",
               item_id: ^workflow_id,
               actor_id: ^user_id,
               changes: %{
                 after: %{
                   "snapshot_id" => ^snapshot_id
                 }
               }
             } = Repo.one(Audit)
    end

    test "save_workflow/1 with attrs audits creation of the snapshot" do
      %{id: user_id} = user = insert(:user)
      project = insert(:project)
      valid_attrs = %{name: "some-name", project_id: project.id}

      {:ok, %{id: workflow_id}} = Workflows.save_workflow(valid_attrs, user)

      %{id: snapshot_id} = Snapshot |> Repo.one!()

      assert %{
               event: "snapshot_created",
               item_type: "workflow",
               item_id: ^workflow_id,
               actor_id: ^user_id,
               changes: %{
                 after: %{
                   "snapshot_id" => ^snapshot_id
                 }
               }
             } = Repo.one(Audit)
    end

    test "save_workflow/1 records a version" do
      user = insert(:user)
      project = insert(:project)

      # Create a new workflow
      valid_attrs = %{name: "versioned-workflow", project_id: project.id}
      {:ok, workflow} = Workflows.save_workflow(valid_attrs, user)

      # Check that a version was recorded
      version_history = Lightning.WorkflowVersions.history_for(workflow)
      assert length(version_history) == 1

      # Verify the version exists in the database
      version =
        Lightning.Workflows.WorkflowVersion
        |> Repo.get_by!(workflow_id: workflow.id)

      assert "#{version.source}:#{version.hash}" == hd(version_history)
      assert version.source == "app"
    end

    test "save_workflow/1 audits when a trigger is enabled" do
      %{id: user_id} = user = insert(:user)
      workflow = create_workflow()

      {:ok, _workflow} =
        workflow
        |> Workflows.update_triggers_enabled_state(true)
        |> Workflows.save_workflow(user)

      assert_trigger_state_audit(workflow.id, user_id, false, true, "enabled")
    end

    test "save_workflow/1 audits when a trigger is disabled" do
      %{id: user_id} = user = insert(:user)
      workflow = create_workflow(enabled: true)

      {:ok, _workflow} =
        workflow
        |> Workflows.update_triggers_enabled_state(false)
        |> Workflows.save_workflow(user)

      assert_trigger_state_audit(workflow.id, user_id, true, false, "disabled")
    end

    test "save_workflow/1 does not audit when trigger enabled state doesn't change" do
      user = insert(:user)
      workflow = create_workflow(enabled: true)

      {:ok, _workflow} =
        workflow
        |> Workflows.update_triggers_enabled_state(true)
        |> Workflows.save_workflow(user)

      assert Repo.aggregate(Audit, :count) == 0
    end

    test "save_workflow/1 does not audit when updating other workflow attributes" do
      user = insert(:user)
      workflow = create_workflow(enabled: true)

      {:ok, _workflow} =
        workflow
        |> Workflows.change_workflow(%{name: "updated name"})
        |> Workflows.save_workflow(user)

      assert Repo.aggregate(
               from(a in Audit, where: a.event in ["enabled", "disabled"]),
               :count
             ) == 0
    end

    test "save_workflow/1 with simultaneous trigger and name changes only audits trigger" do
      %{id: user_id} = user = insert(:user)
      workflow = create_workflow(enabled: true)

      {:ok, _workflow} =
        workflow
        |> Workflows.change_workflow(%{name: "new name"})
        |> Workflows.update_triggers_enabled_state(false)
        |> Workflows.save_workflow(user)

      assert_trigger_state_audit(workflow.id, user_id, true, false, "disabled")

      assert Repo.aggregate(
               from(a in Audit, where: a.event in ["enabled", "disabled"]),
               :count
             ) == 1
    end

    test "save_workflow/1 publishes event for updated Kafka triggers" do
      kafka_configuration = build(:triggers_kafka_configuration)

      workflow = insert(:workflow) |> Repo.preload(:triggers)

      kafka_trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          workflow: workflow,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      cron_trigger_1 =
        insert(
          :trigger,
          type: :cron,
          workflow: workflow,
          enabled: false
        )

      kafka_trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          workflow: workflow,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      triggers = [
        {kafka_trigger_1, %{enabled: true}},
        {cron_trigger_1, %{enabled: true}},
        {kafka_trigger_2, %{enabled: true}}
      ]

      kafka_trigger_1_id = kafka_trigger_1.id
      cron_trigger_1_id = cron_trigger_1.id
      kafka_trigger_2_id = kafka_trigger_2.id

      changeset = workflow |> build_changeset(triggers)

      Events.subscribe_to_kafka_trigger_updated()

      changeset |> Workflows.save_workflow(insert(:user))

      assert_received %KafkaTriggerUpdated{trigger_id: ^kafka_trigger_1_id}
      assert_received %KafkaTriggerUpdated{trigger_id: ^kafka_trigger_2_id}
      refute_received %KafkaTriggerUpdated{trigger_id: ^cron_trigger_1_id}
    end

    test "save_workflow/1 does not publish events if save fails" do
      kafka_configuration = build(:triggers_kafka_configuration)

      workflow = insert(:workflow) |> Repo.preload(:triggers)

      kafka_trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          workflow: workflow,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      cron_trigger_1 =
        insert(
          :trigger,
          type: :cron,
          workflow: workflow,
          enabled: false
        )

      kafka_trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          workflow: workflow,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      triggers = [
        {kafka_trigger_1, %{enabled: true}},
        {cron_trigger_1, %{type: :unobtainium}},
        {kafka_trigger_2, %{enabled: true}}
      ]

      kafka_trigger_1_id = kafka_trigger_1.id
      cron_trigger_1_id = cron_trigger_1.id
      kafka_trigger_2_id = kafka_trigger_2.id

      changeset = workflow |> build_changeset(triggers)

      Events.subscribe_to_kafka_trigger_updated()

      changeset |> Workflows.save_workflow(nil)

      refute_received %KafkaTriggerUpdated{trigger_id: ^kafka_trigger_1_id}
      refute_received %KafkaTriggerUpdated{trigger_id: ^kafka_trigger_2_id}
      refute_received %KafkaTriggerUpdated{trigger_id: ^cron_trigger_1_id}
    end

    defp build_changeset(workflow, triggers_and_attrs) do
      triggers_changes =
        triggers_and_attrs
        |> Enum.map(fn {trigger, attrs} ->
          Trigger.changeset(trigger, attrs)
        end)

      Ecto.Changeset.change(workflow, triggers: triggers_changes)
    end

    test "save_workflow/1 using attrs" do
      project = insert(:project)
      valid_attrs = %{name: "some-name", project_id: project.id}
      user = insert(:user)

      assert {:ok, workflow} =
               Lightning.Workflows.save_workflow(valid_attrs, user)

      assert workflow.name == "some-name"

      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()

      valid_attrs = %{
        name: "some-other-name",
        project_id: project.id,
        jobs: [%{id: job_id, name: "some-job", body: "fn(state)"}],
        triggers: [%{id: trigger_id, type: :webhook}],
        edges: [
          %{
            source_trigger_id: trigger_id,
            condition_type: :always,
            target_job_id: job_id
          }
        ]
      }

      assert {:ok, workflow} =
               Lightning.Workflows.save_workflow(valid_attrs, user)

      edge = workflow.edges |> List.first()
      assert edge.source_trigger_id == trigger_id
      assert edge.target_job_id == job_id

      assert workflow.name == "some-other-name"
    end

    test "using save_workflow/2" do
      project = insert(:project)
      user = insert(:user)

      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()

      valid_attrs = %{
        name: "some-name",
        project_id: project.id,
        jobs: [%{id: job_id, name: "some-job", body: "fn(state)"}],
        triggers: [%{id: trigger_id, type: :webhook}],
        edges: [
          %{
            source_trigger_id: trigger_id,
            target_job_id: job_id,
            condition_type: :always
          }
        ]
      }

      {:ok, workflow} = Workflows.save_workflow(valid_attrs, user)

      edge = workflow.edges |> List.first()

      # Updating a job and resubmitting the same edge should not create a new edge
      valid_attrs = %{
        jobs: [%{id: job_id, name: "some-job-renamed"}],
        edges: [
          %{
            id: edge.id,
            source_trigger_id: trigger_id,
            target_job_id: job_id,
            condition_type: :always
          }
        ]
      }

      assert {:ok, workflow} =
               Workflows.change_workflow(workflow, valid_attrs)
               |> Workflows.save_workflow(user)

      assert Repo.get_by(Workflows.Job,
               id: job_id,
               name: "some-job-renamed"
             )

      assert workflow.name == "some-name"
      assert workflow.edges |> List.first() == edge

      valid_attrs = %{
        jobs: [%{id: job_id, name: "some-job"}],
        triggers: [%{id: trigger_id, type: :webhook}],
        edges: []
      }

      assert {:ok, workflow} =
               Workflows.change_workflow(workflow, valid_attrs)
               |> Workflows.save_workflow(user)

      assert workflow.name == "some-name"
      assert workflow.edges |> Enum.empty?()

      refute Repo.get(Workflows.Edge, edge.id)
    end

    test "edge retargeting: delete job and retarget edge to replacement job" do
      project = insert(:project)
      user = insert(:user)

      trigger_id = Ecto.UUID.generate()
      job_a_id = Ecto.UUID.generate()
      job_b_id = Ecto.UUID.generate()

      {:ok, workflow} =
        Workflows.save_workflow(
          %{
            name: "retarget-test",
            project_id: project.id,
            jobs: [
              %{id: job_a_id, name: "job-a", body: "fn(state)"},
              %{id: job_b_id, name: "job-b", body: "fn(state)"}
            ],
            triggers: [%{id: trigger_id, type: :webhook}],
            edges: [
              %{
                source_trigger_id: trigger_id,
                target_job_id: job_a_id,
                condition_type: :always
              },
              %{
                source_job_id: job_a_id,
                target_job_id: job_b_id,
                condition_type: :on_job_success
              }
            ]
          },
          user
        )

      edge_a_to_b =
        Enum.find(workflow.edges, &(&1.target_job_id == job_b_id))

      # Payload: delete job_b, add job_c, retarget the same edge to job_c
      job_c_id = Ecto.UUID.generate()

      assert {:ok, saved} =
               Workflows.change_workflow(workflow, %{
                 jobs: [
                   %{id: job_a_id, name: "job-a", body: "fn(state)"},
                   %{id: job_c_id, name: "job-c", body: "fn(state)"}
                 ],
                 triggers: [%{id: trigger_id, type: :webhook}],
                 edges: [
                   %{
                     id:
                       Enum.find(
                         workflow.edges,
                         &(&1.source_trigger_id == trigger_id)
                       ).id,
                     source_trigger_id: trigger_id,
                     target_job_id: job_a_id,
                     condition_type: :always
                   },
                   %{
                     id: edge_a_to_b.id,
                     source_job_id: job_a_id,
                     target_job_id: job_c_id,
                     condition_type: :on_job_success
                   }
                 ]
               })
               |> Workflows.save_workflow(user)

      saved = Repo.preload(saved, [:jobs, :edges], force: true)

      assert length(saved.jobs) == 2
      refute Enum.any?(saved.jobs, &(&1.id == job_b_id))
      assert Enum.any?(saved.jobs, &(&1.id == job_c_id))

      # Edge preserved its ID but points to the new job
      retargeted = Enum.find(saved.edges, &(&1.id == edge_a_to_b.id))
      assert retargeted.target_job_id == job_c_id
      assert retargeted.source_job_id == job_a_id
    end

    test "edge retargeting: replace first job retargets trigger edge target and downstream edge source" do
      project = insert(:project)
      user = insert(:user)

      trigger_id = Ecto.UUID.generate()
      job_a_id = Ecto.UUID.generate()
      job_b_id = Ecto.UUID.generate()

      {:ok, workflow} =
        Workflows.save_workflow(
          %{
            name: "replace-first-job",
            project_id: project.id,
            jobs: [
              %{id: job_a_id, name: "job-a", body: "fn(state)"},
              %{id: job_b_id, name: "job-b", body: "fn(state)"}
            ],
            triggers: [%{id: trigger_id, type: :webhook}],
            edges: [
              %{
                source_trigger_id: trigger_id,
                target_job_id: job_a_id,
                condition_type: :always
              },
              %{
                source_job_id: job_a_id,
                target_job_id: job_b_id,
                condition_type: :on_job_success
              }
            ]
          },
          user
        )

      trigger_edge =
        Enum.find(workflow.edges, &(&1.source_trigger_id == trigger_id))

      job_edge =
        Enum.find(workflow.edges, &(&1.source_job_id == job_a_id))

      # Delete job_a, add job_c, retarget both edges
      job_c_id = Ecto.UUID.generate()

      assert {:ok, saved} =
               Workflows.change_workflow(workflow, %{
                 jobs: [
                   %{id: job_c_id, name: "job-c", body: "fn(state)"},
                   %{id: job_b_id, name: "job-b", body: "fn(state)"}
                 ],
                 triggers: [%{id: trigger_id, type: :webhook}],
                 edges: [
                   %{
                     id: trigger_edge.id,
                     source_trigger_id: trigger_id,
                     target_job_id: job_c_id,
                     condition_type: :always
                   },
                   %{
                     id: job_edge.id,
                     source_job_id: job_c_id,
                     target_job_id: job_b_id,
                     condition_type: :on_job_success
                   }
                 ]
               })
               |> Workflows.save_workflow(user)

      saved = Repo.preload(saved, [:jobs, :edges], force: true)

      assert length(saved.jobs) == 2
      assert length(saved.edges) == 2

      # Trigger edge preserved ID and retargeted to job_c
      saved_trigger_edge =
        Enum.find(saved.edges, &(&1.id == trigger_edge.id))

      assert saved_trigger_edge.target_job_id == job_c_id

      # Job edge preserved ID and source retargeted to job_c
      saved_job_edge = Enum.find(saved.edges, &(&1.id == job_edge.id))
      assert saved_job_edge.source_job_id == job_c_id
      assert saved_job_edge.target_job_id == job_b_id
    end

    test "edge retargeting: delete first job cleans up trigger edge and downstream edge" do
      project = insert(:project)
      user = insert(:user)

      trigger_id = Ecto.UUID.generate()
      job_a_id = Ecto.UUID.generate()
      job_b_id = Ecto.UUID.generate()

      {:ok, workflow} =
        Workflows.save_workflow(
          %{
            name: "delete-first-job",
            project_id: project.id,
            jobs: [
              %{id: job_a_id, name: "job-a", body: "fn(state)"},
              %{id: job_b_id, name: "job-b", body: "fn(state)"}
            ],
            triggers: [%{id: trigger_id, type: :webhook}],
            edges: [
              %{
                source_trigger_id: trigger_id,
                target_job_id: job_a_id,
                condition_type: :always
              },
              %{
                source_job_id: job_a_id,
                target_job_id: job_b_id,
                condition_type: :on_job_success
              }
            ]
          },
          user
        )

      trigger_edge =
        Enum.find(workflow.edges, &(&1.source_trigger_id == trigger_id))

      job_edge =
        Enum.find(workflow.edges, &(&1.source_job_id == job_a_id))

      # Delete job_a, remove both edges, keep only job_b
      assert {:ok, saved} =
               Workflows.change_workflow(workflow, %{
                 jobs: [
                   %{id: job_b_id, name: "job-b", body: "fn(state)"}
                 ],
                 triggers: [%{id: trigger_id, type: :webhook}],
                 edges: []
               })
               |> Workflows.save_workflow(user)

      saved = Repo.preload(saved, [:jobs, :edges], force: true)

      assert length(saved.jobs) == 1
      assert hd(saved.jobs).id == job_b_id
      assert saved.edges == []

      # Both edges cleaned up
      refute Repo.get(Workflows.Edge, trigger_edge.id)
      refute Repo.get(Workflows.Edge, job_edge.id)
    end

    test "edge retargeting: delete middle job in chain cleans up both edges" do
      project = insert(:project)
      user = insert(:user)

      trigger_id = Ecto.UUID.generate()
      job_a_id = Ecto.UUID.generate()
      job_b_id = Ecto.UUID.generate()
      job_c_id = Ecto.UUID.generate()

      {:ok, workflow} =
        Workflows.save_workflow(
          %{
            name: "delete-middle-job",
            project_id: project.id,
            jobs: [
              %{id: job_a_id, name: "job-a", body: "fn(state)"},
              %{id: job_b_id, name: "job-b", body: "fn(state)"},
              %{id: job_c_id, name: "job-c", body: "fn(state)"}
            ],
            triggers: [%{id: trigger_id, type: :webhook}],
            edges: [
              %{
                source_trigger_id: trigger_id,
                target_job_id: job_a_id,
                condition_type: :always
              },
              %{
                source_job_id: job_a_id,
                target_job_id: job_b_id,
                condition_type: :on_job_success
              },
              %{
                source_job_id: job_b_id,
                target_job_id: job_c_id,
                condition_type: :on_job_success
              }
            ]
          },
          user
        )

      trigger_edge =
        Enum.find(workflow.edges, &(&1.source_trigger_id == trigger_id))

      a_to_b_edge =
        Enum.find(workflow.edges, &(&1.target_job_id == job_b_id))

      b_to_c_edge =
        Enum.find(workflow.edges, &(&1.source_job_id == job_b_id))

      # Delete job_b, keep trigger -> job_a edge only
      assert {:ok, saved} =
               Workflows.change_workflow(workflow, %{
                 jobs: [
                   %{id: job_a_id, name: "job-a", body: "fn(state)"},
                   %{id: job_c_id, name: "job-c", body: "fn(state)"}
                 ],
                 triggers: [%{id: trigger_id, type: :webhook}],
                 edges: [
                   %{
                     id: trigger_edge.id,
                     source_trigger_id: trigger_id,
                     target_job_id: job_a_id,
                     condition_type: :always
                   }
                 ]
               })
               |> Workflows.save_workflow(user)

      saved = Repo.preload(saved, [:jobs, :edges], force: true)

      assert length(saved.jobs) == 2
      assert length(saved.edges) == 1
      assert hd(saved.edges).id == trigger_edge.id

      # a->b edge deleted (lost target)
      refute Repo.get(Workflows.Edge, a_to_b_edge.id)
      # b->c edge deleted (lost source)
      refute Repo.get(Workflows.Edge, b_to_c_edge.id)
    end

    test "edge retargeting: replace middle job retargets both edges" do
      project = insert(:project)
      user = insert(:user)

      trigger_id = Ecto.UUID.generate()
      job_a_id = Ecto.UUID.generate()
      job_b_id = Ecto.UUID.generate()
      job_c_id = Ecto.UUID.generate()

      {:ok, workflow} =
        Workflows.save_workflow(
          %{
            name: "replace-middle-job",
            project_id: project.id,
            jobs: [
              %{id: job_a_id, name: "job-a", body: "fn(state)"},
              %{id: job_b_id, name: "job-b", body: "fn(state)"},
              %{id: job_c_id, name: "job-c", body: "fn(state)"}
            ],
            triggers: [%{id: trigger_id, type: :webhook}],
            edges: [
              %{
                source_trigger_id: trigger_id,
                target_job_id: job_a_id,
                condition_type: :always
              },
              %{
                source_job_id: job_a_id,
                target_job_id: job_b_id,
                condition_type: :on_job_success
              },
              %{
                source_job_id: job_b_id,
                target_job_id: job_c_id,
                condition_type: :on_job_success
              }
            ]
          },
          user
        )

      trigger_edge =
        Enum.find(workflow.edges, &(&1.source_trigger_id == trigger_id))

      a_to_b_edge =
        Enum.find(workflow.edges, &(&1.target_job_id == job_b_id))

      b_to_c_edge =
        Enum.find(workflow.edges, &(&1.source_job_id == job_b_id))

      # Delete job_b, add job_d, retarget both edges
      job_d_id = Ecto.UUID.generate()

      assert {:ok, saved} =
               Workflows.change_workflow(workflow, %{
                 jobs: [
                   %{id: job_a_id, name: "job-a", body: "fn(state)"},
                   %{id: job_d_id, name: "job-d", body: "fn(state)"},
                   %{id: job_c_id, name: "job-c", body: "fn(state)"}
                 ],
                 triggers: [%{id: trigger_id, type: :webhook}],
                 edges: [
                   %{
                     id: trigger_edge.id,
                     source_trigger_id: trigger_id,
                     target_job_id: job_a_id,
                     condition_type: :always
                   },
                   %{
                     id: a_to_b_edge.id,
                     source_job_id: job_a_id,
                     target_job_id: job_d_id,
                     condition_type: :on_job_success
                   },
                   %{
                     id: b_to_c_edge.id,
                     source_job_id: job_d_id,
                     target_job_id: job_c_id,
                     condition_type: :on_job_success
                   }
                 ]
               })
               |> Workflows.save_workflow(user)

      saved = Repo.preload(saved, [:jobs, :edges], force: true)

      assert length(saved.jobs) == 3
      assert length(saved.edges) == 3

      # a->b edge retargeted to a->d
      retargeted_a = Enum.find(saved.edges, &(&1.id == a_to_b_edge.id))
      assert retargeted_a.source_job_id == job_a_id
      assert retargeted_a.target_job_id == job_d_id

      # b->c edge retargeted to d->c
      retargeted_b = Enum.find(saved.edges, &(&1.id == b_to_c_edge.id))
      assert retargeted_b.source_job_id == job_d_id
      assert retargeted_b.target_job_id == job_c_id
    end

    test "saving with locks" do
      user = insert(:user)
      valid_attrs = params_with_assocs(:workflow, jobs: [params_for(:job)])

      assert {:ok, workflow} =
               Workflows.save_workflow(valid_attrs, insert(:user))

      assert workflow.lock_version == 1

      assert {:ok, workflow} =
               Workflows.change_workflow(workflow, %{})
               |> Workflows.save_workflow(user)

      assert workflow.lock_version == 1,
             "lock_version should not change when no changes are made"

      assert {:ok, updated_workflow} =
               Workflows.change_workflow(workflow, %{jobs: [params_for(:job)]})
               |> Workflows.save_workflow(user)

      assert updated_workflow.lock_version == 2

      # Throws an error because the lock_version is outdated
      assert_raise Ecto.StaleEntryError, fn ->
        Workflows.change_workflow(workflow, %{jobs: [params_for(:job)]})
        |> Workflows.save_workflow(user)
      end
    end

    test "change_workflow/1 returns a workflow changeset" do
      workflow = insert(:workflow)
      assert %Ecto.Changeset{} = Workflows.change_workflow(workflow)
    end

    test "maybe_create_latest_snapshot/1 creates snapshot if missing latest" do
      workflow =
        insert(:simple_workflow, lock_version: 2, updated_at: DateTime.utc_now())

      refute Snapshot.get_current_for(workflow)

      assert capture_log(fn ->
               assert {:ok, %Snapshot{lock_version: 2}} =
                        Workflows.maybe_create_latest_snapshot(workflow)
             end) =~
               "Created latest snapshot for #{workflow.id} (last_update: #{workflow.updated_at})"
    end

    test "maybe_create_latest_snapshot/1 does not create snapshot if latest exists" do
      {:ok, workflow} =
        insert(:simple_workflow)
        |> Workflows.change_workflow(%{name: "some-updated-name"})
        |> Workflows.save_workflow(insert(:user))

      %{lock_version: lock_version} = Snapshot.get_current_for(workflow)

      assert {:ok, %Snapshot{lock_version: ^lock_version}} =
               Workflows.maybe_create_latest_snapshot(workflow)
    end

    test "save_workflow/1 emits telemetry event with is_sandbox: false for regular project" do
      project = insert(:project)
      user = insert(:user)
      event = [:lightning, :workflow, :saved]
      ref = :telemetry_test.attach_event_handlers(self(), [event])

      {:ok, _workflow} =
        Workflows.save_workflow(
          %{name: "telemetry-test", project_id: project.id},
          user
        )

      assert_received {^event, ^ref, %{}, %{is_sandbox: false}}
    end

    test "save_workflow/1 emits telemetry event with is_sandbox: true for sandbox project" do
      parent = insert(:project)
      sandbox = insert(:project, parent: parent)
      user = insert(:user)
      event = [:lightning, :workflow, :saved]
      ref = :telemetry_test.attach_event_handlers(self(), [event])

      {:ok, _workflow} =
        Workflows.save_workflow(
          %{name: "sandbox-telemetry", project_id: sandbox.id},
          user
        )

      assert_received {^event, ^ref, %{}, %{is_sandbox: true}}
    end
  end

  describe "save_workflow/3 rescue" do
    setup do
      Mimic.copy(Lightning.WorkflowVersions)
      :ok
    end

    @tag :capture_log
    test "duplicate primary key is rescued as a changeset error, not a raise (subsumes #4830)" do
      user = insert(:user)
      existing = insert(:simple_workflow)

      # A fresh (unpersisted) Workflow struct carrying an already-used id forces
      # an INSERT that violates workflows_pkey. Workflow declares NO
      # unique_constraint(:id), so Ecto raises Ecto.ConstraintError (undeclared
      # constraint) inside the transaction — the exact crash class #4830 left
      # deferred. The rescue must catch it. This is a STABLE rescue test: no
      # validate_uuid path intercepts it, so it exercises the rescue regardless
      # of which other PRs have landed.
      built = %Lightning.Workflows.Workflow{id: existing.id}
      assert built.__meta__.state == :built

      changeset =
        built
        |> Lightning.Workflows.Workflow.changeset(%{
          name: "dup",
          project_id: existing.project_id
        })

      assert {:error, %Ecto.Changeset{} = cs} =
               Workflows.save_workflow(changeset, user)

      refute cs.valid?
      assert cs.errors[:base]

      # workflows_pkey is allow-listed (#3) → friendly :base message, warning log.
      assert {"could not be saved due to a conflicting or missing reference", _} =
               cs.errors[:base]
    end

    @tag :capture_log
    test "rescued changeset reports :insert on the new-workflow path and :update on the existing-workflow path (#4)" do
      user = insert(:user)
      existing = insert(:simple_workflow)

      # INSERT PATH (:built → :insert). A fresh (unpersisted) Workflow struct
      # carrying an already-used id forces a workflows_pkey duplicate INSERT →
      # rescue. This is the #4830 new-workflow path (the attrs path builds the
      # same :built changeset; :id is not castable from attrs, so we set it on
      # the struct as the attrs path's changeset effectively does). The rescued
      # changeset must report action: :insert (derive_action/1), not the old
      # hard-coded :update.
      built = %Lightning.Workflows.Workflow{id: existing.id}
      assert built.__meta__.state == :built

      insert_changeset =
        Lightning.Workflows.Workflow.changeset(built, %{
          name: "dup-insert-#{System.unique_integer([:positive])}",
          project_id: existing.project_id
        })

      assert {:error, %Ecto.Changeset{action: :insert} = insert_cs} =
               Workflows.save_workflow(insert_changeset, user)

      assert insert_cs.errors[:base]

      # UPDATE PATH (:loaded → :update). A changeset built from a persisted
      # (:loaded) workflow that rescues must report action: :update. A loaded
      # workflow never re-INSERTs, so we drive the rescue via a malformed
      # :binary_id smuggled directly into the changes — it passes cast but raises
      # Ecto.ChangeError at dump time on the workflow's own :binary_id project_id
      # column during the UPDATE (caught by the first rescue clause). Both clauses
      # route through derive_action/1, so this still validates :update derivation.
      loaded = Repo.get!(Lightning.Workflows.Workflow, existing.id)
      assert loaded.__meta__.state == :loaded

      bad_changeset =
        loaded
        |> Ecto.Changeset.change(%{name: "renamed"})
        |> Map.update!(:changes, &Map.put(&1, :project_id, "not-a-binary-id"))

      assert {:error, %Ecto.Changeset{action: :update} = update_cs} =
               Workflows.save_workflow(bad_changeset, user)

      assert update_cs.errors[:base]
    end

    @tag :capture_log
    test "non-workflow constraint logs at :error and is still converted to a changeset (#3, Option A)" do
      # A NON-allow-listed Ecto.ConstraintError raised inside the transaction
      # (here a workflow_snapshots_pkey, a side-table constraint not in
      # @workflow_constraints) must be:
      #   - converted to a {:error, %Ecto.Changeset{}} (never crash — #4816), AND
      #   - logged at :error so a snapshot/audit/version bug is triageable rather
      #     than mislabelled as a quiet workflow warning.
      #
      # SEAM: there is no production seam to deterministically force a
      # non-workflow constraint through the transaction (snapshot ids are
      # DB-autogenerated; record_version swallows its own errors in a nested
      # transaction). We stub WorkflowVersions.record_version/2 — invoked inside
      # the outer Multi (workflows.ex Multi.run(:workflow_version, ...)) — to
      # raise an undeclared, non-workflow Ecto.ConstraintError, which propagates
      # out of Repo.transaction into save_workflow/3's ConstraintError rescue and
      # through constraint_error_changeset/2's non-workflow branch.
      user = insert(:user)
      workflow = insert(:simple_workflow)

      changeset =
        workflow
        |> Repo.preload([:jobs, :triggers, :edges])
        |> Workflows.change_workflow(%{name: "#{workflow.name}-side-table"})

      Mimic.stub(Lightning.WorkflowVersions, :record_version, fn _wf, _hash ->
        raise %Ecto.ConstraintError{
          type: :unique,
          constraint: "workflow_snapshots_pkey",
          message: "side-table pkey collision"
        }
      end)

      log =
        capture_log([level: :error], fn ->
          assert {:error, %Ecto.Changeset{} = cs} =
                   Workflows.save_workflow(changeset, user)

          refute cs.valid?
          assert cs.errors[:base]

          # Still mislabelled to the user as a generic workflow reference error
          # (Option A converts rather than re-raises).
          assert {"could not be saved due to a conflicting or missing reference",
                  _} = cs.errors[:base]
        end)

      assert log =~ "NON-workflow Ecto.ConstraintError"
      assert log =~ "workflow_snapshots_pkey"
    end

    @tag :capture_log
    test "Ecto.Query.CastError raised in the transaction is rescued as an invalid-value changeset" do
      user = insert(:user)
      workflow = insert(:simple_workflow)

      changeset =
        workflow
        |> Repo.preload([:jobs, :triggers, :edges])
        |> Workflows.change_workflow(%{name: "#{workflow.name}-casterror"})

      # No production seam raises Query.CastError on the workflow's own columns
      # (a malformed declared value raises ChangeError). Stub a transaction step
      # to raise it so the second rescue clause is genuinely exercised.
      Mimic.stub(Lightning.WorkflowVersions, :record_version, fn _wf, _hash ->
        raise Ecto.Query.CastError,
          type: :binary_id,
          value: "not-a-binary-id",
          message: "malformed binary_id reached a query"
      end)

      assert {:error, %Ecto.Changeset{} = cs} =
               Workflows.save_workflow(changeset, user)

      refute cs.valid?
      assert {"contains an invalid value", _} = cs.errors[:base]
    end

    test "stale lock still raises Ecto.StaleEntryError (not rescued)" do
      # Guards that the rescue does NOT swallow optimistic-lock conflicts
      # (mirrors the "saving with locks" test above).
      user = insert(:user)
      valid_attrs = params_with_assocs(:workflow, jobs: [params_for(:job)])

      {:ok, workflow} = Workflows.save_workflow(valid_attrs, insert(:user))

      {:ok, _} =
        Workflows.change_workflow(workflow, %{jobs: [params_for(:job)]})
        |> Workflows.save_workflow(user)

      assert_raise Ecto.StaleEntryError, fn ->
        Workflows.change_workflow(workflow, %{jobs: [params_for(:job)]})
        |> Workflows.save_workflow(user)
      end
    end
  end

  describe "save_workflow/3 cron cursor reconciliation" do
    @tag :capture_log
    test "rejects a cron cursor pointing at a job in another workflow" do
      # PRIMARY guard — genuinely red on plain main, unambiguously PR-C-dependent.
      #
      # A cron trigger in workflow A is driven through save_workflow/3 carrying a
      # cron_cursor_job_id that points at a job in a DIFFERENT workflow (B). The
      # trigger row IS in the changeset's `changes` (it is UPDATEd), so the FK is
      # actually exercised on write — unlike the same-workflow `jobs: []` delete,
      # which never UPDATEs the trigger and is therefore driven purely by the DB
      # cascade.
      #
      # On plain main the cursor FK is the ORIGINAL single-column FK
      # (REFERENCES jobs(id)). The foreign job row exists, so that FK ACCEPTS the
      # cross-workflow cursor → {:ok, _} with the corrupt cursor persisted. This
      # test asserts the opposite, so it is RED on main.
      #
      # With PR-C the FK is compound and same-workflow
      # (REFERENCES jobs(id, workflow_id)), so the cross-workflow cursor violates
      # it. Trigger declares foreign_key_constraint(:cron_cursor_job_id), so Ecto
      # maps the violation to a nested changeset error and the Multi returns
      # {:error, :workflow, changeset, _} → save_workflow/3 returns
      # {:error, %Ecto.Changeset{}} via the NORMAL Multi path (the declared
      # constraint means it does not need PR-A's rescue). Either way: no crash,
      # the cursor is never persisted cross-workflow.
      user = insert(:user)

      workflow_a = insert(:workflow)
      workflow_b = insert(:workflow)
      foreign_job = insert(:job, workflow: workflow_b)

      trigger =
        insert(:trigger,
          workflow: workflow_a,
          type: :cron,
          cron_expression: "* * * * *"
        )

      changeset =
        workflow_a
        |> Repo.preload([:jobs, :triggers, :edges])
        |> Workflows.change_workflow(%{
          triggers: [
            %{
              id: trigger.id,
              type: :cron,
              cron_expression: "* * * * *",
              cron_cursor_job_id: foreign_job.id
            }
          ]
        })

      # The trigger UPDATE is genuinely in the changeset (not the cascade path).
      assert :triggers in Map.keys(changeset.changes)

      result = Workflows.save_workflow(changeset, user)

      # Rejected cleanly with a field-targeted changeset error — never a crash,
      # never {:ok, _} (which is what plain main does).
      assert {:error, %Ecto.Changeset{valid?: false} = error_changeset} = result

      assert %{
               triggers: [
                 %{
                   cron_cursor_job_id: [
                     "cursor job doesn't exist, or is not in the same workflow"
                   ]
                 }
               ]
             } =
               Ecto.Changeset.traverse_errors(error_changeset, fn {msg, _opts} ->
                 msg
               end)

      # The corrupt cross-workflow cursor was never persisted.
      assert Repo.reload!(trigger).cron_cursor_job_id == nil
    end

    @tag :capture_log
    test "same-workflow cursor is nulled by the DB cascade when its job is deleted" do
      # Secondary, complementary guard for the same-workflow delete path.
      #
      # NOTE: this case is NOT red on plain main. The ORIGINAL single-column FK
      # was already created with ON DELETE SET NULL (migration
      # 20260314161323_add_cron_cursor_job_id_to_triggers.exs), so a same-workflow
      # cursor was ALWAYS nulled when its job was deleted, even before PR-C. And
      # change_workflow(%{jobs: []}) produces a changeset whose `changes` contains
      # only `:jobs` — the trigger row is NEVER UPDATEd here, so no FK-violation
      # write path fires. This test documents that the same-workflow delete
      # resolves the cursor deterministically via the cascade with no crash; it is
      # NOT the regression guard for PR-C (the cross-workflow test above is).
      user = insert(:user)

      workflow = insert(:workflow)
      job = insert(:job, workflow: workflow)

      trigger =
        insert(:trigger,
          workflow: workflow,
          type: :cron,
          cron_expression: "* * * * *"
        )
        |> Trigger.changeset(%{cron_cursor_job_id: job.id})
        |> Repo.update!()

      assert trigger.cron_cursor_job_id == job.id

      # Only `:jobs` is in the changeset's changes — the trigger is not UPDATEd.
      changeset =
        workflow
        |> Repo.preload([:jobs, :triggers, :edges])
        |> Workflows.change_workflow(%{jobs: []})

      assert Map.keys(changeset.changes) == [:jobs]

      assert {:ok, _workflow} = Workflows.save_workflow(changeset, user)

      # The DB cascade nulled the now-dangling cursor as part of the job DELETE.
      assert Repo.reload!(trigger).cron_cursor_job_id == nil
    end
  end

  describe "finders" do
    test "get_webhook_trigger/1 returns the trigger for a path" do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Repo.preload(:triggers)

      assert Workflows.get_webhook_trigger(trigger.id).id == trigger.id

      Ecto.Changeset.change(trigger, custom_path: "foo")
      |> Lightning.Repo.update!()

      assert Workflows.get_webhook_trigger(trigger.id) == nil

      assert Workflows.get_webhook_trigger("foo").id == trigger.id
    end

    test "get_webhook_trigger/1 does not return a trigger when type is cron" do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Repo.preload(:triggers)

      # Change the trigger type to cron
      Ecto.Changeset.change(trigger, type: :cron)
      |> Lightning.Repo.update!()

      # Should not return the trigger even though the ID matches
      assert Workflows.get_webhook_trigger(trigger.id) == nil

      # Set a custom path and verify it still doesn't return
      Ecto.Changeset.change(trigger, custom_path: "cron_path")
      |> Lightning.Repo.update!()

      assert Workflows.get_webhook_trigger("cron_path") == nil
    end

    test "get_jobs_for_cron_execution/0 returns jobs to run for a given time" do
      t1 = insert(:trigger, %{type: :cron, cron_expression: "5 0 * 8 *"})
      job_0 = insert(:job, %{workflow: t1.workflow})

      insert(:edge, %{
        workflow: t1.workflow,
        source_trigger: t1,
        target_job: job_0
      })

      t2 = insert(:trigger, %{type: :cron, cron_expression: "* * * * *"})
      job_1 = insert(:job, %{workflow: t2.workflow})

      e2 =
        insert(:edge, %{
          workflow: t2.workflow,
          source_trigger: t2,
          target_job: job_1
        })

      insert(:job, %{
        workflow: t2.workflow
      })

      [e | _] = Workflows.get_edges_for_cron_execution(DateTime.utc_now())

      assert e.id == e2.id
    end
  end

  describe "get_webhook_trigger/1" do
    test "returns a trigger when a matching custom_path is provided" do
      trigger = insert(:trigger, custom_path: "some_path")

      assert trigger |> unload_relation(:workflow) ==
               Workflows.get_webhook_trigger("some_path")
    end

    test "returns a trigger when a matching id is provided" do
      trigger = insert(:trigger)

      assert trigger |> unload_relation(:workflow) ==
               Workflows.get_webhook_trigger(trigger.id)
    end

    test "returns nil when no matching trigger is found" do
      insert(:trigger, custom_path: "some_path")
      assert Workflows.get_webhook_trigger("non_existent_path") == nil
    end
  end

  describe "get_edge_by_trigger/1" do
    test "returns an edge when associated trigger is provided" do
      workflow = insert(:workflow)
      trigger = insert(:trigger, workflow: workflow)
      job = insert(:job, workflow: workflow)

      edge =
        insert(:edge,
          workflow: workflow,
          source_trigger_id: trigger.id,
          target_job_id: job.id
        )

      assert edge |> unload_relation(:workflow) ==
               Workflows.get_edge_by_trigger(trigger)
               |> unload_relations([:target_job, :source_trigger])
    end

    test "returns nil when no associated edge is found" do
      trigger = insert(:trigger)
      assert Workflows.get_edge_by_trigger(trigger) == nil
    end
  end

  describe "create_edge/2" do
    setup do
      %{user: insert(:user)}
    end

    test "creates a new edge, and captures a snapshot", %{user: user} do
      workflow = insert(:workflow)

      {:ok, edge} =
        params_for(:edge, workflow: workflow)
        |> Workflows.create_edge(user)

      updated_workflow = Ecto.assoc(edge, :workflow) |> Repo.one!()

      assert updated_workflow.lock_version > workflow.lock_version

      snapshot = Workflows.Snapshot.get_current_for(workflow)

      snapshotted_edge = snapshot.edges |> Enum.find(&(&1.id == edge.id))

      assert snapshotted_edge.id == edge.id
      assert snapshotted_edge.updated_at == edge.updated_at

      fields = [
        :id,
        :enabled,
        :inserted_at,
        :updated_at,
        :condition_type,
        :condition_label,
        :source_job_id,
        :source_trigger_id,
        :target_job_id
      ]

      [snapshotted_edge, edge]
      |> Enum.map(fn model ->
        Map.take(model, fields)
      end)
      |> then(fn [lhs, rhs] ->
        assert lhs == rhs
      end)
    end

    test "snapshot is audited with the appropriate user", %{
      user: %{id: user_id} = user
    } do
      workflow = insert(:workflow)

      assert {:ok, _} =
               :edge
               |> params_for(workflow: workflow)
               |> Workflows.create_edge(user)

      assert %{actor_id: ^user_id} = Audit |> Repo.one!()
    end
  end

  describe "workflows and project spaces" do
    setup do
      project = insert(:project)
      w1 = insert(:workflow, project: project)
      w2 = insert(:workflow, project: project)

      w1_job =
        insert(:job,
          name: "webhook job",
          project: project,
          workflow: w1
          # trigger: %{type: :webhook}
        )

      insert(:edge,
        workflow: w1,
        source_job: w1_job,
        condition_type: :on_job_failure,
        target_job:
          insert(:job,
            name: "on fail",
            project: project,
            workflow: w1
          )
      )

      insert(:edge,
        workflow: w1,
        source_job: w1_job,
        condition_type: :on_job_success,
        target_job:
          insert(:job,
            name: "on success",
            project: project,
            workflow: w1
          )
      )

      w2_job =
        insert(:job,
          name: "other workflow",
          project: project,
          workflow: w2
          # trigger: %{type: :webhook}
        )

      insert(:edge,
        workflow: w2,
        source_job: w2_job,
        condition_type: :on_job_failure,
        target_job:
          insert(:job,
            name: "on fail",
            project: project,
            workflow: w2
          )
      )

      insert(:job,
        name: "unrelated job"
        # trigger: %{type: :webhook}
      )

      %{project: project, w1: w1, w2: w2}
    end

    test "get_workflows_for/1", %{project: project, w1: w1, w2: w2} do
      results = Workflows.get_workflows_for(project)

      assert length(results) == 2

      assert results |> MapSet.new(& &1.id) == [w1, w2] |> MapSet.new(& &1.id)

      for workflow <- results do
        assert is_nil(workflow.deleted_at)
        assert workflow.jobs != %Ecto.Association.NotLoaded{}

        for job <- workflow.jobs do
          assert job.credential != %Ecto.Association.NotLoaded{}
          assert job.workflow != %Ecto.Association.NotLoaded{}
        end

        assert workflow.triggers != %Ecto.Association.NotLoaded{}
        assert workflow.edges != %Ecto.Association.NotLoaded{}
      end
    end

    test "to_project_spec/1", %{project: project, w1: w1, w2: w2} do
      workflows = Workflows.get_workflows_for(project)

      project_space = Workflows.to_project_space(workflows)

      assert %{"id" => w1.id, "name" => w1.name} in project_space["workflows"]
      assert %{"id" => w2.id, "name" => w2.name} in project_space["workflows"]

      w1_id = w1.id

      assert project_space["jobs"]
             |> Enum.filter(&match?(%{"workflowId" => ^w1_id}, &1))
             |> length() == 3

      w2_id = w2.id

      assert project_space["jobs"]
             |> Enum.filter(&match?(%{"workflowId" => ^w2_id}, &1))
             |> length() == 2
    end

    test "mark_for_deletion/3", %{project: project, w1: w1, w2: w2} do
      user = insert(:user)

      workflows = Workflows.get_workflows_for(project)

      assert length(workflows) == 2

      assert w1.deleted_at == nil
      assert w2.deleted_at == nil

      %{id: trigger_1_id} = insert(:trigger, workflow: w1, enabled: true)
      %{id: trigger_2_id} = insert(:trigger, workflow: w1, enabled: true)
      %{id: trigger_3_id} = insert(:trigger, workflow: w2, enabled: true)

      # request workflow deletion (and disable all associated triggers)
      assert {:ok, _workflow} = Workflows.mark_for_deletion(w1, user)

      assert Workflows.get_workflow!(w1.id).deleted_at != nil
      assert Workflows.get_workflow!(w2.id).deleted_at == nil

      # check that get_workflows_for/1 doesn't return those marked for deletion
      assert length(Workflows.get_workflows_for(project)) == 1

      assert Repo.get(Trigger, trigger_1_id) |> Map.get(:enabled) == false
      assert Repo.get(Trigger, trigger_2_id) |> Map.get(:enabled) == false
      assert Repo.get(Trigger, trigger_3_id) |> Map.get(:enabled) == true
    end

    test "mark_for_deletion/3 creates an audit event", %{
      w1: %{id: workflow_id} = workflow
    } do
      %{id: user_id} = user = insert(:user)

      assert {:ok, _workflow} = Workflows.mark_for_deletion(workflow, user)

      audit = Repo.one!(Audit)

      assert %{
               event: "marked_for_deletion",
               item_id: ^workflow_id,
               actor_id: ^user_id
             } = audit
    end

    test "mark_for_deletion/3 publishes events for Kafka triggers", %{w1: w1} do
      user = insert(:user)

      %{id: kafka_trigger_1_id} =
        insert(:trigger, workflow: w1, enabled: true, type: :kafka)

      %{id: webhook_trigger_id} =
        insert(:trigger, workflow: w1, enabled: true, type: :webhook)

      %{id: kafka_trigger_2_id} =
        insert(:trigger, workflow: w1, enabled: true, type: :kafka)

      Events.subscribe_to_kafka_trigger_updated()

      assert {:ok, _workflow} = Workflows.mark_for_deletion(w1, user)

      refute_received %KafkaTriggerUpdated{trigger_id: ^webhook_trigger_id}
      assert_received %KafkaTriggerUpdated{trigger_id: ^kafka_trigger_2_id}
      assert_received %KafkaTriggerUpdated{trigger_id: ^kafka_trigger_1_id}
    end

    test "soft_delete_changeset/1 marks deleted and frees the name in one step" do
      project = insert(:project)
      workflow = insert(:workflow, project: project, name: "Shared Transition")

      changeset =
        workflow
        |> Ecto.Changeset.change()
        |> Workflows.soft_delete_changeset()

      assert %DateTime{} = Ecto.Changeset.get_change(changeset, :deleted_at)

      assert Ecto.Changeset.get_change(changeset, :name) ==
               "Shared Transition_del"
    end

    test "mark_for_deletion/3 renames workflow with _del suffix" do
      # Use a separate project to avoid pollution from setup
      project = insert(:project)
      user = insert(:user)
      w1 = insert(:workflow, project: project, name: "Test Workflow")

      assert {:ok, %{workflow: workflow}} = Workflows.mark_for_deletion(w1, user)
      assert workflow.name == "Test Workflow_del"

      # Test incrementing when deleting another workflow with the same name
      w2 = insert(:workflow, project: project, name: "Test Workflow")

      assert {:ok, %{workflow: workflow2}} =
               Workflows.mark_for_deletion(w2, user)

      assert workflow2.name == "Test Workflow_del1"

      # Test incrementing again
      w3 = insert(:workflow, project: project, name: "Test Workflow")

      assert {:ok, %{workflow: workflow3}} =
               Workflows.mark_for_deletion(w3, user)

      assert workflow3.name == "Test Workflow_del2"
    end

    test "mark_for_deletion/3 does not conflict with active workflows ending in _del" do
      # An active workflow named "water_gap_analysis_del" (where _del is Delaware)
      # should not interfere with deleting "water_gap_analysis"
      project = insert(:project)
      user = insert(:user)

      # Active workflow with name ending in _del (not deleted)
      _delaware_workflow =
        insert(:workflow, project: project, name: "water_gap_analysis_del")

      # Workflow to be deleted
      w1 = insert(:workflow, project: project, name: "water_gap_analysis")

      # Should still get _del suffix since the existing _del workflow is not deleted
      assert {:ok, %{workflow: deleted}} = Workflows.mark_for_deletion(w1, user)
      assert deleted.name == "water_gap_analysis_del1"

      assert {:ok, %{workflow: deleted}} = Workflows.mark_for_deletion(w1, user)
      assert deleted.name == "water_gap_analysis_del2"
    end

    test "allows reusing workflow name after marking for deletion, then validates error when using deleted workflow name" do
      project = insert(:project)
      user = insert(:user)
      w1 = insert(:workflow, project: project, name: "My Workflow")

      # Mark workflow for deletion
      assert {:ok, %{workflow: deleted_workflow}} =
               Workflows.mark_for_deletion(w1, user)

      assert deleted_workflow.name == "My Workflow_del"

      # Should be able to create a new workflow with the original name
      assert {:ok, new_workflow} =
               Workflows.save_workflow(
                 %{name: "My Workflow", project_id: project.id},
                 user
               )

      assert new_workflow.name == "My Workflow"
      assert new_workflow.deleted_at == nil

      # Should NOT be able to create another workflow with the deleted workflow's name
      assert {:error, changeset} =
               Workflows.save_workflow(
                 %{name: "My Workflow_del", project_id: project.id},
                 user
               )

      assert errors_on(changeset) == %{
               name: [
                 "A workflow with this name already exists (possibly pending deletion) in this project."
               ]
             }
    end
  end

  describe "get_workflows_for/2" do
    setup do
      project = insert(:project)

      w1 = insert(:workflow, project: project, name: "API Gateway")
      w2 = insert(:workflow, project: project, name: "Background Jobs")
      w3 = insert(:workflow, project: project, name: "REST API")

      insert(:trigger, workflow: w1, enabled: true)
      insert(:trigger, workflow: w2, enabled: false)
      insert(:trigger, workflow: w3, enabled: true)

      %{project: project, w1: w1, w2: w2, w3: w3}
    end

    test "returns all workflows for a project", %{project: project} do
      workflows = Workflows.get_workflows_for(project)
      assert length(workflows) == 3
    end

    test "filters workflows by search term", %{project: project} do
      workflows = Workflows.get_workflows_for(project, search: "api")
      assert length(workflows) == 2

      assert Enum.map(workflows, & &1.name) |> Enum.sort() == [
               "API Gateway",
               "REST API"
             ]
    end

    test "returns empty list for non-matching search", %{project: project} do
      workflows = Workflows.get_workflows_for(project, search: "nonexistent")
      assert workflows == []
    end

    test "sorts workflows by name ascending", %{project: project} do
      workflows = Workflows.get_workflows_for(project, order_by: {:name, :asc})
      names = Enum.map(workflows, & &1.name)
      assert names == ["API Gateway", "Background Jobs", "REST API"]
    end

    test "sorts workflows by name descending", %{project: project} do
      workflows = Workflows.get_workflows_for(project, order_by: {:name, :desc})
      names = Enum.map(workflows, & &1.name)
      assert names == ["REST API", "Background Jobs", "API Gateway"]
    end

    test "sorts workflows by enabled state ascending", %{project: project} do
      workflows =
        Workflows.get_workflows_for(project, order_by: {:enabled, :asc})

      first_workflow = List.first(workflows)
      last_workflow = List.last(workflows)

      assert first_workflow.triggers |> Enum.any?(& &1.enabled) == false
      assert last_workflow.triggers |> Enum.any?(& &1.enabled) == true
    end

    test "sorts workflows by enabled state descending", %{project: project} do
      workflows =
        Workflows.get_workflows_for(project, order_by: {:enabled, :desc})

      first_workflow = List.first(workflows)
      last_workflow = List.last(workflows)

      assert first_workflow.triggers |> Enum.any?(& &1.enabled) == true
      assert last_workflow.triggers |> Enum.any?(& &1.enabled) == false
    end

    test "uses default sorting for invalid order_by", %{project: project} do
      workflows =
        Workflows.get_workflows_for(project, order_by: {:invalid, :asc})

      names = Enum.map(workflows, & &1.name)
      assert names == ["API Gateway", "Background Jobs", "REST API"]
    end

    test "customizes preloaded associations", %{project: project} do
      workflows = Workflows.get_workflows_for(project, include: [:triggers])
      workflow = List.first(workflows)

      assert workflow.triggers != %Ecto.Association.NotLoaded{}
      assert match?(%Ecto.Association.NotLoaded{}, workflow.edges)
    end

    test "always includes triggers even if not specified", %{project: project} do
      workflows = Workflows.get_workflows_for(project, include: [:edges])
      workflow = List.first(workflows)

      assert workflow.triggers != %Ecto.Association.NotLoaded{}
      assert workflow.edges != %Ecto.Association.NotLoaded{}
    end

    test "ignores empty search term", %{project: project} do
      workflows = Workflows.get_workflows_for(project, search: "")
      assert length(workflows) == 3
    end
  end

  defp assert_trigger_state_audit(
         workflow_id,
         user_id,
         before_state,
         after_state,
         event
       ) do
    audit =
      from(a in Audit, where: a.event in ["enabled", "disabled"]) |> Repo.one!()

    assert %{
             event: ^event,
             item_type: "workflow",
             item_id: ^workflow_id,
             actor_id: ^user_id,
             changes: %{
               before: %{"enabled" => ^before_state},
               after: %{"enabled" => ^after_state}
             }
           } = audit
  end

  describe "editable_state?/2" do
    test "live workflows are read-only on main but editable in a sandbox" do
      main = build(:project)
      sandbox = build(:project, parent_id: Ecto.UUID.generate())

      refute Workflows.editable_state?(build(:workflow, state: :live), main)
      assert Workflows.editable_state?(build(:workflow, state: :live), sandbox)
      assert Workflows.editable_state?(build(:workflow, state: :draft), main)
    end
  end

  describe "get_workflow_by_name/2" do
    test "finds the active workflow by name, scoped to the project" do
      project = insert(:project)
      other_project = insert(:project)

      workflow = insert(:workflow, project: project, name: "payroll")
      insert(:workflow, project: other_project, name: "payroll")

      insert(:workflow,
        project: project,
        name: "archived",
        deleted_at: DateTime.utc_now()
      )

      assert %{id: id} = Workflows.get_workflow_by_name(project.id, "payroll")
      assert id == workflow.id

      # A soft-deleted workflow and an unknown name both resolve to nil.
      assert Workflows.get_workflow_by_name(project.id, "archived") == nil
      assert Workflows.get_workflow_by_name(project.id, "missing") == nil
    end
  end

  defp create_workflow(opts \\ []) do
    enabled = Keyword.get(opts, :enabled, false)
    trigger = build(:trigger, type: :cron, enabled: enabled)
    job = build(:job)

    build(:workflow)
    |> with_job(job)
    |> with_trigger(trigger)
    |> with_edge({trigger, job})
    |> insert()
  end
end
