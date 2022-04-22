defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: true

  alias Lightning.{Invocation, Repo}

  import Lightning.JobsFixtures

  test "POST /i", %{conn: conn} do
    job = job_fixture(%{trigger: %{}})

    message = %{"foo" => "bar"}
    conn = post(conn, "/i/#{job.id}", message)
    assert %{"event_id" => _, "run_id" => run_id} = json_response(conn, 200)

    %{dataclip: %{body: body}} =
      Invocation.get_run!(run_id)
      |> Repo.preload(:dataclip)

    assert body == message

    conn = post(conn, "/i/bar")
    assert json_response(conn, 404) == %{}
  end
end
