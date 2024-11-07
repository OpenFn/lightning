defmodule Lightning.WorkOrdersTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Ecto.Multi
  alias Lightning.Auditing.Audit
  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.Message
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord
  alias Lightning.Workflows.Snapshot
  alias Lightning.WorkOrders
  alias Lightning.WorkOrders.Events
  alias Lightning.WorkOrders.RetryManyWorkOrdersJob

  describe "create_for/2" do
    setup context do
      trigger_type = context |> Map.get(:trigger_type, :webhook)

      job = build(:job)
      trigger = build(:trigger, type: trigger_type)

      workflow =
        build(:workflow)
        |> with_job(job)
        |> with_trigger(trigger)
        |> with_edge({trigger, job})
        |> insert()

      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      record_changeset =
        TriggerKafkaMessageRecord.changeset(
          %TriggerKafkaMessageRecord{},
          %{topic_partition_offset: "foo-bar-baz", trigger_id: trigger.id}
        )

      multi =
        Multi.new()
        |> Multi.insert(:record, record_changeset)

      %{
        workflow: workflow,
        trigger: trigger |> Repo.reload!(),
        job: job |> Repo.reload!(),
        snapshot: snapshot,
        multi: multi
      }
    end

    @tag trigger_type: :webhook
    test "with a webhook trigger", context do
      %{workflow: workflow, trigger: trigger, snapshot: snapshot} = context
      project_id = workflow.project_id

      project =
        Repo.get(Lightning.Projects.Project, project_id)
        |> Lightning.Projects.Project.changeset(%{retention_policy: :erase_all})
        |> Repo.update!()

      Lightning.WorkOrders.subscribe(project_id)
      dataclip = insert(:dataclip, project: project)

      {:ok, workorder} =
        WorkOrders.create_for(trigger, dataclip: dataclip, workflow: workflow)

      assert workorder.snapshot_id == snapshot.id
      assert workorder.workflow_id == workflow.id
      assert workorder.trigger_id == trigger.id
      assert workorder.dataclip_id == dataclip.id
      assert workorder.dataclip.type == :http_request

      [run] = workorder.runs

      assert run.starting_trigger.id == trigger.id
      assert run.dataclip_id == dataclip.id

      assert run.options == %Lightning.Runs.RunOptions{
               save_dataclips: false,
               run_timeout_ms: 300_000
             }

      workorder_id = workorder.id

      assert_received %Events.RunCreated{
        project_id: ^project_id
      }

      assert_received %Events.WorkOrderCreated{
        work_order: %{id: ^workorder_id}
      }
    end

    test "with a webhook trigger (without runs)", context do
      %{workflow: workflow, trigger: trigger, snapshot: snapshot} = context

      project_id = workflow.project_id
      Lightning.WorkOrders.subscribe(project_id)
      dataclip = insert(:dataclip)

      {:ok, %{id: workorder_id} = workorder} =
        WorkOrders.create_for(trigger,
          dataclip: dataclip,
          workflow: workflow,
          without_run: true
        )

      assert workorder.workflow_id == workflow.id
      assert workorder.snapshot_id == snapshot.id
      assert workorder.trigger_id == trigger.id
      assert workorder.dataclip_id == dataclip.id
      assert workorder.dataclip.type == :http_request
      assert workorder.runs == []

      refute_received %Events.RunCreated{
        project_id: ^project_id
      }

      assert_received %Events.WorkOrderCreated{
        work_order: %{id: ^workorder_id}
      }
    end

    @tag trigger_type: :cron
    test "with a cron trigger", context do
      %{workflow: workflow, trigger: trigger, snapshot: snapshot} = context

      Lightning.WorkOrders.subscribe(workflow.project_id)

      dataclip = insert(:dataclip)

      {:ok, workorder} =
        WorkOrders.create_for(trigger, dataclip: dataclip, workflow: workflow)

      assert workorder.workflow_id == workflow.id
      assert workorder.snapshot_id == snapshot.id
      assert workorder.trigger_id == trigger.id
      assert workorder.dataclip_id == dataclip.id
      assert workorder.dataclip.type == :http_request

      [run] = workorder.runs

      assert run.starting_trigger.id == trigger.id
      assert run.snapshot_id == snapshot.id

      assert run.options == %Lightning.Runs.RunOptions{
               save_dataclips: true,
               run_timeout_ms: 300_000
             }

      workorder_id = workorder.id

      assert_received %Events.WorkOrderCreated{
        work_order: %{id: ^workorder_id}
      }
    end

    @tag trigger_type: :kafka
    test "with a provided multi instance - also executes the multi", %{
      multi: multi,
      trigger: trigger,
      workflow: workflow
    } do
      project_id = workflow.project_id

      project =
        Repo.get(Lightning.Projects.Project, project_id)
        |> Lightning.Projects.Project.changeset(%{retention_policy: :erase_all})
        |> Repo.update!()

      Lightning.WorkOrders.subscribe(project_id)
      dataclip = insert(:dataclip, project: project)

      assert {:ok, _workorder} =
               WorkOrders.create_for(
                 trigger,
                 multi,
                 dataclip: dataclip,
                 workflow: workflow
               )

      assert TriggerKafkaMessageRecord
             |> Repo.get_by(trigger_id: trigger.id) != nil
    end

    @tag trigger_type: :cron
    test "with a trigger assigns the provided actor to the event", %{
      snapshot: snapshot,
      trigger: trigger,
      workflow: workflow
    } do
      Repo.delete!(snapshot)

      Lightning.WorkOrders.subscribe(workflow.project_id)

      dataclip = insert(:dataclip)
      %{id: actor_id} = actor = insert(:user)

      WorkOrders.create_for(
        trigger,
        actor: actor,
        dataclip: dataclip,
        workflow: workflow
      )

      assert %{actor_id: ^actor_id} = Repo.one(Audit)
    end

    test "with a manual workorder", context do
      %{workflow: workflow, job: job, snapshot: snapshot} = context
      user = insert(:user)
      project_id = workflow.project_id
      Lightning.WorkOrders.subscribe(project_id)

      assert {:ok, manual} =
               Lightning.WorkOrders.Manual.new(
                 %{
                   "body" =>
                     Jason.encode!(%{
                       "key_left" => "value_left",
                       "configuration" => %{"password" => "secret"}
                     })
                 },
                 workflow: workflow,
                 project: workflow.project,
                 job: job,
                 created_by: user
               )
               |> Ecto.Changeset.apply_action(:validate)

      assert {:ok, %{id: workorder_id, runs: [run]} = workorder} =
               WorkOrders.create_for(manual)

      assert workorder.snapshot_id == snapshot.id
      assert workorder.dataclip.type == :saved_input

      assert workorder.dataclip.body == %{
               "key_left" => "value_left"
             }

      assert run.priority == :immediate
      assert run.created_by.id == user.id
      assert run.snapshot_id == snapshot.id

      assert run.options == %Lightning.Runs.RunOptions{
               save_dataclips: true,
               run_timeout_ms: 300_000
             }

      assert_received %Events.RunCreated{
        project_id: ^project_id
      }

      assert_received %Events.WorkOrderCreated{
        work_order: %{id: ^workorder_id}
      }
    end

    test "assigns the created_by of the Manual as the actor for the audit", %{
      job: job,
      snapshot: snapshot,
      workflow: workflow
    } do
      Repo.delete(snapshot)

      %{id: user_id} = user = insert(:user)
      project_id = workflow.project_id
      Lightning.WorkOrders.subscribe(project_id)

      {:ok, manual} =
        Lightning.WorkOrders.Manual.new(
          %{
            "body" =>
            Jason.encode!(%{
              "key_left" => "value_left",
              "configuration" => %{"password" => "secret"}
            })
          },
          workflow: workflow,
          project: workflow.project,
          job: job,
          created_by: user
        )
        |> Ecto.Changeset.apply_action(:validate)

      WorkOrders.create_for(manual)

      assert %{actor_id: ^user_id} = Repo.one!(Audit)
    end

    test "with a job", %{job: job, workflow: workflow, snapshot: snapshot} do
      project_id = workflow.project_id

      project =
        Repo.get(Lightning.Projects.Project, project_id)
        |> Lightning.Projects.Project.changeset(%{retention_policy: :erase_all})
        |> Repo.update!()

      dataclip = insert(:dataclip, project: project)
      user = insert(:user)

      {:ok, workorder} =
        WorkOrders.create_for(
          job,
          dataclip: dataclip,
          workflow: workflow,
          created_by: user
        )

      assert workorder.snapshot_id == snapshot.id
      assert workorder.workflow_id == workflow.id
      assert workorder.dataclip_id == dataclip.id

      [run] = workorder.runs

      assert run.starting_job == job
      assert run.dataclip == dataclip
    end

    test "with a job and a passed in multi, executes the multi", %{
      job: job,
      multi: multi,
      trigger: trigger,
      workflow: workflow
    } do
      project_id = workflow.project_id

      project =
        Repo.get(Lightning.Projects.Project, project_id)
        |> Lightning.Projects.Project.changeset(%{retention_policy: :erase_all})
        |> Repo.update!()

      dataclip = insert(:dataclip, project: project)
      user = insert(:user)

      assert {:ok, _workorder} =
               WorkOrders.create_for(
                 job,
                 multi,
                 dataclip: dataclip,
                 workflow: workflow,
                 created_by: user
               )

      assert TriggerKafkaMessageRecord
             |> Repo.get_by(trigger_id: trigger.id) != nil
    end

    test "with a job, assigns the actor to the audit if snapshot created", %{
      job: job,
      workflow: workflow,
    } do
      Repo.delete_all(Snapshot)

      project_id = workflow.project_id

      project =
        Repo.get(Lightning.Projects.Project, project_id)
        |> Lightning.Projects.Project.changeset(%{retention_policy: :erase_all})
        |> Repo.update!()

      dataclip = insert(:dataclip, project: project)
      user = insert(:user)
      %{id: actor_id} = actor = insert(:user)

      WorkOrders.create_for(
        job,
        actor: actor,
        dataclip: dataclip,
        workflow: workflow,
        created_by: user
      )

      assert %{actor_id: ^actor_id} = Repo.one!(Audit)
    end
  end

  describe "retry/1" do
    setup do
      [job_a, job_b, job_c] = jobs = build_list(3, :job)
      trigger = build(:trigger, type: :webhook)

      workflow =
        build(:workflow)
        |> with_job(job_a)
        |> with_job(job_b)
        |> with_job(job_c)
        |> with_trigger(trigger)
        |> with_edge({trigger, job_a})
        |> with_edge({job_a, job_b})
        |> with_edge({job_b, job_c})
        |> insert()

      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      %{
        workflow: workflow,
        snapshot: snapshot,
        trigger: trigger |> Repo.reload!(),
        jobs: jobs |> Repo.reload!()
      }
    end

    test "retrying a run from the start", %{
      workflow: %{project_id: project_id} = workflow,
      snapshot: snapshot,
      trigger: trigger,
      jobs: [job | _rest]
    } do
      user = insert(:user)
      dataclip = insert(:dataclip)
      # create existing complete run
      %{id: wo_id, runs: [%{id: run_id} = run]} =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: dataclip,
          runs: [
            %{
              state: :failed,
              dataclip: dataclip,
              snapshot: snapshot,
              starting_trigger: trigger,
              steps: [
                step = insert(:step, job: job, input_dataclip: dataclip)
              ]
            }
          ]
        )

      Events.subscribe(project_id)

      # This isn't the best place to test for this specific case.
      Lightning.Workflows.change_workflow(workflow, %{name: "new name"})
      |> Lightning.Workflows.save_workflow(insert(:user))

      snapshot2 = Lightning.Workflows.Snapshot.get_current_for(workflow)

      {:ok, %{id: new_run_id} = retry_run} =
        WorkOrders.retry(run, step, created_by: user)

      assert_received %Events.WorkOrderUpdated{
        work_order: %{id: ^wo_id}
      }

      refute_received %Events.RunCreated{
        run: %{id: ^run_id},
        project_id: ^project_id
      }

      assert_received %Events.RunCreated{
        run: %{id: ^new_run_id},
        project_id: ^project_id
      }

      refute retry_run.id == run.id
      assert retry_run.dataclip_id == dataclip.id
      assert retry_run.starting_job.id == job.id
      assert retry_run.created_by.id == user.id
      assert retry_run.work_order_id == run.work_order_id

      assert retry_run.options == %Lightning.Runs.RunOptions{
               save_dataclips: true,
               run_timeout_ms: 300_000
             }

      assert retry_run.snapshot_id == snapshot2.id,
             "Retrying automatically picks the newest snapshot for a workflow"

      assert retry_run.state == :available

      assert retry_run |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying a run from the start should not copy over steps"
    end

    test "retrying a run from a step that isn't the first", %{
      workflow: workflow,
      snapshot: snapshot,
      trigger: trigger,
      jobs: [job_a, job_b, job_c]
    } do
      user = insert(:user)
      dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      # create existing complete run
      %{runs: [run]} =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: dataclip,
          runs: [
            %{
              state: :failed,
              dataclip: dataclip,
              snapshot: snapshot,
              starting_trigger: trigger,
              steps: [
                first_step =
                  insert(:step,
                    job: job_a,
                    input_dataclip: dataclip,
                    output_dataclip: output_dataclip
                  ),
                second_step =
                  insert(:step, job: job_b, input_dataclip: output_dataclip),
                insert(:step, job: job_c)
              ]
            }
          ]
        )

      {:ok, retry_run} =
        WorkOrders.retry(run, second_step, created_by: user)

      refute retry_run.id == run.id
      assert retry_run.dataclip_id == output_dataclip.id
      assert retry_run.starting_job.id == job_b.id
      assert retry_run.created_by.id == user.id
      assert retry_run.work_order_id == run.work_order_id
      assert retry_run.state == :available

      assert retry_run.options == %Lightning.Runs.RunOptions{
               save_dataclips: true,
               run_timeout_ms: 300_000
             }

      steps = Ecto.assoc(retry_run, :steps) |> Repo.all()
      assert steps |> Enum.map(& &1.id) == [first_step.id]
    end

    test "retrying a run from a step with a wiped dataclip", %{
      workflow: workflow,
      snapshot: snapshot,
      trigger: trigger,
      jobs: [job | _rest]
    } do
      user = insert(:user)
      dataclip = insert(:dataclip, wiped_at: DateTime.utc_now())
      # create existing complete run
      %{runs: [run]} =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: dataclip,
          runs: [
            %{
              state: :failed,
              dataclip: dataclip,
              snapshot: snapshot,
              starting_trigger: trigger,
              steps: [
                step = insert(:step, job: job, input_dataclip: dataclip)
              ]
            }
          ]
        )

      {:error, changeset} = WorkOrders.retry(run, step, created_by: user)

      assert changeset.errors == [
               {:input_dataclip_id,
                {"cannot retry run using a wiped dataclip", []}}
             ]
    end

    test "retrying a run from a step with a dropped dataclip", %{
      workflow: workflow,
      snapshot: snapshot,
      trigger: trigger,
      jobs: [job_a, job_b, job_c]
    } do
      user = insert(:user)
      dataclip = insert(:dataclip)

      # create existing complete run
      %{runs: [run]} =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: dataclip,
          runs: [
            %{
              state: :failed,
              dataclip: dataclip,
              snapshot: snapshot,
              starting_trigger: trigger,
              steps: [
                insert(:step,
                  job: job_a,
                  input_dataclip: dataclip,
                  output_dataclip: nil
                ),
                second_step =
                  insert(:step, job: job_b, input_dataclip: nil),
                insert(:step, job: job_c)
              ]
            }
          ]
        )

      {:error, changeset} =
        WorkOrders.retry(run, second_step, created_by: user)

      assert changeset.errors == [
               {:input_dataclip_id,
                {"cannot retry run using a wiped dataclip", []}}
             ]
    end

    test "updates workorder state", %{
      snapshot: snapshot,
      workflow: workflow,
      trigger: trigger,
      jobs: [job | _rest]
    } do
      user = insert(:user)
      dataclip = insert(:dataclip)
      # create existing complete run
      %{runs: [run]} =
        workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot,
          state: :failed,
          runs: [
            %{
              state: :failed,
              dataclip: dataclip,
              starting_trigger: trigger,
              snapshot: snapshot,
              steps: [
                step = insert(:step, job: job, input_dataclip: dataclip)
              ]
            }
          ]
        )

      assert workorder.state == :failed
      Lightning.WorkOrders.subscribe(workflow.project_id)

      {:ok, _run} = WorkOrders.retry(run, step, created_by: user)

      updated_workorder = Lightning.Repo.get(Lightning.WorkOrder, workorder.id)

      assert updated_workorder.state == :pending

      workorder_id = workorder.id

      assert_received %Events.WorkOrderUpdated{
        work_order: %{id: ^workorder_id}
      }
    end

    test "if snapshot is created, uses creating user as audit actor", %{
      workflow: workflow,
      snapshot: snapshot,
      trigger: trigger,
      jobs: [job_a, job_b, job_c]
    } do
      %{id: user_id} = user = insert(:user)
      dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      # create existing complete run
      %{runs: [run]} =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          runs: [
            %{
              state: :failed,
              dataclip: dataclip,
              starting_trigger: trigger,
              steps: [
                  insert(:step,
                    job: job_a,
                    input_dataclip: dataclip,
                    output_dataclip: output_dataclip
                  ),
                second_step =
                  insert(:step, job: job_b, input_dataclip: output_dataclip),
                insert(:step, job: job_c)
              ]
            }
          ]
        )

      Repo.delete(snapshot)

      WorkOrders.retry(run, second_step, created_by: user)

      assert %{actor_id: ^user_id} = Repo.one!(Audit)
    end
  end

  describe "retry_many/3" do
    setup do
      Mox.stub(MockUsageLimiter, :limit_action, fn _action, _ctx ->
        :ok
      end)

      [job_a, job_b, job_c] = jobs = build_list(3, :job)
      trigger = build(:trigger, type: :webhook)

      workflow =
        build(:workflow)
        |> with_job(job_a)
        |> with_job(job_b)
        |> with_job(job_c)
        |> with_trigger(trigger)
        |> with_edge({trigger, job_a})
        |> with_edge({job_a, job_b})
        |> with_edge({job_b, job_c})
        |> insert()

      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      %{
        workflow: workflow,
        snapshot: snapshot,
        trigger: Repo.reload!(trigger),
        jobs: Repo.reload!(jobs),
        user: insert(:user)
      }
    end

    test "retrying one WorkOrder with a single run without steps from start job skips the retry",
         %{
           snapshot: snapshot,
           workflow: workflow,
           trigger: trigger,
           jobs: [job_a, _job_b, _job_c],
           user: user
         } do
      input_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: input_dataclip,
          snapshot: snapshot,
          runs: [
            %{
              state: :failed,
              dataclip: input_dataclip,
              starting_trigger: trigger,
              snapshot: snapshot,
              steps: []
            }
          ]
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder.id,
               starting_job_id: job_a.id
             )

      {:ok, 0, 0} =
        WorkOrders.retry_many([workorder], job_a.id,
          created_by: user,
          project_id: workflow.project_id
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder.id,
               starting_job_id: job_a.id
             )
    end

    test "retrying one WorkOrder with a single run from start job", %{
      snapshot: snapshot,
      workflow: workflow,
      trigger: trigger,
      jobs: [job_a, job_b, job_c],
      user: user
    } do
      input_dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: input_dataclip,
          snapshot: snapshot,
          runs: [
            %{
              state: :failed,
              dataclip: input_dataclip,
              starting_trigger: trigger,
              snapshot: snapshot,
              steps: [
                step_a =
                  insert(:step,
                    job: job_a,
                    input_dataclip: input_dataclip,
                    output_dataclip: output_dataclip
                  ),
                insert(:step,
                  job: job_b,
                  input_dataclip: output_dataclip,
                  output_dataclip: build(:dataclip)
                ),
                insert(:step,
                  job: job_c,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                )
              ]
            }
          ]
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder.id,
               starting_job_id: job_a.id
             )

      {:ok, 1, 0} =
        WorkOrders.retry_many([workorder], job_a.id,
          created_by: user,
          project_id: workflow.project_id
        )

      retry_run =
        Repo.get_by(Lightning.Run,
          work_order_id: workorder.id,
          starting_job_id: job_a.id
        )

      [old_run] = workorder.runs

      refute retry_run.id == old_run.id
      assert retry_run.dataclip_id == step_a.input_dataclip_id
      assert retry_run.starting_trigger_id |> is_nil()
      assert retry_run.starting_job_id == job_a.id
      assert retry_run.created_by_id == user.id
      assert retry_run.work_order_id == old_run.work_order_id
      assert retry_run.state == :available

      assert retry_run.options == %Lightning.Runs.RunOptions{
               save_dataclips: true,
               run_timeout_ms: 300_000
             }

      assert retry_run |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying a run from the start should not copy over steps"
    end

    test "retrying one WorkOrder with a single run from mid way job", %{
      jobs: [job_a, job_b, job_c],
      snapshot: snapshot,
      trigger: trigger,
      user: user,
      workflow: workflow
    } do
      input_dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      # create existing complete run
      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: input_dataclip,
          snapshot: snapshot,
          runs: [
            %{
              state: :failed,
              dataclip: input_dataclip,
              snapshot: snapshot,
              starting_trigger: trigger,
              steps: [
                step_a =
                  insert(:step,
                    job: job_a,
                    input_dataclip: input_dataclip,
                    output_dataclip: output_dataclip
                  ),
                step_b =
                  insert(:step,
                    job: job_b,
                    input_dataclip: output_dataclip,
                    output_dataclip: build(:dataclip)
                  ),
                insert(:step,
                  job: job_c,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                )
              ]
            }
          ]
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder.id,
               starting_job_id: job_b.id
             )

      {:ok, 1, 0} =
        WorkOrders.retry_many([workorder], job_b.id,
          created_by: user,
          project_id: workflow.project_id
        )

      retry_run =
        Repo.get_by(Lightning.Run,
          work_order_id: workorder.id,
          starting_job_id: job_b.id
        )

      [old_run] = workorder.runs

      refute retry_run.id == old_run.id
      assert retry_run.dataclip_id == step_b.input_dataclip_id
      assert retry_run.starting_trigger_id |> is_nil()
      assert retry_run.starting_job_id == job_b.id
      assert retry_run.created_by_id == user.id
      assert retry_run.work_order_id == old_run.work_order_id
      assert retry_run.state == :available

      steps = Ecto.assoc(retry_run, :steps) |> Repo.all()
      assert steps |> Enum.map(& &1.id) == [step_a.id]
    end

    test "retrying one WorkOrder with a multiple runs from start job", %{
      jobs: [job_a, job_b, job_c],
      snapshot: snapshot,
      trigger: trigger,
      user: user,
      workflow: workflow
    } do
      input_dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          dataclip: input_dataclip,
          snapshot: snapshot,
          trigger: trigger,
          workflow: workflow
        )

      run_1 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
          snapshot: snapshot,
          starting_trigger: trigger,
          steps: [
            step_1_a =
              insert(:step,
                job: job_a,
                input_dataclip: input_dataclip,
                output_dataclip: output_dataclip
              )
          ]
        )

      run_2 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: build(:dataclip),
          snapshot: snapshot,
          starting_job: job_a,
          steps: [
            step_2_a =
              insert(:step,
                job: job_a,
                input_dataclip: build(:dataclip),
                output_dataclip: build(:dataclip)
              ),
            insert(:step,
              job: job_b,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
            insert(:step,
              job: job_c,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            )
          ]
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      for run <- runs do
        assert run.id in [run_1.id, run_2.id]
      end

      {:ok, 1, 0} =
        WorkOrders.retry_many([workorder], job_a.id,
          created_by: user,
          project_id: workflow.project_id
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      [retry_run] =
        Enum.reject(runs, fn run ->
          run.id in [run_1.id, run_2.id]
        end)

      refute step_1_a.input_dataclip_id == step_2_a.input_dataclip_id
      assert retry_run.dataclip_id == step_2_a.input_dataclip_id
      assert retry_run.starting_trigger_id |> is_nil()
      assert retry_run.starting_job_id == job_a.id
      assert retry_run.created_by_id == user.id
      assert retry_run.work_order_id == workorder.id
      assert retry_run.state == :available

      assert retry_run |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying a run from the start should not copy over steps"
    end

    test "retrying one WorkOrder with a multiple runs whose latest run has no steps from start job skips the retry",
         %{
           jobs: [job_a, job_b, _job_c],
           snapshot: snapshot,
           trigger: trigger,
           user: user,
           workflow: workflow
         } do
      input_dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          dataclip: input_dataclip,
          snapshot: snapshot,
          trigger: trigger,
          workflow: workflow
        )

      run_1 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
          snapshot: snapshot,
          starting_trigger: trigger,
          steps: [
            insert(:step,
              job: job_a,
              input_dataclip: input_dataclip,
              output_dataclip: output_dataclip
            ),
            step_1_b =
              insert(:step,
                job: job_b,
                input_dataclip: output_dataclip
              )
          ]
        )

      run_2 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: step_1_b.input_dataclip,
          snapshot: snapshot,
          starting_job: step_1_b.job,
          steps: []
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      for run <- runs do
        assert run.id in [run_1.id, run_2.id]
      end

      {:ok, 0, 0} =
        WorkOrders.retry_many([workorder], job_a.id, created_by: user)

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      assert [] ==
               Enum.reject(runs, fn run ->
                 run.id in [run_1.id, run_2.id]
               end)
    end

    test "retrying one WorkOrder with a multiple runs from mid way job", %{
      snapshot: snapshot,
      workflow: workflow,
      trigger: trigger,
      jobs: [job_a, job_b, job_c],
      user: user
    } do
      input_dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          dataclip: input_dataclip,
          snapshot: snapshot,
          trigger: trigger,
          workflow: workflow
        )

      run_1 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
          starting_trigger: trigger,
          snapshot: snapshot,
          steps: [
            insert(:step,
              job: job_a,
              input_dataclip: input_dataclip,
              output_dataclip: output_dataclip
            ),
            step_1_b =
              insert(:step,
                job: job_b,
                input_dataclip: build(:dataclip),
                output_dataclip: build(:dataclip)
              )
          ]
        )

      run_2 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: build(:dataclip),
          starting_job: job_a,
          snapshot: snapshot,
          steps: [
            step_2_a =
              insert(:step,
                job: job_a,
                input_dataclip: build(:dataclip),
                output_dataclip: build(:dataclip)
              ),
            step_2_b =
              insert(:step,
                job: job_b,
                input_dataclip: build(:dataclip),
                output_dataclip: build(:dataclip)
              ),
            insert(:step,
              job: job_c,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            )
          ]
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()
      runs_ids = Enum.map(runs, & &1.id)
      assert Enum.sort(runs_ids) == Enum.sort([run_1.id, run_2.id])

      {:ok, 1, 0} =
        WorkOrders.retry_many([workorder], job_b.id,
          created_by: user,
          project_id: workflow.project_id
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      [retry_run] =
        Enum.reject(runs, fn run ->
          run.id in [run_1.id, run_2.id]
        end)

      refute step_1_b.input_dataclip_id == step_2_b.input_dataclip_id
      assert retry_run.dataclip_id == step_2_b.input_dataclip_id
      assert retry_run.starting_trigger_id |> is_nil()
      assert retry_run.starting_job_id == job_b.id
      assert retry_run.created_by_id == user.id
      assert retry_run.work_order_id == workorder.id
      assert retry_run.state == :available

      steps = Ecto.assoc(retry_run, :steps) |> Repo.all()
      assert steps |> Enum.map(& &1.id) == [step_2_a.id]
    end

    test "retrying multiple workorders preserves the order in which the workorders were created",
         %{
           jobs: [job_a, job_b, job_c],
           snapshot: snapshot,
           trigger: trigger,
           user: user,
           workflow: workflow
         } do
      [workorder_1, workorder_2] =
        insert_list(2, :workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          snapshot: snapshot,
          runs: [
            %{
              state: :failed,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              snapshot: snapshot,
              steps: [
                insert(:step,
                  job: job_a,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                ),
                insert(:step,
                  job: job_b,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                ),
                insert(:step,
                  job: job_c,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                )
              ]
            }
          ]
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             )

      # we've reversed the order here
      {:ok, 2, 0} =
        WorkOrders.retry_many([workorder_2, workorder_1], job_a.id,
          created_by: user,
          project_id: workflow.project_id
        )

      retry_run_1 =
        Repo.get_by(Lightning.Run,
          work_order_id: workorder_1.id,
          starting_job_id: job_a.id
        )

      retry_run_2 =
        Repo.get_by(Lightning.Run,
          work_order_id: workorder_2.id,
          starting_job_id: job_a.id
        )

      assert retry_run_1.inserted_at
             |> DateTime.before?(retry_run_2.inserted_at)
    end

    test(
      "retrying multiple workorders returns error on limit exceeded",
      %{
        jobs: [job_a, job_b, job_c],
        snapshot: snapshot,
        trigger: trigger,
        user: user,
        workflow: workflow
      }
    ) do
      Mox.stub(
        MockUsageLimiter,
        :limit_action,
        fn %Action{type: :new_run, amount: n}, _context ->
          {:error, :too_many_runs,
           %Message{
             text:
               "You have attempted to enqueue #{n} runs but you have only 1 remaining in your current billig period"
           }}
        end
      )

      [workorder_1, workorder_2] =
        insert_list(2, :workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          snapshot: snapshot,
          runs: [
            %{
              state: :failed,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              snapshot: snapshot,
              steps: [
                insert(:step,
                  job: job_a,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                ),
                insert(:step,
                  job: job_b,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                ),
                insert(:step,
                  job: job_c,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                )
              ]
            }
          ]
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             )

      # we've reversed the order here
      assert {:error, :too_many_runs,
              %{
                text:
                  "You have attempted to enqueue 2 runs but you have only 1 remaining in your current billig period"
              }} =
               WorkOrders.retry_many([workorder_2, workorder_1], job_a.id,
                 created_by: user,
                 project_id: workflow.project_id
               )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             )
    end

    test "retrying multiple workorders only retries workorders with the given job",
         %{
           jobs: [job_a, job_b, job_c],
           snapshot: snapshot,
           trigger: trigger,
           user: user,
           workflow: workflow
         } do
      workorder_1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          snapshot: snapshot,
          runs: [
            %{
              state: :failed,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              snapshot: snapshot,
              steps: [
                insert(:step,
                  job: job_a,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                )
              ]
            }
          ]
        )

      workorder_2 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          snapshot: snapshot,
          runs: [
            %{
              state: :failed,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              snapshot: snapshot,
              steps: [
                insert(:step,
                  job: job_a,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                ),
                insert(:step,
                  job: job_b,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                ),
                insert(:step,
                  job: job_c,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                )
              ]
            }
          ]
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_b.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_b.id
             )

      {:ok, 1, 0} =
        WorkOrders.retry_many([workorder_2, workorder_1], job_b.id,
          created_by: user,
          project_id: workflow.project_id
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_b.id
             )

      assert Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_b.id
             )
    end

    test "retrying multiple workorders returns an error on limit exceeded for steps",
         %{
           jobs: [job_a | _jobs],
           snapshot: snapshot,
           trigger: trigger,
           user: user,
           workflow: workflow
         } do
      Mox.stub(
        MockUsageLimiter,
        :limit_action,
        fn %Action{
             type: :new_run,
             amount: n
           },
           _context ->
          {:error, :too_many_runs,
           %Message{
             text:
               "You have attempted to enqueue #{n} runs but you have only 1 remaining in your current billig period"
           }}
        end
      )

      workorder_1 =
        insert(:workorder,
          snapshot: snapshot,
          dataclip: build(:dataclip),
          trigger: trigger,
          workflow: workflow
        )

      run_1 =
        insert(:run,
          dataclip: build(:dataclip),
          snapshot: snapshot,
          starting_trigger: trigger,
          state: :failed,
          work_order: workorder_1
        )

      run_step_1_a =
        insert(:run_step,
          step:
            build(:step,
              job: job_a,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
          run: run_1
        )

      workorder_2 =
        insert(:workorder,
          dataclip: build(:dataclip),
          snapshot: snapshot,
          trigger: trigger,
          workflow: workflow
        )

      run_2 =
        insert(:run,
          dataclip: build(:dataclip),
          snapshot: snapshot,
          starting_trigger: trigger,
          state: :failed,
          work_order: workorder_2
        )

      run_step_2_a =
        insert(:run_step,
          step:
            build(:step,
              job: job_a,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
          run: run_2
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             )

      # we've reversed the order here
      assert {:error, :too_many_runs,
              %{
                text:
                  "You have attempted to enqueue 2 runs but you have only 1 remaining in your current billig period"
              }} =
               WorkOrders.retry_many([run_step_2_a, run_step_1_a],
                 created_by: user,
                 project_id: workflow.project_id
               )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             )
    end
  end

  describe "retry_many/2 for WorkOrders" do
    setup do
      Mox.stub(MockUsageLimiter, :limit_action, fn _action, _ctx ->
        :ok
      end)

      [job_a, job_b, job_c] = jobs = build_list(3, :job)
      trigger = build(:trigger, type: :webhook)

      workflow =
        build(:workflow)
        |> with_job(job_a)
        |> with_job(job_b)
        |> with_job(job_c)
        |> with_trigger(trigger)
        |> with_edge({trigger, job_a})
        |> with_edge({job_a, job_b})
        |> with_edge({job_b, job_c})
        |> insert()

      %{
        workflow: workflow,
        snapshot: Lightning.Workflows.Snapshot.build(workflow) |> Repo.insert!(),
        trigger: Repo.reload!(trigger),
        jobs: Repo.reload!(jobs),
        user: insert(:user)
      }
    end

    test "retrying a single WorkOrder with multiple runs", %{
      workflow: workflow,
      snapshot: snapshot,
      trigger: trigger,
      jobs: [job_a, job_b, job_c],
      user: user
    } do
      input_dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: input_dataclip
        )

      run_1 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
          snapshot: snapshot,
          starting_trigger: trigger,
          steps: [
            step_1_a =
              insert(:step,
                job: job_a,
                input_dataclip: input_dataclip,
                output_dataclip: output_dataclip
              )
          ]
        )

      run_2 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: build(:dataclip),
          snapshot: snapshot,
          starting_job: job_a,
          steps: [
            step_2_a =
              insert(:step,
                job: job_a,
                input_dataclip: build(:dataclip),
                output_dataclip: build(:dataclip)
              ),
            insert(:step,
              job: job_b,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
            insert(:step,
              job: job_c,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            )
          ]
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      for run <- runs do
        assert run.id in [run_1.id, run_2.id]
      end

      {:ok, 1, 0} =
        WorkOrders.retry_many([workorder],
          created_by: user,
          project_id: workflow.project_id
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      [retry_run] =
        Enum.reject(runs, fn run ->
          run.id in [run_1.id, run_2.id]
        end)

      refute step_1_a.input_dataclip_id == step_2_a.input_dataclip_id

      assert retry_run.dataclip_id == step_1_a.input_dataclip_id,
             "when retrying a workorder from start, the first job of the first run used"

      assert retry_run.starting_trigger_id |> is_nil()
      assert retry_run.starting_job_id == job_a.id
      assert retry_run.created_by_id == user.id
      assert retry_run.work_order_id == workorder.id
      assert retry_run.snapshot_id == snapshot.id
      assert retry_run.state == :available

      assert retry_run |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying a run from the start should not copy over steps"
    end

    test "retrying multiple workorders preserves the order in which the workorders were created",
         %{
           jobs: [job_a, job_b, job_c],
           snapshot: snapshot,
           trigger: trigger,
           user: user,
           workflow: workflow
         } do
      [workorder_1, workorder_2] =
        insert_list(2, :workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          snapshot: snapshot,
          runs: [
            %{
              state: :failed,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              snapshot: snapshot,
              steps: [
                insert(:step,
                  job: job_a,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                ),
                insert(:step,
                  job: job_b,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                ),
                insert(:step,
                  job: job_c,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                )
              ]
            }
          ]
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             )

      # we've reversed the order here
      {:ok, 2, 0} =
        WorkOrders.retry_many([workorder_2, workorder_1],
          created_by: user,
          project_id: workflow.project_id
        )

      retry_run_1 =
        Repo.get_by(Lightning.Run,
          work_order_id: workorder_1.id,
          starting_job_id: job_a.id
        )

      retry_run_2 =
        Repo.get_by(Lightning.Run,
          work_order_id: workorder_2.id,
          starting_job_id: job_a.id
        )

      assert retry_run_1.inserted_at
             |> DateTime.before?(retry_run_2.inserted_at)
    end

    test "retrying a WorkOrder with a run having starting_trigger without steps",
         %{
           jobs: [job_a, _job_b, _job_c],
           snapshot: snapshot,
           trigger: trigger,
           user: user,
           workflow: workflow
         } do
      input_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          dataclip: input_dataclip,
          snapshot: snapshot,
          trigger: trigger,
          workflow: workflow
        )

      run_1 =
        insert(:run,
          dataclip: input_dataclip,
          snapshot: snapshot,
          starting_trigger: trigger,
          state: :failed,
          steps: [],
          work_order: workorder
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      for run <- runs do
        assert run.id in [run_1.id]
      end

      {:ok, 1, 0} =
        WorkOrders.retry_many([workorder],
          created_by: user,
          project_id: workflow.project_id
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      [retry_run] =
        Enum.reject(runs, fn run ->
          run.id in [run_1.id]
        end)

      assert retry_run.dataclip_id == run_1.dataclip_id

      assert retry_run.starting_trigger_id |> is_nil()

      assert retry_run.starting_job_id == job_a.id,
             "the job linked to the trigger is used when there's no strarting job"

      assert retry_run.created_by_id == user.id
      assert retry_run.work_order_id == workorder.id
      assert retry_run.snapshot_id == snapshot.id
      assert retry_run.state == :available

      assert retry_run |> Repo.preload(:steps) |> Map.get(:steps) == []
    end

    test "rejected workorders are retryable",
         %{
           snapshot: snapshot,
           trigger: trigger,
           user: user,
           workflow: workflow
         } do
      input_dataclip = insert(:dataclip)
      wiped_dataclip = insert(:dataclip, wiped_at: DateTime.utc_now())

      workorder =
        insert(:workorder,
          dataclip: input_dataclip,
          snapshot: snapshot,
          trigger: trigger,
          workflow: workflow,
          state: :rejected
        )

      discarded_workorder =
        insert(:workorder,
          dataclip: wiped_dataclip,
          snapshot: snapshot,
          trigger: trigger,
          workflow: workflow,
          state: :success
        )

      runs = workorder |> Ecto.assoc(:runs) |> Repo.all()

      assert Enum.empty?(runs)
      assert workorder.state == :rejected

      {:ok, 1, 1} =
        WorkOrders.retry_many([workorder, discarded_workorder],
          created_by: user,
          project_id: workflow.project_id
        )

      workorder = Repo.reload(workorder)
      runs = workorder |> Ecto.assoc(:runs) |> Repo.all()

      refute Enum.empty?(runs)
      refute workorder.state == :rejected
    end

    test "enqueues a workorder that was originally built for manual/job", %{
      workflow: workflow,
      jobs: [job | _jobs]
    } do
      user = insert(:user)

      assert {:ok, manual} =
               Lightning.WorkOrders.Manual.new(
                 %{
                   "body" =>
                     Jason.encode!(%{
                       "key_left" => "value_left",
                       "configuration" => %{"password" => "secret"}
                     })
                 },
                 workflow: workflow,
                 project: workflow.project,
                 job: job,
                 created_by: user
               )
               |> Ecto.Changeset.apply_action(:validate)

      assert {:ok, %{runs: old_runs} = workorder} = WorkOrders.create_for(manual)

      {:ok, 1, 0} =
        WorkOrders.retry_many([workorder],
          created_by: user,
          project_id: workflow.project_id
        )

      %{runs: runs} = Repo.reload(workorder) |> Repo.preload(:runs)

      assert runs -- old_runs != []
    end

    test "retrying a WorkOrder with a run having starting_job without steps",
         %{
           jobs: [_job_a, job_b, _job_c],
           snapshot: snapshot,
           trigger: trigger,
           user: user,
           workflow: workflow
         } do
      input_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          dataclip: input_dataclip,
          snapshot: snapshot,
          trigger: trigger,
          workflow: workflow
        )

      run_1 =
        insert(:run,
          dataclip: input_dataclip,
          snapshot: snapshot,
          starting_job: job_b,
          starting_trigger: nil,
          state: :failed,
          steps: [],
          work_order: workorder
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      for run <- runs do
        assert run.id in [run_1.id]
      end

      {:ok, 1, 0} =
        WorkOrders.retry_many([workorder],
          created_by: user,
          project_id: workflow.project_id
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      [retry_run] =
        Enum.reject(runs, fn run ->
          run.id in [run_1.id]
        end)

      assert retry_run.dataclip_id == run_1.dataclip_id

      assert retry_run.starting_trigger_id |> is_nil()
      assert retry_run.starting_job_id == run_1.starting_job_id
      assert retry_run.created_by_id == user.id
      assert retry_run.work_order_id == workorder.id
      assert retry_run.snapshot_id == snapshot.id
      assert retry_run.state == :available

      assert retry_run |> Repo.preload(:steps) |> Map.get(:steps) == []
    end

    test "retrying multiple workorders with wiped and non wiped dataclips",
         %{
           workflow: workflow,
           trigger: trigger,
           snapshot: snapshot,
           jobs: [job_a | _rest],
           user: user
         } do
      workorder_1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :failed,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              snapshot: snapshot,
              steps: [
                insert(:step,
                  job: job_a,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                )
              ]
            }
          ]
        )

      wiped_dataclip = insert(:dataclip, wiped_at: DateTime.utc_now())

      workorder_2 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: wiped_dataclip,
          runs: [
            %{
              state: :failed,
              dataclip: wiped_dataclip,
              starting_trigger: trigger,
              snapshot: snapshot,
              steps: [
                insert(:step,
                  job: job_a,
                  input_dataclip: wiped_dataclip,
                  output_dataclip: nil
                )
              ]
            }
          ]
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             )

      {:ok, 1, 1} =
        WorkOrders.retry_many([workorder_2, workorder_1],
          created_by: user,
          project_id: workflow.project_id
        )

      assert Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             ),
             "workorder with wiped dataclip is not retried"
    end

    test "retrying multiple chunks of workorders enqueues in background",
         %{
           jobs: [job_a, job_b, job_c],
           snapshot: snapshot,
           trigger: trigger,
           user: user,
           workflow: workflow
         } do
      workorders =
        insert_list(101, :workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          snapshot: snapshot,
          runs: [
            %{
              state: :failed,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              snapshot: snapshot,
              steps: [
                insert(:step,
                  job: job_a,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                ),
                insert(:step,
                  job: job_b,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                ),
                insert(:step,
                  job: job_c,
                  input_dataclip: build(:dataclip),
                  output_dataclip: build(:dataclip)
                )
              ]
            }
          ]
        )

      workorder_1 = hd(workorders)
      workorder_101 = hd(Enum.reverse(workorders))

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_101.id,
               starting_job_id: job_a.id
             )

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, 101, 0} =
          WorkOrders.retry_many(workorders,
            created_by: user,
            project_id: workflow.project_id
          )

        [workorders1, workorders2] = Enum.chunk_every(workorders, 100)

        workorders_ids1 = Enum.map(workorders1, & &1.id)

        workorders_ids2 = Enum.map(workorders2, & &1.id)

        user_id = user.id

        enqueued_jobs = all_enqueued(queue: :scheduler)

        assert length(enqueued_jobs) == 2,
               "Expected 2 jobs, got #{length(enqueued_jobs)}"

        all_expected_ids = workorders_ids1 ++ workorders_ids2

        all_actual_ids =
          Enum.flat_map(enqueued_jobs, fn job ->
            assert %{"created_by" => ^user_id, "workorders_ids" => ids} =
                     job.args

            ids
          end)

        assert Enum.sort(all_actual_ids) == Enum.sort(all_expected_ids),
               "The workorder IDs in the enqueued jobs do not match the expected IDs"

        job_with_workorder_1 =
          Enum.find(enqueued_jobs, fn job ->
            "#{workorder_1.id}" in job.args["workorders_ids"]
          end)

        job_with_workorder_101 =
          Enum.find(enqueued_jobs, fn job ->
            "#{workorder_101.id}" in job.args["workorders_ids"]
          end)

        assert job_with_workorder_1, "No job found containing workorder_1"
        assert job_with_workorder_101, "No job found containing workorder_101"

        assert :ok =
                 perform_job(RetryManyWorkOrdersJob, job_with_workorder_1.args)

        assert Repo.get_by(Lightning.Run,
                 work_order_id: workorder_1.id,
                 starting_job_id: job_a.id
               )

        refute Repo.get_by(Lightning.Run,
                 work_order_id: workorder_101.id,
                 starting_job_id: job_a.id
               )

        assert :ok =
                 perform_job(RetryManyWorkOrdersJob, job_with_workorder_101.args)

        assert Repo.get_by(Lightning.Run,
                 work_order_id: workorder_101.id,
                 starting_job_id: job_a.id
               )
      end)
    end
  end

  describe "retry_many/2 for RunSteps" do
    setup do
      Mox.stub(MockUsageLimiter, :limit_action, fn _action, _ctx ->
        :ok
      end)

      [job_a, job_b, job_c] = jobs = build_list(3, :job)
      trigger = build(:trigger, type: :webhook)

      workflow =
        build(:workflow)
        |> with_job(job_a)
        |> with_job(job_b)
        |> with_job(job_c)
        |> with_trigger(trigger)
        |> with_edge({trigger, job_a})
        |> with_edge({job_a, job_b})
        |> with_edge({job_b, job_c})
        |> insert()

      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      %{
        workflow: workflow,
        snapshot: snapshot,
        trigger: Repo.reload!(trigger),
        jobs: Repo.reload!(jobs),
        user: insert(:user)
      }
    end

    test "retrying a single RunStep of the first job", %{
      workflow: workflow,
      snapshot: snapshot,
      trigger: trigger,
      jobs: [job_a, job_b | _rest],
      user: user
    } do
      input_dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: input_dataclip
        )

      run =
        insert(:run,
          work_order: workorder,
          snapshot: snapshot,
          state: :failed,
          dataclip: input_dataclip,
          starting_trigger: trigger
        )

      step_a =
        insert(:step,
          job: job_a,
          input_dataclip: input_dataclip,
          output_dataclip: output_dataclip
        )

      run_step_a = insert(:run_step, step: step_a, run: run)

      # other run step
      insert(:run_step,
        step:
          build(:step,
            job: job_b,
            input_dataclip: build(:dataclip),
            output_dataclip: build(:dataclip)
          ),
        run: run
      )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder.id,
               starting_job_id: job_a.id
             )

      {:ok, 1, 0} =
        WorkOrders.retry_many([run_step_a],
          created_by: user,
          project_id: workflow.project_id
        )

      retry_run =
        Repo.get_by(Lightning.Run,
          work_order_id: workorder.id,
          starting_job_id: job_a.id
        )

      refute retry_run.id == run.id
      assert retry_run.dataclip_id == run_step_a.step.input_dataclip_id
      assert retry_run.starting_trigger_id |> is_nil()
      assert retry_run.starting_job_id == run_step_a.step.job.id
      assert retry_run.created_by_id == user.id
      assert retry_run.work_order_id == run.work_order_id
      assert retry_run.state == :available

      assert retry_run |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying a run from the start should not copy over steps"
    end

    test "retrying a single RunStep of a mid way job", %{
      workflow: workflow,
      snapshot: snapshot,
      trigger: trigger,
      jobs: [job_a, job_b, job_c],
      user: user
    } do
      input_dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: input_dataclip
        )

      run =
        insert(:run,
          work_order: workorder,
          snapshot: snapshot,
          state: :failed,
          dataclip: input_dataclip,
          starting_trigger: trigger
        )

      run_step_a =
        insert(:run_step,
          step:
            build(:step,
              job: job_a,
              input_dataclip: input_dataclip,
              output_dataclip: output_dataclip
            ),
          run: run
        )

      run_step_b =
        insert(:run_step,
          step:
            build(:step,
              job: job_b,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
          run: run
        )

      _run_step_c =
        insert(:run_step,
          step:
            build(:step,
              job: job_c,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
          run: run
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder.id,
               starting_job_id: run_step_b.step.job.id
             )

      {:ok, 1, 0} =
        WorkOrders.retry_many([run_step_b],
          created_by: user,
          project_id: workflow.project_id
        )

      retry_run =
        Repo.get_by(Lightning.Run,
          work_order_id: workorder.id,
          starting_job_id: run_step_b.step.job.id
        )

      refute retry_run.id == run.id
      assert retry_run.dataclip_id == run_step_b.step.input_dataclip_id
      assert retry_run.starting_trigger_id |> is_nil()
      assert retry_run.starting_job_id == run_step_b.step.job.id
      assert retry_run.created_by_id == user.id
      assert retry_run.work_order_id == run.work_order_id
      assert retry_run.state == :available

      steps = Ecto.assoc(retry_run, :steps) |> Repo.all()
      assert steps |> Enum.map(& &1.id) == [run_step_a.step.id]
    end

    test "retrying multiple RunSteps preservers the order of the given list to enqueue the runs",
         %{
           jobs: [job_a | _rest],
           snapshot: snapshot,
           trigger: trigger,
           user: user,
           workflow: workflow
         } do
      workorder_1 =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      run_1 =
        insert(:run,
          work_order: workorder_1,
          snapshot: snapshot,
          state: :failed,
          dataclip: build(:dataclip),
          starting_trigger: trigger
        )

      run_step_1_a =
        insert(:run_step,
          step:
            build(:step,
              job: job_a,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
          run: run_1
        )

      workorder_2 =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      run_2 =
        insert(:run,
          work_order: workorder_2,
          snapshot: snapshot,
          state: :failed,
          dataclip: build(:dataclip),
          starting_trigger: trigger
        )

      run_step_2_a =
        insert(:run_step,
          step:
            build(:step,
              job: job_a,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
          run: run_2
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             )

      # we've reversed the order here
      {:ok, 2, 0} =
        WorkOrders.retry_many([run_step_2_a, run_step_1_a],
          created_by: user,
          project_id: workflow.project_id
        )

      retry_run_1 =
        Repo.get_by(Lightning.Run,
          work_order_id: workorder_1.id,
          starting_job_id: job_a.id
        )

      retry_run_2 =
        Repo.get_by(Lightning.Run,
          work_order_id: workorder_2.id,
          starting_job_id: job_a.id
        )

      assert retry_run_2.inserted_at
             |> DateTime.before?(retry_run_1.inserted_at)
    end

    test "retrying multiple RunSteps with wiped and non wiped dataclips", %{
      workflow: workflow,
      snapshot: snapshot,
      trigger: trigger,
      jobs: [job_a | _rest],
      user: user
    } do
      workorder_1 =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      run_1 =
        insert(:run,
          work_order: workorder_1,
          state: :failed,
          dataclip: build(:dataclip),
          snapshot: snapshot,
          starting_trigger: trigger
        )

      run_step_1_a =
        insert(:run_step,
          step:
            build(:step,
              job: job_a,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
          run: run_1
        )

      wiped_dataclip = insert(:dataclip, wiped_at: DateTime.utc_now())

      workorder_2 =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: wiped_dataclip
        )

      run_2 =
        insert(:run,
          work_order: workorder_2,
          snapshot: snapshot,
          state: :failed,
          dataclip: wiped_dataclip,
          starting_trigger: trigger
        )

      run_step_2_a =
        insert(:run_step,
          step:
            build(:step,
              job: job_a,
              input_dataclip: wiped_dataclip,
              output_dataclip: nil
            ),
          run: run_2
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             )

      {:ok, 1, 0} =
        WorkOrders.retry_many([run_step_2_a, run_step_1_a],
          created_by: user,
          project_id: workflow.project_id
        )

      assert Repo.get_by(Lightning.Run,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             ),
             "run with wiped dataclip is not retried"
    end
  end

  describe "update_state/1" do
    test "sets the workorders state to running if there are any started runs" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, work_order} = WorkOrders.update_state(run)

      assert work_order.state == :pending

      {:ok, run} =
        Repo.update(run |> Ecto.Changeset.change(state: :started))

      {:ok, work_order} = WorkOrders.update_state(run)

      assert work_order.state == :running
    end
  end

  describe ".enqueue_many_for_retry/2" do
    test "assigns the creating user as the auditing actor" do
      dataclip = insert(:dataclip)
      workflow = insert(:simple_workflow)
      %{id: work_order_id} =
        insert(:workorder, workflow: workflow, dataclip: dataclip)
      %{id: user_id} = insert(:user)
      
      WorkOrders.enqueue_many_for_retry([work_order_id], user_id)

      assert %{actor_id: ^user_id} = Repo.one(Audit)
    end
  end

  describe ".build"  do
    test "uses the provided actor for the snapshot audit event" do
      dataclip = insert(:dataclip)
      workflow = insert(:simple_workflow)
      %{id: actor_id} = actor = insert(:user)

      WorkOrders.build(%{dataclip: dataclip, workflow: workflow, actor: actor})

      assert %{actor_id: ^actor_id} = Repo.one(Audit)
    end
  end

  describe ".build_for" do
    test "uses the provided actor for the snapshot audit event" do
      dataclip = insert(:dataclip)
      trigger = insert(:trigger)
      workflow = insert(:simple_workflow)
      %{id: actor_id} = actor = insert(:user)

      WorkOrders.build_for(
        trigger,
        %{dataclip: dataclip, workflow: workflow, actor: actor}
      )

      assert %{actor_id: ^actor_id} = Repo.one(Audit)
    end
  end
end
