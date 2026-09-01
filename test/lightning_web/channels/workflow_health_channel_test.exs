defmodule LightningWeb.WorkflowHealthChannelTest do
  use LightningWeb.ChannelCase, async: true

  import Lightning.Factories

  setup do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    workflow = insert(:simple_workflow, project: project)

    %{user: user, project: project, workflow: workflow}
  end

  defp join_health(user, project_id, workflow_id) do
    LightningWeb.UserSocket
    |> socket("user_#{user.id}", %{current_user: user})
    |> subscribe_and_join(
      LightningWeb.WorkflowHealthChannel,
      "workflow_health:#{workflow_id}",
      %{"project_id" => project_id}
    )
  end

  describe "join/3" do
    test "a project member can join", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      assert {:ok, _reply, _socket} = join_health(user, project.id, workflow.id)
    end

    test "a non-member is rejected", %{project: project, workflow: workflow} do
      assert {:error, %{reason: "unauthorized"}} =
               join_health(insert(:user), project.id, workflow.id)
    end

    test "a member of another project cannot read this workflow", %{
      user: user,
      project: project
    } do
      other_workflow = insert(:simple_workflow)

      assert {:error, %{reason: "unauthorized"}} =
               join_health(user, project.id, other_workflow.id)

      # Nor by naming the other workflow's own project, which they aren't in.
      assert {:error, %{reason: "unauthorized"}} =
               join_health(user, other_workflow.project_id, other_workflow.id)
    end

    # Support users have no `project_users` row, so a membership check alone
    # would refuse them where the rest of the app admits them.
    test "a support user can join a project that allows support access", %{
      workflow: workflow
    } do
      support_user = insert(:user, support_user: true)
      opted_in = insert(:project, allow_support_access: true)
      opted_in_workflow = insert(:simple_workflow, project: opted_in)

      assert {:ok, _reply, _socket} =
               join_health(support_user, opted_in.id, opted_in_workflow.id)

      # Not a blanket pass: a project that hasn't opted in still refuses them.
      assert {:error, %{reason: "unauthorized"}} =
               join_health(support_user, workflow.project_id, workflow.id)
    end

    test "a member cannot join a project scheduled for deletion", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      project
      |> Ecto.Changeset.change(scheduled_deletion: ~U[2026-01-01 00:00:00Z])
      |> Lightning.Repo.update!()

      assert {:error, %{reason: "unauthorized"}} =
               join_health(user, project.id, workflow.id)
    end

    test "a malformed id is rejected rather than crashing the join", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      assert {:error, %{reason: "unauthorized"}} =
               join_health(user, "not-a-uuid", workflow.id)

      assert {:error, %{reason: "unauthorized"}} =
               join_health(user, project.id, "not-a-uuid")
    end

    test "requires project_id", %{user: user, workflow: workflow} do
      assert {:error, %{reason: reason}} =
               LightningWeb.UserSocket
               |> socket("user_#{user.id}", %{current_user: user})
               |> subscribe_and_join(
                 LightningWeb.WorkflowHealthChannel,
                 "workflow_health:#{workflow.id}",
                 %{}
               )

      assert reason =~ "project_id is required"
    end
  end

  describe "get_outcomes" do
    test "counts runs from the last 30 days, grouped by state", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      %{triggers: [trigger]} = workflow

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: insert(:dataclip),
          state: :failed
        )

      run = fn attrs ->
        insert(
          :run,
          Keyword.merge(
            [
              work_order: work_order,
              starting_trigger: trigger,
              dataclip: insert(:dataclip)
            ],
            attrs
          )
        )
      end

      for state <- [:success, :success, :crashed, :started] do
        run.(state: state)
      end

      # Outside the window — must not be counted.
      run.(state: :success, inserted_at: Timex.shift(Timex.now(), days: -31))

      {:ok, _reply, socket} = join_health(user, project.id, workflow.id)

      ref = push(socket, "get_outcomes", %{})

      assert_reply ref, :ok, outcomes

      assert %{from: from, to: to} = outcomes.window
      assert DateTime.diff(to, from, :day) == 30

      assert %{success: 2, crashed: 1, failed: 0} = outcomes.counts
    end

    test "reports zeroes for a workflow with no runs", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      {:ok, _reply, socket} = join_health(user, project.id, workflow.id)

      ref = push(socket, "get_outcomes", %{})

      assert_reply ref, :ok, outcomes

      assert outcomes.counts == Map.new(Lightning.Run.final_states(), &{&1, 0})
    end
  end

  describe "get_failure_signatures" do
    test "returns the signature parts and run count for each failure", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      %{triggers: [trigger], jobs: [job | _]} = workflow

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: insert(:dataclip),
          state: :failed
        )

      insert(:run,
        work_order: work_order,
        starting_trigger: trigger,
        dataclip: insert(:dataclip),
        state: :failed,
        steps: [
          build(:step,
            job: job,
            input_dataclip: build(:dataclip),
            exit_reason: "fail",
            error_type: "RuntimeError"
          )
        ]
      )

      {:ok, _reply, socket} = join_health(user, project.id, workflow.id)

      ref = push(socket, "get_failure_signatures", %{})

      assert_reply ref, :ok, reply

      assert DateTime.diff(reply.window.to, reply.window.from, :day) == 30

      assert [
               %{
                 count: 1,
                 exit_reason: "fail",
                 error_type: "RuntimeError",
                 step_name: step_name,
                 adaptor: adaptor
               }
             ] = reply.signatures

      assert step_name == job.name
      assert adaptor == job.adaptor
    end

    test "returns an empty list for a workflow with no failures", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      {:ok, _reply, socket} = join_health(user, project.id, workflow.id)

      ref = push(socket, "get_failure_signatures", %{})

      assert_reply ref, :ok, %{signatures: []}
    end
  end
end
