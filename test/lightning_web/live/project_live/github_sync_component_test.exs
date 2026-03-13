defmodule LightningWeb.ProjectLive.GithubSyncComponentTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  alias Lightning.VersionControl.GithubError
  alias Lightning.VersionControl.ProjectRepoConnection
  alias LightningWeb.ProjectLive.GithubSyncComponent
  alias Phoenix.LiveView.AsyncResult

  describe "error state rendering for installations async_result" do
    setup do
      user = insert(:user)
      project = insert(:project)
      project_repo_connection = build(:project_repo_connection, project: project)

      # Prepare base assigns that match what the component sets up
      changeset =
        ProjectRepoConnection.configure_changeset(project_repo_connection, %{})

      repos = AsyncResult.ok(%AsyncResult{}, %{})
      branches = AsyncResult.ok(%AsyncResult{}, %{branches: %{}})

      %{
        user: user,
        project: project,
        project_repo_connection: project_repo_connection,
        changeset: changeset,
        repos: repos,
        branches: branches
      }
    end

    test "displays error banner for invalid OAuth token error", %{
      user: user,
      project: project,
      project_repo_connection: project_repo_connection,
      changeset: changeset,
      repos: repos,
      branches: branches
    } do
      error = GithubError.invalid_oauth_token("user refresh token has expired")
      installations = AsyncResult.failed(%AsyncResult{}, {:error, error})

      html =
        rendered_template(%{
          id: "github-sync-component",
          myself: %{},
          user: user,
          project: project,
          project_repo_connection: project_repo_connection,
          can_install_github: true,
          can_initiate_github_sync: true,
          action: :new,
          installations: installations,
          changeset: changeset,
          repos: repos,
          branches: branches,
          actions_disabled: false,
          actions_disabled_tooltip: nil
        })

      # Verify error banner is visible
      parsed = Floki.parse_document!(html)
      alert_banner = Floki.find(parsed, "[role='alert']")
      assert alert_banner != []

      # Verify ARIA attributes
      assert Floki.attribute(alert_banner, "aria-live") == ["polite"]

      # Verify error message content
      assert html =~ "Unable to load GitHub installations"
      assert html =~ "Your GitHub authentication has expired or is invalid"

      # Verify Settings link is present
      assert html =~ "Settings"
      assert html =~ ~s(href="/profile")
      assert html =~ "reconnect your GitHub account"
    end

    test "displays error banner for generic GitHub API error", %{
      user: user,
      project: project,
      project_repo_connection: project_repo_connection,
      changeset: changeset,
      repos: repos,
      branches: branches
    } do
      error = GithubError.api_error("API rate limit exceeded")
      installations = AsyncResult.failed(%AsyncResult{}, {:error, error})

      assigns = %{
        id: "github-sync-component",
        myself: %{},
        user: user,
        project: project,
        project_repo_connection: project_repo_connection,
        can_install_github: true,
        can_initiate_github_sync: true,
        action: :new,
        installations: installations,
        changeset: changeset,
        repos: repos,
        branches: branches,
        actions_disabled: false,
        actions_disabled_tooltip: nil
      }

      html = rendered_template(assigns)

      # Verify error banner and ARIA attributes
      parsed = Floki.parse_document!(html)
      alert_banner = Floki.find(parsed, "[role='alert']")
      assert alert_banner != []
      assert Floki.attribute(alert_banner, "aria-live") == ["polite"]

      # Verify error message content
      assert html =~ "Unable to load GitHub installations"
      assert html =~ "There was a problem connecting to GitHub"
      assert html =~ "Try the refresh button above, or contact support"
    end

    test "displays warning banner when user has no installations", %{
      user: user,
      project: project,
      project_repo_connection: project_repo_connection,
      changeset: changeset,
      repos: repos,
      branches: branches
    } do
      # Token is valid but user has no installations (app not installed or uninstalled)
      installations =
        AsyncResult.ok(%AsyncResult{}, %{installations: [], repos: %{}})

      assigns = %{
        id: "github-sync-component",
        myself: %{},
        user: user,
        project: project,
        project_repo_connection: project_repo_connection,
        can_install_github: true,
        can_initiate_github_sync: true,
        action: :new,
        installations: installations,
        changeset: changeset,
        repos: repos,
        branches: branches,
        actions_disabled: false,
        actions_disabled_tooltip: nil
      }

      html = rendered_template(assigns)

      # Verify warning banner is visible
      parsed = Floki.parse_document!(html)
      alert_banner = Floki.find(parsed, "[role='alert']")
      assert alert_banner != []

      # Verify ARIA attributes
      assert Floki.attribute(alert_banner, "aria-live") == ["polite"]

      # Verify warning message content
      assert html =~ "No GitHub installations found"
      assert html =~ "haven't installed the OpenFn GitHub App yet"
      assert html =~ "may have uninstalled it"

      # Verify GitHub installations link is present
      assert html =~ "Install or manage GitHub app installations"
      assert html =~ "https://github.com/apps/"
    end

    test "error and warning banners have correct styling", %{
      user: user,
      project: project,
      project_repo_connection: project_repo_connection,
      changeset: changeset,
      repos: repos,
      branches: branches
    } do
      # Test with a token error
      error = GithubError.invalid_oauth_token("token expired")
      installations = AsyncResult.failed(%AsyncResult{}, {:error, error})

      assigns = %{
        id: "github-sync-component",
        myself: %{},
        user: user,
        project: project,
        project_repo_connection: project_repo_connection,
        can_install_github: true,
        can_initiate_github_sync: true,
        action: :new,
        installations: installations,
        changeset: changeset,
        repos: repos,
        branches: branches,
        actions_disabled: false,
        actions_disabled_tooltip: nil
      }

      html = rendered_template(assigns)
      parsed = Floki.parse_document!(html)

      # Verify yellow background styling
      error_container = Floki.find(parsed, ".bg-yellow-50")
      assert error_container != []

      # Verify exclamation triangle icon is present
      icon = Floki.find(parsed, "svg.h-5.w-5.text-yellow-400")
      assert icon != []
    end
  end

  # Helper function to render the template with assigns
  defp rendered_template(assigns) do
    assigns = Map.new(assigns)

    GithubSyncComponent.render(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
