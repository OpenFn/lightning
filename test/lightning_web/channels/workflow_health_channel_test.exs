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
    test "counts work orders from the last 30 days, grouped by state", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      %{triggers: [trigger]} = workflow
      dataclip = insert(:dataclip)

      for state <- [:success, :success, :failed, :pending] do
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: state
        )
      end

      # Outside the window — must not be counted.
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        state: :success,
        inserted_at: Timex.shift(Timex.now(), days: -31)
      )

      {:ok, _reply, socket} = join_health(user, project.id, workflow.id)

      ref = push(socket, "get_outcomes", %{})

      assert_reply ref, :ok, outcomes

      assert %{from: from, to: to} = outcomes.window
      assert DateTime.diff(to, from, :day) == 30

      assert outcomes.counts == %{success: 2, failed: 1, pending: 1}
    end

    test "reports zeroes for a workflow with no work orders", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      {:ok, _reply, socket} = join_health(user, project.id, workflow.id)

      ref = push(socket, "get_outcomes", %{})

      assert_reply ref, :ok, outcomes

      assert outcomes.counts == %{success: 0, failed: 0, pending: 0}
    end
  end
end
