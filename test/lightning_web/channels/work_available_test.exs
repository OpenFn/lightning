defmodule LightningWeb.WorkAvailableTest do
  use LightningWeb.ChannelCase, async: false

  import Lightning.Factories

  alias Lightning.Projects
  alias Lightning.WorkOrders
  alias Lightning.Workers

  # this ensures the WorkAvailable server inherits the mox stubs
  setup :set_mox_from_context

  setup do
    stub_with(
      Lightning.Extensions.MockProjectHook,
      Lightning.Extensions.ProjectHook
    )

    {:ok, bearer, claims} =
      Workers.WorkerToken.generate_and_sign(
        %{},
        Lightning.Config.worker_token_signer()
      )

    socket =
      LightningWeb.WorkerSocket
      |> socket("socket_id", %{token: bearer, claims: claims})

    {:ok, _, socket} =
      socket |> subscribe_and_join(LightningWeb.WorkerChannel, "worker:queue")

    %{socket: socket}
  end

  test "message is sent when a run from an existing project is created",
       %{test: test} do
    # project is created before starting the server
    project = insert(:project)

    %{triggers: [trigger]} =
      workflow = insert(:simple_workflow, project: project) |> with_snapshot()

    start_supervised!(
      {LightningWeb.WorkAvailable, [name: test, debounce_time_ms: 0]}
    )

    {:ok, %{runs: [_run]}} =
      WorkOrders.create_for(trigger,
        workflow: workflow,
        dataclip: params_with_assocs(:dataclip)
      )

    assert_push "work-available", %{}
  end

  test "message is sent out when a run from a new project is created",
       %{test: test} do
    start_supervised!(
      {LightningWeb.WorkAvailable, [name: test, debounce_time_ms: 0]}
    )

    user = insert(:user)

    # We're creating a project after starting the server
    {:ok, project} =
      Projects.create_project(%{
        name: "some-random-project",
        project_users: [%{role: :owner, user_id: user.id}]
      })

    %{triggers: [trigger]} =
      workflow = insert(:simple_workflow, project: project) |> with_snapshot()

    {:ok, %{runs: [_run]}} =
      WorkOrders.create_for(trigger,
        workflow: workflow,
        dataclip: params_with_assocs(:dataclip)
      )

    assert_push "work-available", %{}
  end

  test "message is sent out within the specified debounce time once even if multiple runs are created",
       %{test: test} do
    project = insert(:project)

    %{triggers: [trigger]} =
      workflow = insert(:simple_workflow, project: project) |> with_snapshot()

    debounce_time = 50

    start_supervised!(
      {LightningWeb.WorkAvailable, [name: test, debounce_time_ms: debounce_time]}
    )

    for _i <- 1..10 do
      {:ok, %{runs: [_run]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )
    end

    assert_push "work-available", %{}

    # no other message out
    refute_push "work-available", %{}, debounce_time + 5
  end
end
