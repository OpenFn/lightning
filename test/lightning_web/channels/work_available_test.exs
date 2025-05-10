defmodule LightningWeb.WorkAvailableTest do
  use LightningWeb.ChannelCase, async: false

  import Lightning.Factories

  alias Lightning.WorkOrders
  alias Lightning.Workers

  # this ensures the WorkAvailable server inherits the mox stubs
  setup :set_mox_from_context

  setup context do
    {:ok, bearer, claims} =
      Workers.WorkerToken.generate_and_sign(
        %{},
        Lightning.Config.worker_token_signer()
      )

    socket =
      socket(LightningWeb.WorkerSocket, "socket_id", %{
        token: bearer,
        claims: claims,
        work_listener_debounce_time: context[:debounce_time] || 100
      })

    {:ok, _, socket} =
      socket |> subscribe_and_join(LightningWeb.WorkerChannel, "worker:queue")

    %{socket: socket}
  end

  test "message is sent out when a run is created" do
    project = insert(:project)

    %{triggers: [trigger]} =
      workflow = insert(:simple_workflow, project: project) |> with_snapshot()

    {:ok, %{runs: [_run]}} =
      WorkOrders.create_for(trigger,
        workflow: workflow,
        dataclip: params_with_assocs(:dataclip)
      )

    assert_push "work-available", %{}
  end

  @tag debounce_time: 50
  test "message is sent out within the specified debounce time once even if multiple runs are created" do
    project = insert(:project)

    %{triggers: [trigger]} =
      workflow = insert(:simple_workflow, project: project) |> with_snapshot()

    for _i <- 1..10 do
      {:ok, %{runs: [_run]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )
    end

    assert_push "work-available", %{}

    # no other message out
    refute_push "work-available", %{}, 55
  end
end
