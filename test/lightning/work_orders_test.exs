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

  describe "delete_history_for/1" do
    test "returns error for a project whose history retention is not set" do
      project = insert(:project, history_retention_period: nil)

      assert {:error, _} = WorkOrders.delete_history_for(project)
    end

    test "deletes history for workorders based on last_activity" do
      project = insert(:project, history_retention_period: 7)

      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project)

      now = DateTime.utc_now()

      workorder_to_delete =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -7),
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            build(:run,
              starting_trigger: trigger,
              dataclip: build(:dataclip),
              log_lines: [build(:log_line)],
              steps: [build(:step, job: job)]
            )
          ]
        )

      workorder_to_remain =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -6),
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            build(:run,
              starting_trigger: trigger,
              dataclip: build(:dataclip),
              log_lines: [build(:log_line)],
              steps: [build(:step, job: job)]
            )
          ]
        )

      assert {:ok, _} = WorkOrders.delete_history_for(project)

      # deleted history
      refute Lightning.Repo.get(Lightning.WorkOrder, workorder_to_delete.id)
      run_to_delete = hd(workorder_to_delete.runs)
      refute Lightning.Repo.get(Lightning.Run, run_to_delete.id)
      step_to_delete = hd(run_to_delete.steps)
      refute Lightning.Repo.get(Lightning.Invocation.Step, step_to_delete.id)
      log_line_to_delete = hd(run_to_delete.log_lines)

      refute Lightning.Repo.get_by(
               Lightning.Invocation.LogLine,
               id: log_line_to_delete.id
             )

      # remaining history
      assert Lightning.Repo.get(Lightning.WorkOrder, workorder_to_remain.id)
      run_to_remain = hd(workorder_to_remain.runs)
      assert Lightning.Repo.get(Lightning.Run, run_to_remain.id)
      step_to_remain = hd(run_to_remain.steps)
      assert Lightning.Repo.get(Lightning.Invocation.Step, step_to_remain.id)
      log_line_to_remain = hd(run_to_remain.log_lines)

      assert Lightning.Repo.get_by(
               Lightning.Invocation.LogLine,
               id: log_line_to_remain.id
             )

      # extra checks. Jobs, Triggers, Workflows are not deleted
      assert Repo.get(Lightning.Workflows.Job, job.id)
      assert Repo.get(Lightning.Workflows.Trigger, trigger.id)
      assert Repo.get(Lightning.Workflows.Workflow, workflow.id)
    end

    test "deletes project dataclips not associated to any work order correctly" do
      project = insert(:project, history_retention_period: 7)
      workflow = insert(:simple_workflow, project: project)
      now = DateTime.utc_now()

      # pre_retention means it exists earlier than the retention cut off time
      # post_retention means it exists later than the retention cut off time

      pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # opharn to mean not associated to any workorder
      opharn_pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      opharn_post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # to delete
      workorder_to_delete_1 =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -8),
          dataclip: post_retention_dataclip
        )

      # note that we've used pre_retention_dataclip for these 2 workorders.
      # to delete
      workorder_to_delete_2 =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -8),
          dataclip: pre_retention_dataclip
        )

      # will remain
      workorder_to_remain =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -6),
          dataclip: pre_retention_dataclip
        )

      assert {:ok, _} = WorkOrders.delete_history_for(project)

      # the workorders are deleted correctly
      refute Lightning.Repo.get(Lightning.WorkOrder, workorder_to_delete_1.id)
      refute Lightning.Repo.get(Lightning.WorkOrder, workorder_to_delete_2.id)
      assert Lightning.Repo.get(Lightning.WorkOrder, workorder_to_remain.id)

      # pre_retention_dataclip still exists
      # this is because it is still linked to workorder_to_remain
      assert workorder_to_delete_2.dataclip_id == pre_retention_dataclip.id
      assert workorder_to_remain.dataclip_id == pre_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, pre_retention_dataclip.id)

      # post_retention_dataclip still exists
      # this is because it exists later than the cut off time
      assert workorder_to_delete_1.dataclip_id == post_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, post_retention_dataclip.id)

      # opharn_post_retention_dataclip still exists
      # this is because it exists later than the cut off time
      assert Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_post_retention_dataclip.id
             )

      # opharn_pre_retention_dataclip is deleted
      # this is because it exists earlier than the cut off time
      refute Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_pre_retention_dataclip.id
             )
    end

    test "deletes project dataclips not associated to any run correctly" do
      project = insert(:project, history_retention_period: 7)

      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow, project: project)

      now = DateTime.utc_now()

      # pre_retention means it exists earlier than the retention cut off time
      # post_retention means it exists later than the retention cut off time

      pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # opharn to mean not associated to any workorder
      opharn_pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      opharn_post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # to delete
      workorder_to_delete_1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          last_activity: Timex.shift(now, days: -8)
        )

      run_to_delete_1 =
        insert(:run,
          work_order: workorder_to_delete_1,
          starting_trigger: trigger,
          dataclip: post_retention_dataclip
        )

      # note that we've used pre_retention_dataclip for these 2 runs.
      # to delete
      run_to_delete_2 =
        insert(:run,
          work_order: workorder_to_delete_1,
          starting_trigger: trigger,
          dataclip: pre_retention_dataclip
        )

      # will remain
      workorder_to_remain =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -6)
        )

      run_to_remain =
        insert(:run,
          work_order: workorder_to_remain,
          starting_trigger: trigger,
          dataclip: pre_retention_dataclip
        )

      assert {:ok, _} = WorkOrders.delete_history_for(project)

      # the runs are deleted correctly
      refute Lightning.Repo.get(Lightning.Run, run_to_delete_1.id)
      refute Lightning.Repo.get(Lightning.Run, run_to_delete_2.id)
      assert Lightning.Repo.get(Lightning.Run, run_to_remain.id)

      # pre_retention_dataclip still exists
      # this is because it is still linked to run_to_remain
      assert run_to_delete_2.dataclip_id == pre_retention_dataclip.id
      assert run_to_remain.dataclip_id == pre_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, pre_retention_dataclip.id)

      # post_retention_dataclip still exists
      # this is because it exists later than the cut off time
      assert run_to_delete_1.dataclip_id == post_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, post_retention_dataclip.id)

      # opharn_post_retention_dataclip still exists
      # this is because it exists later than the cut off time
      assert Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_post_retention_dataclip.id
             )

      # opharn_pre_retention_dataclip is deleted
      # this is because it exists earlier than the cut off time
      refute Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_pre_retention_dataclip.id
             )
    end

    test "deletes project dataclips not associated to any step input_dataclip correctly" do
      project = insert(:project, history_retention_period: 7)

      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project)

      now = DateTime.utc_now()

      # pre_retention means it exists earlier than the retention cut off time
      # post_retention means it exists later than the retention cut off time

      pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # opharn to mean not associated to any workorder
      opharn_pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      opharn_post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # to delete
      workorder_to_delete_1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          last_activity: Timex.shift(now, days: -8)
        )

      run_to_delete_1 =
        insert(:run,
          work_order: workorder_to_delete_1,
          starting_trigger: trigger,
          dataclip: build(:dataclip)
        )

      step_to_delete_1 =
        insert(:step,
          runs: [run_to_delete_1],
          job: job,
          input_dataclip: post_retention_dataclip
        )

      # note that we've used pre_retention_dataclip for these 2 steps.
      # to delete
      run_to_delete_2 =
        insert(:run,
          work_order: workorder_to_delete_1,
          starting_trigger: trigger,
          dataclip: build(:dataclip)
        )

      step_to_delete_2 =
        insert(:step,
          runs: [run_to_delete_2],
          job: job,
          input_dataclip: pre_retention_dataclip
        )

      # will remain
      workorder_to_remain =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -6)
        )

      run_to_remain =
        insert(:run,
          work_order: workorder_to_remain,
          starting_trigger: trigger,
          dataclip: build(:dataclip)
        )

      step_to_remain =
        insert(:step,
          runs: [run_to_remain],
          job: job,
          input_dataclip: pre_retention_dataclip
        )

      assert {:ok, _} = WorkOrders.delete_history_for(project)

      # the steps are deleted correctly
      refute Lightning.Repo.get(Lightning.Invocation.Step, step_to_delete_1.id)
      refute Lightning.Repo.get(Lightning.Invocation.Step, step_to_delete_2.id)
      assert Lightning.Repo.get(Lightning.Invocation.Step, step_to_remain.id)

      # pre_retention_dataclip still exists
      # this is because it is still linked to step_to_remain
      assert step_to_delete_2.input_dataclip_id == pre_retention_dataclip.id
      assert step_to_remain.input_dataclip_id == pre_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, pre_retention_dataclip.id)

      # post_retention_dataclip still exists
      # this is because it exists later than the cut off time
      assert step_to_delete_1.input_dataclip_id == post_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, post_retention_dataclip.id)

      # opharn_post_retention_dataclip still exists
      # this is because it exists later than the cut off time
      assert Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_post_retention_dataclip.id
             )

      # opharn_pre_retention_dataclip is deleted
      # this is because it exists earlier than the cut off time
      refute Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_pre_retention_dataclip.id
             )
    end

    test "deletes project dataclips not associated to any step output_dataclip correctly" do
      project = insert(:project, history_retention_period: 7)

      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project)

      now = DateTime.utc_now()

      # pre_retention means it exists earlier than the retention cut off time
      # post_retention means it exists later than the retention cut off time

      pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # opharn to mean not associated to any workorder
      opharn_pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      opharn_post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # to delete
      workorder_to_delete_1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          last_activity: Timex.shift(now, days: -8)
        )

      run_to_delete_1 =
        insert(:run,
          work_order: workorder_to_delete_1,
          starting_trigger: trigger,
          dataclip: build(:dataclip)
        )

      step_to_delete_1 =
        insert(:step,
          runs: [run_to_delete_1],
          job: job,
          output_dataclip: post_retention_dataclip
        )

      # note that we've used pre_retention_dataclip for these 2 steps.
      # to delete
      run_to_delete_2 =
        insert(:run,
          work_order: workorder_to_delete_1,
          starting_trigger: trigger,
          dataclip: build(:dataclip)
        )

      step_to_delete_2 =
        insert(:step,
          runs: [run_to_delete_2],
          job: job,
          output_dataclip: pre_retention_dataclip
        )

      # will remain
      workorder_to_remain =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -6)
        )

      run_to_remain =
        insert(:run,
          work_order: workorder_to_remain,
          starting_trigger: trigger,
          dataclip: build(:dataclip)
        )

      step_to_remain =
        insert(:step,
          runs: [run_to_remain],
          job: job,
          output_dataclip: pre_retention_dataclip
        )

      assert {:ok, _} = WorkOrders.delete_history_for(project)

      # the steps are deleted correctly
      refute Lightning.Repo.get(Lightning.Invocation.Step, step_to_delete_1.id)
      refute Lightning.Repo.get(Lightning.Invocation.Step, step_to_delete_2.id)
      assert Lightning.Repo.get(Lightning.Invocation.Step, step_to_remain.id)

      # pre_retention_dataclip still exists
      # this is because it is still linked to step_to_remain
      assert step_to_delete_2.output_dataclip_id == pre_retention_dataclip.id
      assert step_to_remain.output_dataclip_id == pre_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, pre_retention_dataclip.id)

      # post_retention_dataclip still exists
      # this is because it exists later than the cut off time
      assert step_to_delete_1.output_dataclip_id == post_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, post_retention_dataclip.id)

      # opharn_post_retention_dataclip still exists
      # this is because it exists later than the cut off time
      assert Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_post_retention_dataclip.id
             )

      # opharn_pre_retention_dataclip is deleted
      # this is because it exists earlier than the cut off time
      refute Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_pre_retention_dataclip.id
             )
    end
  end
end
