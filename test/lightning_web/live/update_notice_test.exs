defmodule LightningWeb.UpdateNoticeTest do
  # async: false because the pages read the globally named checker.
  use LightningWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Mox
  import Phoenix.LiveViewTest

  alias Lightning.UpdateCheck.Checker
  alias LightningWeb.WorkerPresence

  setup :set_mox_global

  @behind %{
    current: "2.19.1",
    latest: "2.19.2",
    latest_tag: "2.19.2",
    update_available?: true,
    registry: "https://registry-1.docker.io",
    repository: "openfn/lightning",
    instructions_url:
      "https://docs.openfn.org/documentation/deploy/options#technical-guidelines",
    checked_at: ~U[2026-10-29 07:00:00Z],
    worker: %{
      latest: "1.30.0",
      latest_tag: "1.30.0",
      registry: "https://registry-1.docker.io",
      repository: "openfn/ws-worker"
    }
  }

  @up_to_date %{@behind | current: "2.19.2", update_available?: false}

  defp start_checker(status) do
    start_supervised!(
      {Checker,
       name: Checker,
       check_fun: fn -> {:ok, status} end,
       interval: :timer.hours(1),
       initial_delay: :timer.hours(1)}
    )

    {:ok, ^status} = Checker.check_now(Checker)
    :ok
  end

  defp start_failing_checker(error) do
    start_supervised!(
      {Checker,
       name: Checker,
       check_fun: fn -> error end,
       interval: :timer.hours(1),
       initial_delay: :timer.hours(1)}
    )

    :ok
  end

  defp connect_worker(version, capacity \\ 1) do
    pid = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(pid, :kill) end)

    {:ok, _ref} =
      WorkerPresence.track_worker(pid, "worker-#{inspect(pid)}", capacity,
        worker_version: version,
        api_version: "1.2"
      )

    pid
  end

  describe "sidebar" do
    test "a regular user sees the chip badge but no callout", %{conn: conn} do
      start_checker(@behind)
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      {:ok, view, _html} = live(conn, ~p"/projects")

      assert has_element?(view, ".version-update-dot")
      refute has_element?(view, "#update-callout")
    end

    test "a superuser sees a callout linking to the maintenance page",
         %{conn: conn} do
      start_checker(@behind)
      %{conn: conn} = register_and_log_in_superuser(%{conn: conn})

      {:ok, view, _html} = live(conn, ~p"/projects")

      assert has_element?(view, ".version-update-dot")

      assert has_element?(
               view,
               ~s{#update-callout a[href="/settings/maintenance#update-card"]},
               "New version available"
             )

      assert render(view) =~ "Click for upgrade info"
    end

    test "a superuser sees the same callout when only a worker is behind",
         %{conn: conn} do
      start_checker(@up_to_date)
      connect_worker("1.29.6")
      %{conn: conn} = register_and_log_in_superuser(%{conn: conn})

      {:ok, view, _html} = live(conn, ~p"/projects")

      assert has_element?(view, "#update-callout", "New version available")
      assert has_element?(view, ".version-update-dot")
    end

    test "a green dot shows when on the latest version", %{conn: conn} do
      start_checker(@up_to_date)
      %{conn: conn} = register_and_log_in_superuser(%{conn: conn})

      {:ok, view, _html} = live(conn, ~p"/projects")

      assert has_element?(view, ".version-current-dot")
      refute has_element?(view, ".version-update-dot")
      refute has_element?(view, "#update-callout")
    end

    test "nothing is shown when the check isn't running", %{conn: conn} do
      %{conn: conn} = register_and_log_in_superuser(%{conn: conn})

      {:ok, view, _html} = live(conn, ~p"/projects")

      refute has_element?(view, ".version-update-dot")
      refute has_element?(view, ".version-current-dot")
      refute has_element?(view, "#update-callout")
    end
  end

  describe "maintenance page update card" do
    setup :register_and_log_in_superuser

    test "shows the upgrade steps when behind", %{conn: conn} do
      start_checker(@behind)

      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      assert has_element?(view, "#update-status", "Update available")

      assert has_element?(
               view,
               "#update-available-callout",
               "2.19.2 is available. Please upgrade."
             )

      assert has_element?(
               view,
               ~s{#update-instructions-link[href="#{@behind.instructions_url}"]}
             )

      assert has_element?(view, "#update-latest-version", "2.19.2")
      refute has_element?(view, "#update-latest-version", "v2.19.2")
    end

    test "the version card doesn't flag an app that's up to date", %{conn: conn} do
      start_checker(@up_to_date)
      connect_worker("1.29.6")

      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      assert has_element?(view, "#update-status", "Up to date")
      refute has_element?(view, "#update-available-callout")
    end

    test "says when the check is turned off", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      assert has_element?(view, "#update-status", "Not checked yet")
      assert has_element?(view, "#update-check-disabled")
      assert has_element?(view, "#check-for-update-button[disabled]")
    end

    test "Check now runs a check and reports the result", %{conn: conn} do
      stub(Lightning.MockConfig, :update_check_enabled?, fn -> true end)
      start_checker(@up_to_date)

      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      view |> element("#check-for-update-button") |> render_click()
      render_async(view)

      assert has_element?(
               view,
               "p[role=alert][phx-value-key=info]",
               "You're on the latest version."
             )

      assert has_element?(view, "#update-status", "Up to date")
    end

    test "Check now says when the checker isn't running", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      render_click(view, "check_for_update", %{})
      render_async(view)

      assert has_element?(
               view,
               "p[role=alert][phx-value-key=error]",
               "The update check is turned off."
             )
    end

    test "Check now says when the channel tag isn't a release", %{conn: conn} do
      stub(Lightning.MockConfig, :update_check_enabled?, fn -> true end)
      start_failing_checker({:error, :no_release_found})

      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      capture_log(fn ->
        view |> element("#check-for-update-button") |> render_click()
        render_async(view)
      end)

      assert has_element?(
               view,
               "p[role=alert][phx-value-key=error]",
               "no release matches the latest tag"
             )

      assert has_element?(view, "#update-status", "Not checked yet")
    end

    test "Check now reports any other failure", %{conn: conn} do
      stub(Lightning.MockConfig, :update_check_enabled?, fn -> true end)
      start_failing_checker({:error, {:unexpected_status, 429}})

      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      capture_log(fn ->
        view |> element("#check-for-update-button") |> render_click()
        render_async(view)
      end)

      assert has_element?(
               view,
               "p[role=alert][phx-value-key=error]",
               "Update check failed: {:unexpected_status, 429}"
             )
    end
  end

  describe "maintenance page workers card" do
    setup :register_and_log_in_superuser

    test "groups connected workers by version and flags the outdated ones",
         %{conn: conn} do
      start_checker(@up_to_date)
      connect_worker("1.30.0", 5)
      connect_worker("1.29.6", 2)
      connect_worker("1.29.6", 2)

      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      assert has_element?(view, "#workers-status", "Update available")

      assert has_element?(
               view,
               "#worker-update-callout",
               "ws-worker 1.30.0 is available. Please upgrade."
             )

      assert has_element?(view, "#worker-update-callout", "2 of 3")
      assert has_element?(view, "#worker-group-0", "1.30.0")
      refute has_element?(view, "#worker-group-0", "Outdated")
      assert has_element?(view, "#worker-group-1", "1.29.6")
      assert has_element?(view, "#worker-group-1", "Outdated")
      assert has_element?(view, "#worker-capacity", "9 concurrent runs")
      assert has_element?(view, "#worker-latest-version", "1.30.0")
      refute has_element?(view, "#worker-latest-version", "v1.30.0")
    end

    test "says when no workers are connected", %{conn: conn} do
      start_checker(@up_to_date)

      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      assert has_element?(view, "#workers-status", "None connected")
      assert has_element?(view, "#no-workers")
      refute has_element?(view, "#worker-versions")
    end

    test "workers without a reported version are flagged as outdated",
         %{conn: conn} do
      start_checker(@up_to_date)
      connect_worker(nil)

      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      assert has_element?(view, "#workers-status", "Update available")
      assert has_element?(view, "#worker-group-0", "unknown")
      assert has_element?(view, "#worker-group-0", "Outdated")
      assert has_element?(view, "#worker-update-callout", "1 of 1")
    end

    test "ignores messages it doesn't handle", %{conn: conn} do
      start_checker(@up_to_date)

      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")
      send(view.pid, :unexpected)

      assert render(view) =~ "workers-status"
    end

    test "a worker reporting a leading v is compared and shown like any other",
         %{conn: conn} do
      start_checker(@up_to_date)
      connect_worker("v1.29.6")

      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      assert has_element?(view, "#workers-status", "Update available")
      assert has_element?(view, "#worker-group-0", "1.29.6")
      refute has_element?(view, "#worker-group-0", "v1.29.6")
      assert has_element?(view, "#worker-group-0", "Outdated")
    end

    test "says unknown, not up to date, when no worker release was found",
         %{conn: conn} do
      start_checker(%{@up_to_date | worker: nil})
      connect_worker("1.29.6")

      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      assert has_element?(view, "#workers-status", "Unknown")
      refute has_element?(view, "#worker-latest-version")
      refute has_element?(view, "#worker-update-callout")
    end

    test "updates as workers connect and disconnect", %{conn: conn} do
      start_checker(@up_to_date)

      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")
      assert has_element?(view, "#no-workers")

      # The view hears the same broadcast, so waiting for it here means the
      # view has it queued before the next render.
      Phoenix.PubSub.subscribe(Lightning.PubSub, WorkerPresence.topic())

      pid = connect_worker("1.29.6")
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}
      assert has_element?(view, "#worker-group-0", "1.29.6")
      assert has_element?(view, "#worker-update-callout")

      Process.exit(pid, :kill)
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}
      refute has_element?(view, "#worker-group-0")
      assert has_element?(view, "#no-workers")
    end
  end
end
