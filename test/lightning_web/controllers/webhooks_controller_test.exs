defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false
  use Mimic

  alias Lightning.{Invocation, Repo}

  import Lightning.JobsFixtures

  test "POST /i", %{conn: conn} do
    expect(Lightning.Pipeline.Runner, :start, fn _run -> %Engine.Result{} end)
    job = job_fixture()

    message = %{"foo" => "bar"}
    conn = post(conn, "/i/#{job.id}", message)
    assert %{"event_id" => _, "run_id" => run_id} = json_response(conn, 200)

    %{input_dataclip: %{body: body}} =
      Invocation.get_run!(run_id)
      |> Repo.preload(:input_dataclip)

    assert body == message

    conn = post(conn, "/i/bar")
    assert json_response(conn, 404) == %{}
  end
end
