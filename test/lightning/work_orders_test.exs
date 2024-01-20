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
      Lightning.WorkOrders.subscribe(workflow.project_id)
      dataclip = insert(:dataclip)

      {:ok, workorder} =
        WorkOrders.create_for(trigger, dataclip: dataclip, workflow: workflow)

      assert workorder.workflow_id == workflow.id
      assert workorder.trigger_id == trigger.id
      assert workorder.dataclip_id == dataclip.id
      assert workorder.dataclip.type == :http_request

      [attempt] = workorder.attempts

      assert attempt.starting_trigger.id == trigger.id

      workorder_id = workorder.id

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

      [attempt] = workorder.attempts

      assert attempt.starting_trigger.id == trigger.id

      workorder_id = workorder.id

      assert_received %Lightning.WorkOrders.Events.WorkOrderCreated{
        work_order: %{id: ^workorder_id}
      }
    end

    test "creates a manual workorder", %{workflow: workflow, job: job} do
      user = insert(:user)

      Lightning.WorkOrders.subscribe(workflow.project_id)

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
      assert [attempt] = workorder.attempts

      assert workorder.dataclip.type == :saved_input

      assert workorder.dataclip.body == %{
               "key_left" => "value_left"
             }

      assert attempt.created_by.id == user.id

      assert_received %Lightning.WorkOrders.Events.AttemptCreated{}

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

    test "retrying an attempt from the start", %{
      workflow: workflow,
      trigger: trigger,
      jobs: [job | _rest]
    } do
      user = insert(:user)
      dataclip = insert(:dataclip)
      # create existing complete attempt
      %{attempts: [attempt]} =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          attempts: [
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

      {:ok, retry_attempt} = WorkOrders.retry(attempt, step, created_by: user)

      refute retry_attempt.id == attempt.id
      assert retry_attempt.dataclip_id == dataclip.id
      assert retry_attempt.starting_job.id == job.id
      assert retry_attempt.created_by.id == user.id
      assert retry_attempt.work_order_id == attempt.work_order_id
      assert retry_attempt.state == :available

      assert retry_attempt |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying an attempt from the start should not copy over steps"
    end

    test "retrying an attempt from a step that isn't the first", %{
      workflow: workflow,
      trigger: trigger,
      jobs: [job_a, job_b, job_c]
    } do
      user = insert(:user)
      dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      # create existing complete attempt
      %{attempts: [attempt]} =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          attempts: [
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

      {:ok, retry_attempt} =
        WorkOrders.retry(attempt, second_step, created_by: user)

      refute retry_attempt.id == attempt.id
      assert retry_attempt.dataclip_id == output_dataclip.id
      assert retry_attempt.starting_job.id == job_b.id
      assert retry_attempt.created_by.id == user.id
      assert retry_attempt.work_order_id == attempt.work_order_id
      assert retry_attempt.state == :available

      steps = Ecto.assoc(retry_attempt, :steps) |> Repo.all()
      assert steps |> Enum.map(& &1.id) == [first_step.id]
    end

    test "updates workorder state", %{
      workflow: workflow,
      trigger: trigger,
      jobs: [job | _rest]
    } do
      user = insert(:user)
      dataclip = insert(:dataclip)
      # create existing complete attempt
      %{attempts: [attempt]} =
        workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: :failed,
          attempts: [
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

      {:ok, _attempt} = WorkOrders.retry(attempt, step, created_by: user)

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

    test "retrying one WorkOrder with a single attempt without steps from start job skips the retry",
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
          attempts: [
            %{
              state: :failed,
              dataclip: input_dataclip,
              starting_trigger: trigger,
              steps: []
            }
          ]
        )

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder.id,
               starting_job_id: job_a.id
             )

      {:ok, 0} = WorkOrders.retry_many([workorder], job_a.id, created_by: user)

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder.id,
               starting_job_id: job_a.id
             )
    end

    test "retrying one WorkOrder with a single attempt from start job", %{
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
          attempts: [
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

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder.id,
               starting_job_id: job_a.id
             )

      {:ok, 1} = WorkOrders.retry_many([workorder], job_a.id, created_by: user)

      retry_attempt =
        Repo.get_by(Lightning.Attempt,
          work_order_id: workorder.id,
          starting_job_id: job_a.id
        )

      [old_attempt] = workorder.attempts

      refute retry_attempt.id == old_attempt.id
      assert retry_attempt.dataclip_id == step_a.input_dataclip_id
      assert retry_attempt.starting_trigger_id |> is_nil()
      assert retry_attempt.starting_job_id == job_a.id
      assert retry_attempt.created_by_id == user.id
      assert retry_attempt.work_order_id == old_attempt.work_order_id
      assert retry_attempt.state == :available

      assert retry_attempt |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying an attempt from the start should not copy over steps"
    end

    test "retrying one WorkOrder with a single attempt from mid way job", %{
      workflow: workflow,
      trigger: trigger,
      jobs: [job_a, job_b, job_c],
      user: user
    } do
      input_dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

      # create existing complete attempt
      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: input_dataclip,
          attempts: [
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

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder.id,
               starting_job_id: job_b.id
             )

      {:ok, 1} = WorkOrders.retry_many([workorder], job_b.id, created_by: user)

      retry_attempt =
        Repo.get_by(Lightning.Attempt,
          work_order_id: workorder.id,
          starting_job_id: job_b.id
        )

      [old_attempt] = workorder.attempts

      refute retry_attempt.id == old_attempt.id
      assert retry_attempt.dataclip_id == step_b.input_dataclip_id
      assert retry_attempt.starting_trigger_id |> is_nil()
      assert retry_attempt.starting_job_id == job_b.id
      assert retry_attempt.created_by_id == user.id
      assert retry_attempt.work_order_id == old_attempt.work_order_id
      assert retry_attempt.state == :available

      steps = Ecto.assoc(retry_attempt, :steps) |> Repo.all()
      assert steps |> Enum.map(& &1.id) == [step_a.id]
    end

    test "retrying one WorkOrder with a multiple attempts from start job", %{
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

      attempt_1 =
        insert(:attempt,
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

      attempt_2 =
        insert(:attempt,
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

      attempts = Ecto.assoc(workorder, :attempts) |> Repo.all()

      for attempt <- attempts do
        assert attempt.id in [attempt_1.id, attempt_2.id]
      end

      {:ok, 1} = WorkOrders.retry_many([workorder], job_a.id, created_by: user)

      attempts = Ecto.assoc(workorder, :attempts) |> Repo.all()

      [retry_attempt] =
        Enum.reject(attempts, fn attempt ->
          attempt.id in [attempt_1.id, attempt_2.id]
        end)

      refute step_1_a.input_dataclip_id == step_2_a.input_dataclip_id
      assert retry_attempt.dataclip_id == step_2_a.input_dataclip_id
      assert retry_attempt.starting_trigger_id |> is_nil()
      assert retry_attempt.starting_job_id == job_a.id
      assert retry_attempt.created_by_id == user.id
      assert retry_attempt.work_order_id == workorder.id
      assert retry_attempt.state == :available

      assert retry_attempt |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying an attempt from the start should not copy over steps"
    end

    test "retrying one WorkOrder with a multiple attempts whose latest attempt has no steps from start job skips the retry",
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

      attempt_1 =
        insert(:attempt,
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

      attempt_2 =
        insert(:attempt,
          work_order: workorder,
          state: :failed,
          dataclip: step_1_b.input_dataclip,
          starting_job: step_1_b.job,
          steps: []
        )

      attempts = Ecto.assoc(workorder, :attempts) |> Repo.all()

      for attempt <- attempts do
        assert attempt.id in [attempt_1.id, attempt_2.id]
      end

      {:ok, 0} = WorkOrders.retry_many([workorder], job_a.id, created_by: user)

      attempts = Ecto.assoc(workorder, :attempts) |> Repo.all()

      assert [] ==
               Enum.reject(attempts, fn attempt ->
                 attempt.id in [attempt_1.id, attempt_2.id]
               end)
    end

    test "retrying one WorkOrder with a multiple attempts from mid way job", %{
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

      attempt_1 =
        insert(:attempt,
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

      attempt_2 =
        insert(:attempt,
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

      attempts = Ecto.assoc(workorder, :attempts) |> Repo.all()
      attempts_ids = Enum.map(attempts, & &1.id)
      assert Enum.sort(attempts_ids) == Enum.sort([attempt_1.id, attempt_2.id])

      {:ok, 1} = WorkOrders.retry_many([workorder], job_b.id, created_by: user)

      attempts = Ecto.assoc(workorder, :attempts) |> Repo.all()

      [retry_attempt] =
        Enum.reject(attempts, fn attempt ->
          attempt.id in [attempt_1.id, attempt_2.id]
        end)

      refute step_1_b.input_dataclip_id == step_2_b.input_dataclip_id
      assert retry_attempt.dataclip_id == step_2_b.input_dataclip_id
      assert retry_attempt.starting_trigger_id |> is_nil()
      assert retry_attempt.starting_job_id == job_b.id
      assert retry_attempt.created_by_id == user.id
      assert retry_attempt.work_order_id == workorder.id
      assert retry_attempt.state == :available

      steps = Ecto.assoc(retry_attempt, :steps) |> Repo.all()
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
          attempts: [
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

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             )

      # we've reversed the order here
      {:ok, 2} =
        WorkOrders.retry_many([workorder_2, workorder_1], job_a.id,
          created_by: user
        )

      retry_attempt_1 =
        Repo.get_by(Lightning.Attempt,
          work_order_id: workorder_1.id,
          starting_job_id: job_a.id
        )

      retry_attempt_2 =
        Repo.get_by(Lightning.Attempt,
          work_order_id: workorder_2.id,
          starting_job_id: job_a.id
        )

      assert retry_attempt_1.inserted_at
             |> DateTime.before?(retry_attempt_2.inserted_at)
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
          attempts: [
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
          attempts: [
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

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder_1.id,
               starting_job_id: job_b.id
             )

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder_2.id,
               starting_job_id: job_b.id
             )

      {:ok, 1} =
        WorkOrders.retry_many([workorder_2, workorder_1], job_b.id,
          created_by: user
        )

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder_1.id,
               starting_job_id: job_b.id
             )

      assert Repo.get_by(Lightning.Attempt,
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

    test "retrying a single WorkOrder with multiple attempts", %{
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

      attempt_1 =
        insert(:attempt,
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

      attempt_2 =
        insert(:attempt,
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

      attempts = Ecto.assoc(workorder, :attempts) |> Repo.all()

      for attempt <- attempts do
        assert attempt.id in [attempt_1.id, attempt_2.id]
      end

      {:ok, 1} = WorkOrders.retry_many([workorder], created_by: user)

      attempts = Ecto.assoc(workorder, :attempts) |> Repo.all()

      [retry_attempt] =
        Enum.reject(attempts, fn attempt ->
          attempt.id in [attempt_1.id, attempt_2.id]
        end)

      refute step_1_a.input_dataclip_id == step_2_a.input_dataclip_id

      assert retry_attempt.dataclip_id == step_1_a.input_dataclip_id,
             "when retrying a workorder from start, the first job of the first attempt used"

      assert retry_attempt.starting_trigger_id |> is_nil()
      assert retry_attempt.starting_job_id == job_a.id
      assert retry_attempt.created_by_id == user.id
      assert retry_attempt.work_order_id == workorder.id
      assert retry_attempt.state == :available

      assert retry_attempt |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying an attempt from the start should not copy over steps"
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
          attempts: [
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

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             )

      # we've reversed the order here
      {:ok, 2} =
        WorkOrders.retry_many([workorder_2, workorder_1],
          created_by: user
        )

      retry_attempt_1 =
        Repo.get_by(Lightning.Attempt,
          work_order_id: workorder_1.id,
          starting_job_id: job_a.id
        )

      retry_attempt_2 =
        Repo.get_by(Lightning.Attempt,
          work_order_id: workorder_2.id,
          starting_job_id: job_a.id
        )

      assert retry_attempt_1.inserted_at
             |> DateTime.before?(retry_attempt_2.inserted_at)
    end

    test "retrying a WorkOrder with an attempt having starting_trigger without steps",
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

      attempt_1 =
        insert(:attempt,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
          starting_trigger: trigger,
          steps: []
        )

      attempts = Ecto.assoc(workorder, :attempts) |> Repo.all()

      for attempt <- attempts do
        assert attempt.id in [attempt_1.id]
      end

      {:ok, 1} = WorkOrders.retry_many([workorder], created_by: user)

      attempts = Ecto.assoc(workorder, :attempts) |> Repo.all()

      [retry_attempt] =
        Enum.reject(attempts, fn attempt ->
          attempt.id in [attempt_1.id]
        end)

      assert retry_attempt.dataclip_id == attempt_1.dataclip_id

      assert retry_attempt.starting_trigger_id |> is_nil()

      assert retry_attempt.starting_job_id == job_a.id,
             "the job linked to the trigger is used when there's no strarting job"

      assert retry_attempt.created_by_id == user.id
      assert retry_attempt.work_order_id == workorder.id
      assert retry_attempt.state == :available

      assert retry_attempt |> Repo.preload(:steps) |> Map.get(:steps) == []
    end

    test "retrying a WorkOrder with an attempt having starting_job without steps",
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

      attempt_1 =
        insert(:attempt,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
          starting_trigger: nil,
          starting_job: job_b,
          steps: []
        )

      attempts = Ecto.assoc(workorder, :attempts) |> Repo.all()

      for attempt <- attempts do
        assert attempt.id in [attempt_1.id]
      end

      {:ok, 1} = WorkOrders.retry_many([workorder], created_by: user)

      attempts = Ecto.assoc(workorder, :attempts) |> Repo.all()

      [retry_attempt] =
        Enum.reject(attempts, fn attempt ->
          attempt.id in [attempt_1.id]
        end)

      assert retry_attempt.dataclip_id == attempt_1.dataclip_id

      assert retry_attempt.starting_trigger_id |> is_nil()
      assert retry_attempt.starting_job_id == attempt_1.starting_job_id
      assert retry_attempt.created_by_id == user.id
      assert retry_attempt.work_order_id == workorder.id
      assert retry_attempt.state == :available

      assert retry_attempt |> Repo.preload(:steps) |> Map.get(:steps) == []
    end
  end

  describe "retry_many/2 for AttemptSteps" do
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

    test "retrying a single AttemptStep of the first job", %{
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

      attempt =
        insert(:attempt,
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

      attempt_step_a = insert(:attempt_step, step: step_a, attempt: attempt)

      # other attempt step
      insert(:attempt_step,
        step:
          build(:step,
            job: job_b,
            input_dataclip: build(:dataclip),
            output_dataclip: build(:dataclip)
          ),
        attempt: attempt
      )

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder.id,
               starting_job_id: job_a.id
             )

      {:ok, 1} = WorkOrders.retry_many([attempt_step_a], created_by: user)

      retry_attempt =
        Repo.get_by(Lightning.Attempt,
          work_order_id: workorder.id,
          starting_job_id: job_a.id
        )

      refute retry_attempt.id == attempt.id
      assert retry_attempt.dataclip_id == attempt_step_a.step.input_dataclip_id
      assert retry_attempt.starting_trigger_id |> is_nil()
      assert retry_attempt.starting_job_id == attempt_step_a.step.job.id
      assert retry_attempt.created_by_id == user.id
      assert retry_attempt.work_order_id == attempt.work_order_id
      assert retry_attempt.state == :available

      assert retry_attempt |> Repo.preload(:steps) |> Map.get(:steps) == [],
             "retrying an attempt from the start should not copy over steps"
    end

    test "retrying a single AttemptStep of a mid way job", %{
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

      attempt =
        insert(:attempt,
          work_order: workorder,
          state: :failed,
          dataclip: input_dataclip,
          starting_trigger: trigger
        )

      attempt_step_a =
        insert(:attempt_step,
          step:
            build(:step,
              job: job_a,
              input_dataclip: input_dataclip,
              output_dataclip: output_dataclip
            ),
          attempt: attempt
        )

      attempt_step_b =
        insert(:attempt_step,
          step:
            build(:step,
              job: job_b,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
          attempt: attempt
        )

      _attempt_step_c =
        insert(:attempt_step,
          step:
            build(:step,
              job: job_c,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
          attempt: attempt
        )

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder.id,
               starting_job_id: attempt_step_b.step.job.id
             )

      {:ok, 1} = WorkOrders.retry_many([attempt_step_b], created_by: user)

      retry_attempt =
        Repo.get_by(Lightning.Attempt,
          work_order_id: workorder.id,
          starting_job_id: attempt_step_b.step.job.id
        )

      refute retry_attempt.id == attempt.id
      assert retry_attempt.dataclip_id == attempt_step_b.step.input_dataclip_id
      assert retry_attempt.starting_trigger_id |> is_nil()
      assert retry_attempt.starting_job_id == attempt_step_b.step.job.id
      assert retry_attempt.created_by_id == user.id
      assert retry_attempt.work_order_id == attempt.work_order_id
      assert retry_attempt.state == :available

      steps = Ecto.assoc(retry_attempt, :steps) |> Repo.all()
      assert steps |> Enum.map(& &1.id) == [attempt_step_a.step.id]
    end

    test "retrying multiple AttemptSteps preservers the order of the given list to enqueue the attempts",
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

      attempt_1 =
        insert(:attempt,
          work_order: workorder_1,
          state: :failed,
          dataclip: build(:dataclip),
          starting_trigger: trigger
        )

      attempt_step_1_a =
        insert(:attempt_step,
          step:
            build(:step,
              job: job_a,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
          attempt: attempt_1
        )

      workorder_2 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      attempt_2 =
        insert(:attempt,
          work_order: workorder_2,
          state: :failed,
          dataclip: build(:dataclip),
          starting_trigger: trigger
        )

      attempt_step_2_a =
        insert(:attempt_step,
          step:
            build(:step,
              job: job_a,
              input_dataclip: build(:dataclip),
              output_dataclip: build(:dataclip)
            ),
          attempt: attempt_2
        )

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder_1.id,
               starting_job_id: job_a.id
             )

      refute Repo.get_by(Lightning.Attempt,
               work_order_id: workorder_2.id,
               starting_job_id: job_a.id
             )

      # we've reversed the order here
      {:ok, 2} =
        WorkOrders.retry_many([attempt_step_2_a, attempt_step_1_a],
          created_by: user
        )

      retry_attempt_1 =
        Repo.get_by(Lightning.Attempt,
          work_order_id: workorder_1.id,
          starting_job_id: job_a.id
        )

      retry_attempt_2 =
        Repo.get_by(Lightning.Attempt,
          work_order_id: workorder_2.id,
          starting_job_id: job_a.id
        )

      assert retry_attempt_2.inserted_at
             |> DateTime.before?(retry_attempt_1.inserted_at)
    end
  end

  describe "update_state/1" do
    test "sets the workorders state to running if there are any started attempts" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, work_order} = WorkOrders.update_state(attempt)

      assert work_order.state == :pending

      {:ok, attempt} =
        Repo.update(attempt |> Ecto.Changeset.change(state: :started))

      {:ok, work_order} = WorkOrders.update_state(attempt)

      assert work_order.state == :running
    end
  end
end
