defmodule LightningWeb.ProjectLive.SupportAccessTeardownTest do
  @moduledoc """
  Session teardown when a project's support-access toggle flips.
  """
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.ProjectsHelpers
  import Phoenix.LiveViewTest

  # The broadcast lands in the victim's mailbox synchronously, but the teardown
  # is asynchronous relative to the test process.
  @teardown_timeout 2_000

  setup do
    owner = insert(:user, first_name: "Olga", last_name: "Owner")
    member = insert(:user, first_name: "Eli", last_name: "Editor")
    support_user = insert(:user, role: :superuser, support_user: true)

    project =
      insert(:project,
        allow_support_access: true,
        project_users: [
          %{user: owner, role: :owner},
          %{user: member, role: :editor}
        ]
      )

    %{
      project: project,
      owner: owner,
      member: member,
      support_user: support_user
    }
  end

  describe "revoking support access" do
    test "bounces a support user's settings socket and denies the re-mount", %{
      project: project,
      owner: owner,
      support_user: support_user
    } do
      conn = user_conn(support_user)
      path = ~p"/projects/#{project}/settings"

      {:ok, victim, _html} = live(conn, path, on_error: :raise)

      assert render(victim) =~ "Project settings"

      monitor_ref = Process.monitor(victim.pid)

      revoke_support_access(project, owner)

      assert_redirect(victim, path, @teardown_timeout)

      assert_receive {:DOWN, ^monitor_ref, :process, _pid, _reason},
                     @teardown_timeout

      assert {:error,
              {:redirect, %{to: "/projects", flash: %{"nav" => :not_found}}}} =
               live(conn, path)
    end

    test "bounces a support user's workflow index socket too", %{
      project: project,
      owner: owner,
      support_user: support_user
    } do
      conn = user_conn(support_user)
      path = ~p"/projects/#{project}/w"

      {:ok, victim, _html} = live(conn, path, on_error: :raise)

      monitor_ref = Process.monitor(victim.pid)

      revoke_support_access(project, owner)

      assert_redirect(victim, path, @teardown_timeout)

      assert_receive {:DOWN, ^monitor_ref, :process, _pid, _reason},
                     @teardown_timeout

      assert {:error, {:redirect, %{to: "/projects"}}} = live(conn, path)
    end

    test "leaves a support user who is also a member mounted", %{
      project: project,
      owner: owner,
      support_user: support_user
    } do
      insert(:project_user, project: project, user: support_user, role: :viewer)

      {:ok, view, _html} =
        live(user_conn(support_user), ~p"/projects/#{project}/settings",
          on_error: :raise
        )

      revoke_support_access(project, owner)

      # `render/1` is a call into the LiveView, so it cannot answer until the
      # event broadcast above has been handled.
      assert render(view) =~ "Project settings"
    end

    test "leaves an ordinary member mounted", %{
      project: project,
      owner: owner,
      member: member
    } do
      {:ok, view, _html} =
        live(user_conn(member), ~p"/projects/#{project}/settings",
          on_error: :raise
        )

      revoke_support_access(project, owner)

      assert render(view) =~ "Project settings"
    end
  end

  describe "revoking support access from the owner's settings LiveView" do
    test "bounces the support user and leaves the owner mounted", %{
      project: project,
      owner: owner,
      support_user: support_user
    } do
      path = ~p"/projects/#{project}/settings"

      {:ok, victim, _html} =
        live(user_conn(support_user), path, on_error: :raise)

      {:ok, owner_view, _html} =
        live(user_conn(owner), path, on_error: :raise)

      Mox.allow(LightningMock, self(), owner_view.pid)

      monitor_ref = Process.monitor(victim.pid)

      assert owner_view
             |> element("#toggle-support-access")
             |> render_click() =~ "Revoked access to support users"

      assert_receive {:DOWN, ^monitor_ref, :process, _pid, _reason},
                     @teardown_timeout

      refute Repo.reload!(project).allow_support_access
    end
  end
end
