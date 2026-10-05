defmodule LightningWeb.ConfirmationLockoutRecoveryTest do
  @moduledoc """
  The payload routes an account past its confirmation deadline must not reach,
  and the four things it must still be able to do: resend the link, open it,
  correct its address, log out.

  The refutes and the positive control build their requests from the same
  `payload_requests/3`, so neither side can quietly stop covering a route.
  """
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Lightning.Accounts
  alias Lightning.Accounts.UserToken

  # The secrets the payload routes carry.
  @collection_secret "8201015800083"
  @dataclip_secret "confidential-payload"

  # `root.html.heex` interpolates the socket token into `window.userToken`.
  # An empty assignment is fine; a populated one is a working credential.
  @user_token_regex ~r/window\.userToken = ".+"/

  setup do
    Mox.stub(Lightning.MockConfig, :check_flag?, fn
      :require_email_verification -> true
      flag -> Lightning.Config.API.check_flag?(flag)
    end)

    :ok
  end

  describe "a locked-out account" do
    test "is served none of the payload routes", %{conn: conn} do
      user = locked_out_user()
      project = project_for(user)

      for {what, secret, request} <- payload_requests(conn, user, project) do
        refute_serves(request, secret, what)
      end
    end

    test "keeps the escape hatch open", %{conn: conn} do
      user = locked_out_user()
      authed = log_in_user(conn, user)

      # Resend. All the recovery routes sit inside the authenticated scope, so
      # a check that halts without exempting them locks the account out of the
      # only way to unlock itself.
      resend = get(authed, ~p"/users/send-confirmation-email")
      assert redirected_to(resend) == "/projects"
      assert_email_sent(subject: "Confirm your OpenFn account", to: user.email)

      # Which lands, like everything else, on the page it is confined to — and
      # that page renders rather than bouncing again.
      assert authed |> get(~p"/projects") |> redirected_to() ==
               "/users/confirm-required"

      assert {:ok, _view, _html} = live(authed, ~p"/users/confirm-required")

      # Opening the link confirms the account.
      confirmed = post(authed, ~p"/users/confirm/#{confirmation_token(user)}")
      assert redirected_to(confirmed)
      assert Repo.reload!(user).confirmed_at

      # And logging out still works — the session token stops resolving.
      token = Accounts.generate_user_session_token(user)

      logout =
        build_conn()
        |> init_test_session(%{})
        |> put_session(:user_token, token)
        |> get(~p"/users/log_out")

      assert redirected_to(logout) == ~p"/users/log_in"
      refute Accounts.get_user_by_session_token(token)
    end

    test "regains access on the same session the moment it confirms",
         %{conn: conn} do
      user = locked_out_user()
      project = project_for(user)
      authed = log_in_user(conn, user)

      assert authed
             |> get(~p"/download/yaml?#{%{id: project.id}}")
             |> redirected_to() == "/users/confirm-required"

      assert authed
             |> post(~p"/users/confirm/#{confirmation_token(user)}")
             |> redirected_to()

      # No fresh login: the decision is recomputed per request rather than
      # latched into the session when it was created.
      assert authed
             |> get(~p"/download/yaml?#{%{id: project.id}}")
             |> response(200) =~ project.name

      assert {:ok, _view, _html} = live(authed, ~p"/projects")
    end

    test "that is the first superuser can let itself back in", %{conn: conn} do
      # `superuser_registration_changeset/2` sets no `confirmed_at`, so a fresh
      # install with the flag on locks its own operator out of `/settings`
      # after 48 hours. This is the behaviour change most likely to arrive as a
      # support ticket.
      {:ok, admin} =
        Accounts.register_superuser(%{
          email: "operator-#{Ecto.UUID.generate()}@example.com",
          first_name: "Operator",
          last_name: "One",
          password: "hello world!"
        })

      refute admin.confirmed_at

      admin =
        Repo.update!(Changeset.change(admin, %{inserted_at: hours_ago(50)}))

      authed = log_in_user(conn, admin)

      assert {:error, {_redirect, %{to: "/users/confirm-required"}}} =
               live(authed, ~p"/settings/users")

      assert authed
             |> get(~p"/users/send-confirmation-email")
             |> redirected_to()

      assert_email_sent(subject: "Confirm your OpenFn account", to: admin.email)

      assert authed
             |> post(~p"/users/confirm/#{confirmation_token(admin)}")
             |> redirected_to()

      {:ok, _view, html} = live(authed, ~p"/settings/users")
      assert html =~ admin.email
    end
  end

  describe "an account that is not locked out" do
    test "inside the grace period, or on a flag-off instance, is unaffected",
         %{conn: conn} do
      fresh = insert(:user, confirmed_at: nil, inserted_at: DateTime.utc_now())
      fresh_project = project_for(fresh)
      fresh_conn = log_in_user(conn, fresh)

      assert fresh_conn
             |> get(~p"/download/yaml?#{%{id: fresh_project.id}}")
             |> response(200) =~ fresh_project.name

      assert {:ok, _view, _html} = live(fresh_conn, ~p"/projects")

      # Past the deadline, but the operator never turned the flag on.
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> false
        flag -> Lightning.Config.API.check_flag?(flag)
      end)

      stale = locked_out_user()
      stale_project = project_for(stale)
      stale_conn = log_in_user(conn, stale)

      assert stale_conn
             |> get(~p"/download/yaml?#{%{id: stale_project.id}}")
             |> response(200) =~ stale_project.name

      assert {:ok, _view, _html} = live(stale_conn, ~p"/projects")
    end

    test "is served every payload route in full", %{conn: conn} do
      # Positive control for every `refute_serves` above. Each of those passes
      # on an empty body, and an empty body is what a renamed route, a changed
      # template or a 500 produces — so without this, a fix that broke the
      # downloads outright would make the lockout tests greener.
      #
      # Same account shape as `locked_out_user/1` with the flag off, which is
      # the closest thing to "nothing is in the way".
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> false
        flag -> Lightning.Config.API.check_flag?(flag)
      end)

      user = locked_out_user()
      project = project_for(user)

      for {what, secret, request} <- payload_requests(conn, user, project) do
        assert request.status == 200,
               "positive control: #{what} answered #{request.status}, so the " <>
                 "lockout test's refute on it proves nothing"

        assert response(request, 200) =~ secret,
               "positive control: #{what} did not carry #{inspect(secret)}, " <>
                 "so the lockout test's refute on it proves nothing"
      end
    end
  end

  # The four requests the lockout test refutes and the control asserts, built
  # in one place so neither side can quietly stop covering a route.
  defp payload_requests(conn, user, project) do
    collection = insert(:collection, project: project)

    insert(:collection_item,
      collection: collection,
      key: "patient-1",
      value: ~s({"nid": "#{@collection_secret}"})
    )

    dataclip =
      insert(:dataclip,
        project: project,
        type: :http_request,
        body: %{"household" => @dataclip_secret}
      )

    authed = log_in_user(conn, user)

    [
      {"collection download", @collection_secret,
       authed
       # Without this the route negotiates differently and the request lands
       # in a different code path than the one being tested.
       |> put_req_header("accept", "text/html,*/*")
       |> get(~p"/download/collections/#{project.id}/#{collection.name}")},
      {"project yaml export", project.name,
       get(authed, ~p"/download/yaml?#{%{id: project.id}}")},
      {"dataclip body", @dataclip_secret,
       get(authed, ~p"/dataclip/body/#{dataclip.id}")},
      {"user-socket token on an authenticated page", @user_token_regex,
       get(authed, ~p"/projects")}
    ]
  end

  # Any shape of refusal counts — a redirect, a 401, a 403, or a 200 that
  # carries none of the data — so the tests do not pin our particular one.
  defp refute_serves(conn, secret, what) do
    body = if conn.status in 200..299, do: response(conn, conn.status), else: ""

    refute body =~ secret,
           "#{what} served its payload to a locked-out account " <>
             "(status #{conn.status})"
  end

  defp locked_out_user(attrs \\ []) do
    insert(
      :user,
      Keyword.merge([confirmed_at: nil, inserted_at: hours_ago(50)], attrs)
    )
  end

  defp project_for(user) do
    insert(:project, project_users: [%{user: user, role: :owner}])
  end

  defp confirmation_token(user) do
    {encoded_token, user_token} =
      UserToken.build_email_token(user, "confirm", user.email)

    Repo.insert!(user_token)

    encoded_token
  end

  defp hours_ago(hours) do
    DateTime.utc_now()
    |> DateTime.add(-hours, :hour)
    |> DateTime.truncate(:second)
  end
end
