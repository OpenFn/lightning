defmodule LightningWeb.MaintenanceLive.IndexTest do
  # async: false because the icon-refresh test stubs Lightning.Adaptors.StrategyMock
  # globally, which the singleton Scheduler GenServer (not in the test pid's
  # caller chain) needs to see.
  use LightningWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  setup :set_mox_global

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the maintenance page", %{conn: conn} do
      {:ok, _live, html} =
        live(conn, ~p"/settings/maintenance", on_error: :raise)
        |> follow_redirect(conn, "/projects")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end
  end

  describe "Index as a superuser" do
    setup :register_and_log_in_superuser

    test "renders the Refresh Adaptor Registry card", %{conn: conn} do
      html = conn |> open_page() |> render()

      assert html =~ "Maintenance"
      assert html =~ "Refresh Adaptor Registry"
      assert html =~ "Re-fetch the list of available adaptors"
      assert html =~ "Run"
    end

    test "clicking Run flashes that the refresh was queued", %{conn: conn} do
      live = open_page(conn)

      live
      |> element("#refresh-adaptors-button")
      |> render_click()

      assert has_element?(
               live,
               "p[role=alert][phx-value-key=info]",
               "Adaptor refresh queued."
             )
    end

    test "renders the Refresh Adaptor Icons card", %{conn: conn} do
      live = open_page(conn)

      assert render(live) =~ "Refresh Adaptor Icons"
      assert has_element?(live, "#refresh-icons-button")
    end

    test "clicking the icons button starts the refresh and reports the result asynchronously",
         %{conn: conn} do
      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok, %{}}
      end)

      {:ok, live, _html} =
        live(conn, ~p"/settings/maintenance", on_error: :raise)

      html =
        live
        |> element("#refresh-icons-button")
        |> render_click()

      assert html =~ "Icon refresh started."

      render_async(live)

      assert has_element?(
               live,
               "p[role=alert][phx-value-key=info]",
               "Icon refresh complete"
             )
    end

    test "the icons button reports a failed refresh", %{conn: conn} do
      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:error, :boom}
      end)

      live = open_page(conn)

      live
      |> element("#refresh-icons-button")
      |> render_click()

      render_async(live)

      assert has_element?(
               live,
               "p[role=alert][phx-value-key=error]",
               "Icon refresh failed"
             )
    end
  end

  describe "Anonymous usage metrics card" do
    setup :register_and_log_in_superuser

    setup do
      stub(Lightning.MockConfig, :usage_tracking_enabled?, fn -> true end)

      stub(Lightning.MockConfig, :usage_tracking_cleartext_uuids_enabled?, fn ->
        false
      end)

      stub(Lightning.MockConfig, :usage_tracking_host, fn ->
        "https://impact.example.com"
      end)

      :ok
    end

    test "shows the host, UUID and hash when reporting hashed UUIDs",
         %{conn: conn} do
      %{instance_id: instance_id} =
        Lightning.Factories.insert(:usage_tracking_daily_report_configuration)

      hashed_id = Base.encode16(:crypto.hash(:sha256, instance_id))

      live = open_page(conn)

      assert has_element?(live, "#usage-metrics-status", "Enabled")
      refute has_element?(live, "#usage-metrics-disabled-callout")

      assert has_element?(
               live,
               "#usage-metrics-host",
               "https://impact.example.com"
             )

      assert has_element?(
               live,
               "#usage-metrics-links a[href='https://docs.openfn.org/documentation/contribute/impact#the-data-yes-all-of-it']"
             )

      assert has_element?(
               live,
               "#usage-metrics-links a[href='https://www.openfn.org/impact']"
             )

      assert has_element?(
               live,
               "#usage-metrics-links a[href='mailto:admin@openfn.org']"
             )

      assert has_element?(live, "#usage-metrics-instance-id", instance_id)

      assert has_element?(
               live,
               "#copy-usage-metrics-instance-id[data-content='#{instance_id}']"
             )

      assert has_element?(live, "#usage-metrics-hashed-id", hashed_id)

      assert has_element?(
               live,
               "#copy-usage-metrics-hashed-id[data-content='#{hashed_id}']"
             )

      assert has_element?(
               live,
               "#usage-metrics-identity-mode",
               "Only the hashed UUID (SHA-256) is sent"
             )
    end

    test "says the UUID is sent in cleartext when configured", %{conn: conn} do
      stub(Lightning.MockConfig, :usage_tracking_cleartext_uuids_enabled?, fn ->
        true
      end)

      Lightning.Factories.insert(:usage_tracking_daily_report_configuration)

      live = open_page(conn)

      assert has_element?(
               live,
               "#usage-metrics-identity-mode",
               "sent in cleartext"
             )
    end

    test "urges the operator to turn tracking on when disabled", %{conn: conn} do
      stub(Lightning.MockConfig, :usage_tracking_enabled?, fn -> false end)

      Lightning.Factories.insert(:usage_tracking_daily_report_configuration)

      live = open_page(conn)
      html = render(live)

      assert has_element?(live, "#usage-metrics-status", "Disabled")

      assert has_element?(
               live,
               "#usage-metrics-disabled-callout",
               "USAGE_TRACKING_ENABLED=true"
             )

      assert html =~ "Would report to"

      assert has_element?(
               live,
               "#usage-metrics-identity-mode",
               "Nothing is sent while usage metrics are disabled"
             )

      refute has_element?(
               live,
               "#usage-metrics-identity-mode",
               "Only the hashed UUID"
             )
    end

    test "explains when no instance ID exists yet", %{conn: conn} do
      live = open_page(conn)

      assert has_element?(
               live,
               "#usage-metrics-no-instance-id",
               "generated the first time"
             )

      refute has_element?(live, "#usage-metrics-instance-id")
    end
  end

  defp open_page(conn) do
    {:ok, live, _html} = live(conn, ~p"/settings/maintenance", on_error: :raise)
    render_async(live)
    live
  end
end
