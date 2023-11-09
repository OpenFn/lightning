defmodule LightningWeb.RunLive.RunViewerLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias LightningWeb.RunLive.RunViewerLive
  alias Lightning.Attempts

  describe "mounting" do
    test "", %{conn: conn} do
      user = insert(:user)
      dataclip = insert(:dataclip)
      %{triggers: [_trigger], jobs: [job]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(job,
          workflow: workflow,
          dataclip: dataclip,
          created_by: user
        )
        |> insert()

      {:ok, view, _html} =
        live_isolated(conn, RunViewerLive,
          session: %{"attempt_id" => attempt.id}
        )

      assert view |> render() =~ "Pending"

      assert {:ok, [attempt]} = Attempts.claim()

      assert view |> render() =~ "Starting"

      {:ok, _run} =
        Attempts.start_run(%{
          "attempt_id" => attempt.id,
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "run_id" => _run_id = Ecto.UUID.generate()
        })

      {:ok, log_line} =
        Attempts.append_attempt_log(attempt, %{
          message: "hello",
          timestamp: DateTime.utc_now()
        })

      view |> render()

      assert view |> has_element?("tr#log_lines-#{log_line.id}", "hello")
    end
  end
end
