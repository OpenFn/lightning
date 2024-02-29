defmodule Lightning.WorkOrdersTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.WorkOrders

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

      %{
        workflow: workflow,
        trigger: trigger |> Repo.reload!(),
        job: job |> Repo.reload!()
      }
    end

    @tag trigger_type: :webhook
    test "creating a webhook triggered workorder", %{
      workflow: workflow,
      trigger: trigger
    } do
      project_id = workflow.project_id
      Lightning.WorkOrders.subscribe(project_id)
      dataclip = insert(:dataclip)

      {:ok, workorder} =
        WorkOrders.create_for(trigger, dataclip: dataclip, workflow: workflow)

      assert workorder.workflow_id == workflow.id
      assert workorder.trigger_id == trigger.id
      assert workorder.dataclip_id == dataclip.id
      assert workorder.dataclip.type == :http_request

      [run] = workorder.runs

      assert run.starting_trigger.id == trigger.id
      assert run.dataclip_id == dataclip.id

      workorder_id = workorder.id

      assert_received %Lightning.WorkOrders.Events.RunCreated{
        project_id: ^project_id
      }

      assert_received %Lightning.WorkOrders.Events.WorkOrderCreated{
        work_order: %{id: ^workorder_id}
      }
    end

    @tag trigger_type: :cron
    test "creating a cron triggered workorder", %{
      workflow: workflow,
      trigger: trigger
    } do
      Lightning.WorkOrders.subscribe(workflow.project_id)

      dataclip = insert(:dataclip)

      {:ok, workorder} =
        WorkOrders.create_for(trigger, dataclip: dataclip, workflow: workflow)

      assert workorder.workflow_id == workflow.id
      assert workorder.trigger_id == trigger.id
      assert workorder.dataclip_id == dataclip.id
      assert workorder.dataclip.type == :http_request

      [run] = workorder.runs

      assert run.starting_trigger.id == trigger.id

      workorder_id = workorder.id

      assert_received %Lightning.WorkOrders.Events.WorkOrderCreated{
        work_order: %{id: ^workorder_id}
      }
    end

    test "creates a manual workorder", %{workflow: workflow, job: job} do
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

      assert {:ok, workorder} = WorkOrders.create_for(manual)
      assert [run] = workorder.runs

      assert workorder.dataclip.type == :saved_input

      assert workorder.dataclip.body == %{
               "key_left" => "value_left"
             }

      assert run.created_by.id == user.id

      assert_received %Lightning.WorkOrders.Events.RunCreated{
        project_id: ^project_id
      }

      workorder_id = workorder.id

      assert_received %Lightning.WorkOrders.Events.WorkOrderCreated{
        work_order: %{id: ^workorder_id}
      }
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

      %{
        workflow: workflow,
        trigger: trigger |> Repo.reload!(),
        jobs: jobs |> Repo.reload!()
      }
    end

    test "retrying a run from the start", %{
      workflow: workflow,
      trigger: trigger,
      jobs: [job | _rest]
    } do
      user = insert(:user)
      dataclip = insert(:dataclip)
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
                step = insert(:step, job: job, input_dataclip: dataclip)
              ]
            }
          ]
        )

      {:ok, retry_run} = WorkOrders.retry(run, step, created_by: user)

      refute retry_run.id == run.id
      assert retry_run.dataclip_id == dataclip.id
      assert retry_run.starting_job.id == job.id
      assert retry_run.created_by.id == user.id
      assert retry_run.work_order_id == run.work_order_id
      assert retry_run.state == :available

      assert retry_run |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying a run from the start should not copy over steps"
    end

    test "retrying a run from a step that isn't the first", %{
      workflow: workflow,
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
          trigger: trigger,
          dataclip: dataclip,
          runs: [
            %{
              state: :failed,
              dataclip: dataclip,
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

      steps = Ecto.assoc(retry_run, :steps) |> Repo.all()
      assert steps |> Enum.map(& &1.id) == [first_step.id]
    end

    test "retrying a run from a step with a wiped dataclip", %{
      workflow: workflow,
      trigger: trigger,
      jobs: [job | _rest]
    } do
      user = insert(:user)
      dataclip = insert(:dataclip, wiped_at: DateTime.utc_now())
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
      trigger: trigger,
      jobs: [job_a, job_b, job_c]
    } do
      user = insert(:user)
      dataclip = insert(:dataclip)

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
          state: :failed,
          runs: [
            %{
              state: :failed,
              dataclip: dataclip,
              starting_trigger: trigger,
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

      assert_received %Lightning.WorkOrders.Events.WorkOrderUpdated{
        work_order: %{id: ^workorder_id}
      }
    end
  end

  describe "retry_many/3" do
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

      %{
        workflow: workflow,
        trigger: Repo.reload!(trigger),
        jobs: Repo.reload!(jobs),
        user: insert(:user)
      }
    end

    test "retrying one WorkOrder with a single run without steps from start job skips the retry",
         %{
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
          runs: [
            %{
              state: :failed,
              dataclip: input_dataclip,
              starting_trigger: trigger,
              steps: []
            }
          ]
        )

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder.id,
               starting_job_id: job_a.id
             )

      {:ok, 0} = WorkOrders.retry_many([workorder], job_a.id, created_by: user)

      refute Repo.get_by(Lightning.Run,
               work_order_id: workorder.id,
               starting_job_id: job_a.id
             )
    end

    test "retrying one WorkOrder with a single run from start job", %{
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
          runs: [
            %{
              state: :failed,
              dataclip: input_dataclip,
              starting_trigger: trigger,
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

      {:ok, 1} = WorkOrders.retry_many([workorder], job_a.id, created_by: user)

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

      assert retry_run |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying a run from the start should not copy over steps"
    end

    test "retrying one WorkOrder with a single run from mid way job", %{
      workflow: workflow,
      trigger: trigger,
      jobs: [job_a, job_b, job_c],
      user: user
    } do
      input_dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      # create existing complete run
      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: input_dataclip,
          runs: [
            %{
              state: :failed,
              dataclip: input_dataclip,
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

      {:ok, 1} = WorkOrders.retry_many([workorder], job_b.id, created_by: user)

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
          dataclip: input_dataclip
        )

      run_1 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
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

      {:ok, 1} = WorkOrders.retry_many([workorder], job_a.id, created_by: user)

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
           workflow: workflow,
           trigger: trigger,
           jobs: [job_a, job_b, _job_c],
           user: user
         } do
      input_dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: input_dataclip
        )

      run_1 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
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
          starting_job: step_1_b.job,
          steps: []
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      for run <- runs do
        assert run.id in [run_1.id, run_2.id]
      end

      {:ok, 0} = WorkOrders.retry_many([workorder], job_a.id, created_by: user)

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      assert [] ==
               Enum.reject(runs, fn run ->
                 run.id in [run_1.id, run_2.id]
               end)
    end

    test "retrying one WorkOrder with a multiple runs from mid way job", %{
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
          dataclip: input_dataclip
        )

      run_1 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
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

      {:ok, 1} = WorkOrders.retry_many([workorder], job_b.id, created_by: user)

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
           workflow: workflow,
           trigger: trigger,
           jobs: [job_a, job_b, job_c],
           user: user
         } do
      [workorder_1, workorder_2] =
        insert_list(2, :workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :failed,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
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
      {:ok, 2} =
        WorkOrders.retry_many([workorder_2, workorder_1], job_a.id,
          created_by: user
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

    test "retrying multiple workorders only retries workorders with the given job",
         %{
           workflow: workflow,
           trigger: trigger,
           jobs: [job_a, job_b, job_c],
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
          runs: [
            %{
              state: :failed,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
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

      {:ok, 1} =
        WorkOrders.retry_many([workorder_2, workorder_1], job_b.id,
          created_by: user
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
  end

  describe "retry_many/2 for WorkOrders" do
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

      %{
        workflow: workflow,
        trigger: Repo.reload!(trigger),
        jobs: Repo.reload!(jobs),
        user: insert(:user)
      }
    end

    test "retrying a single WorkOrder with multiple runs", %{
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
          dataclip: input_dataclip
        )

      run_1 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
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

      {:ok, 1} = WorkOrders.retry_many([workorder], created_by: user)

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
      assert retry_run.state == :available

      assert retry_run |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying a run from the start should not copy over steps"
    end

    test "retrying multiple workorders preserves the order in which the workorders were created",
         %{
           workflow: workflow,
           trigger: trigger,
           jobs: [job_a, job_b, job_c],
           user: user
         } do
      [workorder_1, workorder_2] =
        insert_list(2, :workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :failed,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
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
      {:ok, 2} =
        WorkOrders.retry_many([workorder_2, workorder_1],
          created_by: user
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
          dataclip: input_dataclip
        )

      run_1 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
          starting_trigger: trigger,
          steps: []
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      for run <- runs do
        assert run.id in [run_1.id]
      end

      {:ok, 1} = WorkOrders.retry_many([workorder], created_by: user)

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
      assert retry_run.state == :available

      assert retry_run |> Repo.preload(:steps) |> Map.get(:steps) == []
    end

    test "retrying a WorkOrder with a run having starting_job without steps",
         %{
           workflow: workflow,
           trigger: trigger,
           jobs: [_job_a, job_b, _job_c],
           user: user
         } do
      input_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: input_dataclip
        )

      run_1 =
        insert(:run,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
          starting_trigger: nil,
          starting_job: job_b,
          steps: []
        )

      runs = Ecto.assoc(workorder, :runs) |> Repo.all()

      for run <- runs do
        assert run.id in [run_1.id]
      end

      {:ok, 1} = WorkOrders.retry_many([workorder], created_by: user)

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
      assert retry_run.state == :available

      assert retry_run |> Repo.preload(:steps) |> Map.get(:steps) == []
    end

    test "retrying multiple workorders with wiped and non wiped dataclips",
         %{
           workflow: workflow,
           trigger: trigger,
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

      {:ok, 1} =
        WorkOrders.retry_many([workorder_2, workorder_1],
          created_by: user
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
  end

  describe "retry_many/2 for RunSteps" do
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

      %{
        workflow: workflow,
        trigger: Repo.reload!(trigger),
        jobs: Repo.reload!(jobs),
        user: insert(:user)
      }
    end

    test "retrying a single RunStep of the first job", %{
      workflow: workflow,
      trigger: trigger,
      jobs: [job_a, job_b | _rest],
      user: user
    } do
      input_dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: input_dataclip
        )

      run =
        insert(:run,
          work_order: workorder,
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

      {:ok, 1} = WorkOrders.retry_many([run_step_a], created_by: user)

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
          dataclip: input_dataclip
        )

      run =
        insert(:run,
          work_order: workorder,
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

      {:ok, 1} = WorkOrders.retry_many([run_step_b], created_by: user)

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
           workflow: workflow,
           trigger: trigger,
           jobs: [job_a | _rest],
           user: user
         } do
      workorder_1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      run_1 =
        insert(:run,
          work_order: workorder_1,
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
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      run_2 =
        insert(:run,
          work_order: workorder_2,
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
      {:ok, 2} =
        WorkOrders.retry_many([run_step_2_a, run_step_1_a],
          created_by: user
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

    test "retrying multiple RunSteps with wiped and non wiped dataclips",
         %{
           workflow: workflow,
           trigger: trigger,
           jobs: [job_a | _rest],
           user: user
         } do
      workorder_1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      run_1 =
        insert(:run,
          work_order: workorder_1,
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

      wiped_dataclip = insert(:dataclip, wiped_at: DateTime.utc_now())

      workorder_2 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: wiped_dataclip
        )

      run_2 =
        insert(:run,
          work_order: workorder_2,
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

      {:ok, 1} =
        WorkOrders.retry_many([run_step_2_a, run_step_1_a],
          created_by: user
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
end
