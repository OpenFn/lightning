defmodule LightningWeb.ProjectLive.GithubSyncComponentTest do
  @moduledoc """
  Focused tests for the sandbox/parent ancestor `(repo, branch)` guard surfaced
  by the GitHub sync component on the project settings page.
  """

  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Lightning.GithubHelpers
  import Mox

  setup :stub_usage_limiter_ok
  setup :verify_on_exit!

  @ancestor_branch_error "this branch is already linked to a parent project; sandboxes must use a different branch"

  describe "ancestor branch guard on the new connection form" do
    test "surfaces an inline error and disables the Save button when sandbox claims an ancestor's (repo, branch)",
         %{conn: conn} do
      installation = %{
        "id" => "1234",
        "account" => %{"type" => "User", "login" => "username"}
      }

      repo = %{"full_name" => "openfn/example", "default_branch" => "main"}
      branch = %{"name" => "main"}

      parent = insert(:project)

      insert(:project_repo_connection,
        project: parent,
        repo: repo["full_name"],
        branch: branch["name"]
      )

      sandbox = insert(:project, parent: parent)

      {conn, user} = setup_project_user(conn, sandbox, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(200, %{"installations" => [installation]})
      expect_create_installation_token(installation["id"])
      expect_get_installation_repos(200, %{"repositories" => [repo]})

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{sandbox.id}/settings#vcs")

      render_async(view)

      # select the installation
      view
      |> form("#project-repo-connection-form")
      |> render_change(connection: %{github_installation_id: installation["id"]})

      render_async(view)

      # select the repo (triggers branch fetch)
      expect_create_installation_token(installation["id"])
      expect_get_repo_branches(repo["full_name"], 200, [branch])

      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{
          github_installation_id: installation["id"],
          repo: repo["full_name"]
        }
      )

      render_async(view)

      # select the branch — this triggers the ancestor guard
      html =
        view
        |> form("#project-repo-connection-form")
        |> render_change(
          connection: %{
            github_installation_id: installation["id"],
            repo: repo["full_name"],
            branch: branch["name"]
          }
        )

      # error renders inline (template at github_sync_component.html.heex:120-145)
      assert html =~ @ancestor_branch_error

      # save button is disabled while the conflict is present
      assert has_element?(view, "#connect-and-sync-button[disabled]")
    end

    test "re-enables the Save button when the user picks a different branch",
         %{conn: conn} do
      installation = %{
        "id" => "1234",
        "account" => %{"type" => "User", "login" => "username"}
      }

      repo = %{"full_name" => "openfn/example", "default_branch" => "main"}
      conflicting_branch = %{"name" => "main"}
      safe_branch = %{"name" => "dev"}

      parent = insert(:project)

      insert(:project_repo_connection,
        project: parent,
        repo: repo["full_name"],
        branch: conflicting_branch["name"]
      )

      sandbox = insert(:project, parent: parent)

      {conn, user} = setup_project_user(conn, sandbox, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(200, %{"installations" => [installation]})
      expect_create_installation_token(installation["id"])
      expect_get_installation_repos(200, %{"repositories" => [repo]})

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{sandbox.id}/settings#vcs")

      render_async(view)

      view
      |> form("#project-repo-connection-form")
      |> render_change(connection: %{github_installation_id: installation["id"]})

      render_async(view)

      expect_create_installation_token(installation["id"])

      expect_get_repo_branches(repo["full_name"], 200, [
        conflicting_branch,
        safe_branch
      ])

      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{
          github_installation_id: installation["id"],
          repo: repo["full_name"]
        }
      )

      render_async(view)

      # pick the conflicting branch — error appears
      html_conflict =
        view
        |> form("#project-repo-connection-form")
        |> render_change(
          connection: %{
            github_installation_id: installation["id"],
            repo: repo["full_name"],
            branch: conflicting_branch["name"]
          }
        )

      assert html_conflict =~ @ancestor_branch_error
      assert has_element?(view, "#connect-and-sync-button[disabled]")

      # switch to a safe branch — conflict error clears (other validations
      # like the unchecked `accept` may still keep the button disabled).
      html_ok =
        view
        |> form("#project-repo-connection-form")
        |> render_change(
          connection: %{
            github_installation_id: installation["id"],
            repo: repo["full_name"],
            branch: safe_branch["name"]
          }
        )

      refute html_ok =~ @ancestor_branch_error
    end

    test "non-sandbox project (no parent) is unaffected by the guard",
         %{conn: conn} do
      installation = %{
        "id" => "1234",
        "account" => %{"type" => "User", "login" => "username"}
      }

      repo = %{"full_name" => "openfn/example", "default_branch" => "main"}
      branch = %{"name" => "main"}

      # An unrelated project happens to use the same (repo, branch). Since the
      # project we're configuring has no parent, the guard must not fire.
      other_project = insert(:project)

      insert(:project_repo_connection,
        project: other_project,
        repo: repo["full_name"],
        branch: branch["name"]
      )

      project = insert(:project)
      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(200, %{"installations" => [installation]})
      expect_create_installation_token(installation["id"])
      expect_get_installation_repos(200, %{"repositories" => [repo]})

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/settings#vcs")

      render_async(view)

      view
      |> form("#project-repo-connection-form")
      |> render_change(connection: %{github_installation_id: installation["id"]})

      render_async(view)

      expect_create_installation_token(installation["id"])
      expect_get_repo_branches(repo["full_name"], 200, [branch])

      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{
          github_installation_id: installation["id"],
          repo: repo["full_name"]
        }
      )

      render_async(view)

      html =
        view
        |> form("#project-repo-connection-form")
        |> render_change(
          connection: %{
            github_installation_id: installation["id"],
            repo: repo["full_name"],
            branch: branch["name"]
          }
        )

      refute html =~ @ancestor_branch_error
    end
  end
end
