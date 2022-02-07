defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase

  import Lightning.JobsFixtures

  test "GET /", %{conn: conn} do
    job = job_fixture(%{trigger: %{}})

    conn = post(conn, "/i/#{job.id}")
    assert json_response(conn, 200) == %{"foo" => "bar"}

    conn = post(conn, "/i/bar")
    assert json_response(conn, 404) == %{"foo" => "bar"}
  end
end
