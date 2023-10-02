defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false
  use Mimic

  alias Lightning.{Invocation, Repo}

  import Lightning.JobsFixtures

  describe "a POST request to '/i'" do
    test "with a valid trigger id instantiates a workorder and responds with 200",
         %{conn: conn} do
      Oban.Testing.with_testing_mode(:inline, fn ->
        expect(Lightning.Pipeline.Runner, :start, fn _run ->
          %Lightning.Runtime.Result{}
        end)

        %{job: job, trigger: trigger, edge: _edge} = workflow_job_fixture()

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
  end

  test "return 403 on a disabled message", %{conn: conn} do
    %{job: _job, trigger: trigger, edge: _edge} =
      workflow_job_fixture(enabled: false)

    conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})

    assert %{"message" => message} = json_response(conn, 403)

    assert message =~ "Unable to process request, trigger is disabled."
  end
end
