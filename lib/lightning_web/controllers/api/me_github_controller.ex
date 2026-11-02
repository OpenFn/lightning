defmodule LightningWeb.API.MeGithubController do
  @moduledoc """
  The signed-in person's GitHub connection, which GitHub sync uses to set up a
  project's repository. On a session token only; any other token is 403
  `forbidden`.

  `DELETE /api/me/github_connection` forgets the person's GitHub token and asks
  GitHub to revoke it, answering 204 even when GitHub can't be reached or
  there was no connection. Repository connections keep working, since each
  has its own token.

  `GET /api/me/github_repos` lists the repositories Lightning's GitHub App can
  reach through the person's GitHub account, across every installation they
  can see, by name and paged. An installation whose repositories can't be read
  lists none.

  `GET /api/me/github_repos/:owner/:name/branches` lists one repository's
  branches by name. A repository the person's installations can't reach is
  404 `not_found`.

  With no GitHub connection, or one whose refresh token has expired, both are
  403 `forbidden`: connect again. When GitHub can't be asked, they are 503
  `service_unavailable`.
  """
  use LightningWeb, :controller

  import LightningWeb.API.Helpers, only: [pagination_links: 3]

  alias Lightning.Scope
  alias Lightning.VersionControl
  alias Lightning.VersionControl.GithubError
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Problem
  alias LightningWeb.Plugs.AuthorizeAction

  require Logger

  action_fallback FallbackController

  @default_page_size 10
  @max_page_size 100

  plug AuthorizeAction,
       {:account, :disconnect_github}
       when action == :delete_connection

  plug AuthorizeAction,
       {:account, :list_github_repos}
       when action in [:repos, :branches]

  def delete_connection(conn, _params) do
    %Scope{actor: user} = conn.assigns.scope

    if is_nil(user.github_oauth_token) do
      send_resp(conn, 204, "")
    else
      with {:ok, _user} <- VersionControl.delete_github_oauth_grant(user) do
        send_resp(conn, 204, "")
      end
    end
  end

  def repos(conn, params) do
    %Scope{actor: user} = conn.assigns.scope

    with {:ok, repos} <- user_repos(user) do
      page = page(repos, Filters.page(params))

      json(conn, %{
        data: page.entries,
        links: pagination_links(conn, page, %{})
      })
    end
  end

  def branches(conn, %{"owner" => owner, "name" => name}) do
    %Scope{actor: user} = conn.assigns.scope
    full_name = String.downcase("#{owner}/#{name}")

    with {:ok, repos} <- user_repos(user),
         {:ok, repo} <- find_repo(repos, full_name),
         {:ok, branches} <-
           VersionControl.fetch_repo_branches(
             user,
             repo.installation_id,
             repo.full_name
           )
           |> github_answer() do
      json(conn, %{
        data:
          branches
          |> Enum.map(&%{name: &1["name"]})
          |> Enum.sort_by(&String.downcase(&1.name))
      })
    end
  end

  # Only ids from the person's own installations are passed on, since the
  # app's credential could read any installation's repositories.
  defp user_repos(user) do
    with {:ok, %{"installations" => installations}} <-
           user |> VersionControl.fetch_user_installations() |> github_answer() do
      repos =
        installations
        |> Task.async_stream(&installation_repos(to_string(&1["id"])),
          timeout: 30_000,
          on_timeout: :kill_task
        )
        |> Enum.flat_map(fn
          {:ok, repos} -> repos
          {:exit, _reason} -> []
        end)
        |> Enum.sort_by(&String.downcase(&1.full_name))

      {:ok, repos}
    end
  end

  defp installation_repos(installation_id) do
    case VersionControl.fetch_installation_repos(installation_id) do
      {:ok, %{"repositories" => repositories}} ->
        for repo <- repositories do
          %{
            full_name: repo["full_name"],
            default_branch: repo["default_branch"],
            installation_id: installation_id
          }
        end

      _failed ->
        []
    end
  end

  defp find_repo(repos, full_name) do
    case Enum.find(repos, &(String.downcase(&1.full_name) == full_name)) do
      nil -> {:error, :not_found}
      repo -> {:ok, repo}
    end
  end

  defp github_answer({:ok, _body} = ok), do: ok

  defp github_answer({:error, %GithubError{code: :invalid_oauth_token}}),
    do: {:error, :forbidden}

  defp github_answer({:error, :unauthorized_installation}),
    do: {:error, :not_found}

  defp github_answer({:error, reason}) do
    Logger.warning(
      "Could not ask GitHub for a person's repositories: " <>
        inspect(reason)
    )

    {:error, Problem.new(:service_unavailable)}
  end

  defp page(entries, params) do
    size =
      params
      |> Keyword.get(:page_size, @default_page_size)
      |> min(@max_page_size)

    number = Keyword.get(params, :page, 1)
    total = length(entries)

    %Scrivener.Page{
      entries: entries |> Enum.drop((number - 1) * size) |> Enum.take(size),
      page_number: number,
      page_size: size,
      total_entries: total,
      total_pages: max(ceil(total / size), 1)
    }
  end
end
