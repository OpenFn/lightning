defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false

  alias Lightning.WorkOrders

  import Lightning.JobsFixtures
  import Lightning.Factories

  describe "a POST request to '/i'" do
    test "with a valid trigger id instantiates a workorder", %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      message = %{"foo" => "bar"}
      conn = post(conn, "/i/#{trigger.id}", message)

      assert %{"work_order_id" => work_order_id} =
               json_response(conn, 200)

      work_order =
        WorkOrders.get(work_order_id, include: [:attempts, :dataclip, :trigger])

      assert work_order.dataclip.body == message
      assert work_order.trigger.id == trigger.id

      %{attempts: [attempt]} = work_order
      assert attempt.starting_trigger_id == trigger.id
    end

    test "with an invalid trigger id returns a 404", %{conn: conn} do
      conn = post(conn, "/i/bar")
      assert json_response(conn, 404) == %{}
    end
  end

  test "return 403 on a disabled message", %{conn: conn} do
    flunk("TODO: add `enabled` to triggers")

    %{job: _job, trigger: trigger, edge: _edge} =
      workflow_job_fixture(enabled: false)

    conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})

    assert %{"message" => message} = json_response(conn, 403)

    assert message =~ "Unable to process request, trigger is disabled."
  end
end
