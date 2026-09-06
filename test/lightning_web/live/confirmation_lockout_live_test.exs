defmodule LightningWeb.ConfirmationLockoutLiveTest do
  @moduledoc """
  What an account past its confirmation deadline can and cannot mount.

  Nothing here names the module that refuses the mount. The claims are that the
  view does not render, that the landing page does, and that a confirmed
  account is untouched — a reader should be able to move the check between the
  plug and the mount hook without editing a line of this file.
  """
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Accounts

  # `root.html.heex` interpolates the socket token into `window.userToken`.
  # An empty assignment is fine; a populated one is a working credential.
  @user_token_regex ~r/window\.userToken = ".+"/

  # The six admin LiveViews rendered through `settings.html.heex`, which never
  # carried a confirmation condition of any kind — so a fix aimed at
  # `live.html.heex` leaves every one of them serving in full.
  @admin_routes [
    "/settings/users",
    "/settings/users/new",
    "/settings/projects",
    "/settings/audit",
    "/settings/authentication",
    "/settings/collections"
  ]

  setup do
    Mox.stub(Lightning.MockConfig, :check_flag?, fn
      :require_email_verification -> true
      flag -> Lightning.Config.API.check_flag?(flag)
    end)

    :ok
  end

  describe "a locked-out account" do
    test "cannot mount any of the admin LiveViews", %{conn: conn} do
      admin = locked_out_user(role: :superuser)
      colleague = insert(:user)
      actor = insert(:user)
      insert(:audit, actor_id: actor.id, actor_type: :user)

      conn = log_in_user(conn, admin)

      for path <- @admin_routes do
        assert {:error, {_redirect, %{to: "/users/confirm-required"}}} =
                 live(conn, path),
               "#{path} mounted for a locked-out superuser"
      end

      # Positive control. Confirm the same account on the same session and all
      # six mount, two of them carrying a canary that a blanked page would not:
      # a colleague's address on the user list, and an actor's address on the
      # audit trail. "Audit" itself is only a nav label and would survive an
      # emptied page body.
      confirm(admin)

      for path <- @admin_routes do
        assert {:ok, _view, _html} = mount(conn, path),
               "#{path} did not mount for a confirmed superuser, so the " <>
                 "lockout assertion on it proves nothing"
      end

      {:ok, _view, users_html} = live(conn, ~p"/settings/users")
      assert users_html =~ colleague.email

      {:ok, _view, audit_html} = live(conn, ~p"/settings/audit")
      assert audit_html =~ actor.email
    end

    test "cannot reach its profile or mint a personal access token",
         %{conn: conn} do
      user = locked_out_user()
      conn = log_in_user(conn, user)

      # `/profile` was the redirect target in an earlier design and is now
      # closed like everything else. `/profile/tokens` is PAT creation — the
      # thing a prefix entry of `["profile"]` would have handed over.
      for path <- [~p"/profile", ~p"/profile/tokens"] do
        assert {:error, {_redirect, %{to: "/users/confirm-required"}}} =
                 live(conn, path),
               "#{path} mounted for a locked-out account"
      end

      confirm(user)

      {:ok, _view, profile_html} = live(conn, ~p"/profile")
      assert profile_html =~ user.email

      assert {:ok, _view, _html} = live(conn, ~p"/profile/tokens")
    end

    test "reaches the page it is confined to rather than looping",
         %{conn: conn} do
      user = locked_out_user()
      conn = log_in_user(conn, user)

      # One assertion, and it is the difference between a fix and an outage:
      # the landing page is behind the same authenticated pipeline as
      # everything else, so it has to be exempted from the request check and
      # kept clear of the mount check at the same time.
      {:ok, _view, html} = live(conn, ~p"/users/confirm-required")
      assert html =~ "blocked pending email confirmation"

      assert conn |> get(~p"/users/confirm-required") |> html_response(200)
    end

    test "is handed no socket token and no project inventory", %{conn: conn} do
      user = locked_out_user()
      project = insert(:project, project_users: [%{user: user, role: :owner}])

      blocked = conn |> log_in_user(user) |> get(~p"/projects")
      html = response(blocked, blocked.status)

      assert redirected_to(blocked) == "/users/confirm-required"

      # `window.userToken` is what opens `/socket`.
      refute html =~ @user_token_regex

      # The project picker serialises every project the account can see —
      # id, name and full parent path — into `data-items`, outside anything
      # the layout was ever conditioned on.
      refute html =~ project.name
      refute html =~ project.id

      # Positive control, so the three refutes above are not passing on an
      # empty body for some unrelated reason.
      confirm(user)
      served = conn |> log_in_user(user) |> get(~p"/projects")
      served_html = response(served, 200)

      assert served_html =~ @user_token_regex
      assert served_html =~ project.name
      assert served_html =~ project.id
    end

    test "a mid-session lockout takes effect on the next mount, not on the live process",
         %{conn: conn} do
      user = insert(:user, confirmed_at: DateTime.utc_now())
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/projects", on_error: :raise)

      lock_out(user)

      render_hook(view, "toggle_sidebar", %{})

      # A known gap, recorded rather than endorsed: every check this bag adds
      # runs at a boundary — a request, a mount, a join — and none of them
      # reaches a LiveView process that is already running. Evicting live
      # processes on an account-state change is deferred to its own piece of
      # work. When that lands this assertion fails, which is the point of it.
      assert Accounts.get_preference(user, "sidebar_collapsed") == true

      # The next mount on the same session is refused.
      assert {:error, {redirect, %{to: "/users/confirm-required"}}} =
               live(conn, ~p"/projects")

      assert redirect in [:redirect, :live_redirect]
    end
  end

  # `/settings/authentication` live-redirects to `/settings/authentication/new`
  # on an instance with no auth provider configured, so the positive control
  # follows one hop before deciding the page rendered.
  defp mount(conn, path) do
    case live(conn, path) do
      {:error, {:live_redirect, %{to: to}}} -> live(conn, to)
      result -> result
    end
  end

  defp locked_out_user(attrs \\ []) do
    insert(
      :user,
      Keyword.merge([confirmed_at: nil, inserted_at: hours_ago(50)], attrs)
    )
  end

  defp lock_out(user) do
    Repo.update!(
      Changeset.change(user, %{confirmed_at: nil, inserted_at: hours_ago(50)})
    )
  end

  defp confirm(user) do
    Repo.update!(
      Changeset.change(user, %{
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    )
  end

  defp hours_ago(hours) do
    DateTime.utc_now()
    |> DateTime.add(-hours, :hour)
    |> DateTime.truncate(:second)
  end
end
