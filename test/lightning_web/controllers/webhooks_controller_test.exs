defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false
  use Mimic

  alias Lightning.{Invocation, Repo}

  import Lightning.JobsFixtures

  describe "POST /i" do
    test "with a trigger id", %{conn: conn} do
      expect(Lightning.Pipeline.Runner, :start, fn _run ->
        %Lightning.Runtime.Result{}
      end)

      job = job_fixture()

      message = %{"foo" => "bar"}
      conn = post(conn, "/i/#{job.trigger.id}", message)

      assert %{"work_order_id" => _, "run_id" => run_id} =
               json_response(conn, 200)

      %{input_dataclip: %{body: body}} =
        Invocation.get_run!(run_id)
        |> Repo.preload(:input_dataclip)

      assert body == message

      conn = post(conn, "/i/bar")
      assert json_response(conn, 404) == %{}
    end
  end

  test "return 403 on a disabled message", %{conn: conn} do
    job = job_fixture(enabled: false)

    conn = post(conn, "/i/#{job.trigger.id}", %{"foo" => "bar"})

    assert %{"message" => message} = json_response(conn, 403)

    assert message =~ "Unable to process request"
  end
end
