defmodule LightningWeb.UpdateNoticeTest do
  # async: false because the pages read the globally named checker.
  use LightningWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  alias Lightning.UpdateCheck.Checker

  setup :set_mox_global

  @behind %{
    current: "2.19.1",
    latest: "2.19.2",
    latest_tag: "v2.19.2",
    update_available?: true,
    registry: "https://registry-1.docker.io",
    repository: "openfn/lightning",
    instructions_url:
      "https://docs.openfn.org/documentation/deploy/options#technical-guidelines",
    checked_at: ~U[2026-10-29 07:00:00Z]
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
               "v2.19.2 is available"
             )

      assert render(view) =~ "Click for upgrade info"
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
               "v2.19.2 is available. Please upgrade."
             )

      assert has_element?(
               view,
               ~s{#update-instructions-link[href="#{@behind.instructions_url}"]}
             )

      assert has_element?(view, "#update-latest-version", "v2.19.2")
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
  end
end
