defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false
  use Mimic

  alias Lightning.{Invocation, Repo}

  import Lightning.JobsFixtures

  describe "a POST request to '/i'" do
    setup %{conn: conn} do
      %{job: job, trigger: trigger, edge: _edge} = workflow_job_fixture()

      [conn: conn, job: job, trigger: trigger]
    end

    test "with a valid trigger id instantiates a workorder", %{
      conn: conn,
      job: job,
      trigger: trigger
    } do
      Oban.Testing.with_testing_mode(:inline, fn ->
        expect(Lightning.Pipeline.Runner, :start, fn _run ->
          %Lightning.Runtime.Result{}
        end)

        message = %{"foo" => "bar"}
        conn = post(conn, "/i/#{trigger.id}", message)

        assert %{"work_order_id" => _, "run_id" => run_id} =
                 json_response(conn, 200)

        %{job_id: job_id, input_dataclip: %{body: body}} =
          Invocation.get_run!(run_id)
          |> Repo.preload(:input_dataclip)

        assert job_id == job.id
        assert body == message
      end)
    end

    test "triggers a custom telemetry event", %{conn: conn, trigger: trigger} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:lightning, :workorder, :webhook, :stop]
        ])

      trigger_id = trigger.id

      message = %{"foo" => "bar"}
      post(conn, "/i/#{trigger.id}", message)

      assert_received {
        [:lightning, :workorder, :webhook, :stop],
        ^ref,
        %{},
        %{source_trigger_id: ^trigger_id}
      }
    end

    test "with an invalid trigger id returns a 404", %{conn: conn} do
      conn = post(conn, "/i/bar")
      assert json_response(conn, 404) == %{}
    end
  end

  test "return 403 on a disabled message", %{conn: conn} do
    %{job: _job, trigger: trigger, edge: _edge} =
      workflow_job_fixture(enabled: false)

    conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})

    assert %{"message" => message} = json_response(conn, 403)

    assert message =~ "Unable to process request, trigger is disabled."
  end

  def dummy_event_trigger() do
    :telemetry.span(
      [:lightning, :workorder, :webhook],
      %{source_trigger_id: 99},
      fn ->
        {true, %{source_trigger_id: 99}}
      end
    )
  end
end
