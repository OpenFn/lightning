defmodule LightningWeb.ProjectLive.GithubSyncComponent do
  @moduledoc false

  use LightningWeb, :live_component
  alias Lightning.VersionControl
  alias Lightning.VersionControl.ProjectRepoConnection

  @impl true
  def update(
        %{
          user: user,
          project: _,
          project_repo_connection: repo_connection,
          can_install_github: _,
          can_initiate_github_sync: _,
          edit_mode: _
        } = assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(changeset: ProjectRepoConnection.changeset(repo_connection, %{}))
     |> assign_async([:installations, :repos], fn ->
       fetch_user_installations_and_repos(user)
     end)
     |> assign_async(:branches, fn -> {:ok, %{branches: []}} end)}
  end

  defp fetch_user_installations_and_repos(user) do
    with {:ok, %{"installations" => installations}} <-
           VersionControl.fetch_user_installations(user) do
      installations =
        Enum.map(installations, fn %{"account" => account, "id" => id} ->
          {"#{account["type"]}: #{account["login"]}", id}
        end)

      repos_stream =
        Task.async_stream(installations, fn {_account, id} ->
          {id, fetch_repos(id)}
        end)

      {:ok, %{installations: installations, repos: Enum.into(repos_stream, %{})}}
    end
  end

  defp fetch_repos(installation_id) do
    case VersionControl.fetch_installation_repos(installation_id) do
      {:ok, body} ->
        Enum.map(body["repositories"], fn g_repo -> g_repo["full_name"] end)

      _other ->
        []
    end
  end

  defp fetch_branches(installation_id, repo_name) do
    case VersionControl.fetch_repo_branches(installation_id, repo_name) do
      {:ok, body} ->
        Enum.map(body, fn branch -> branch["name"] end)

      _other ->
        []
    end
  end

  defp github_config do
    Application.get_env(:lightning, :github_app, [])
  end

  defp fetch_async_list(assign) do
    (assign.ok? && assign.result) || []
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%= if @edit_mode do %>
        <.form :let={f} for={@changeset}>
          <.input
            type="select"
            field={f[:github_installation_id]}
            label="Github Installation"
            prompt="Select an installation"
            options={fetch_async_list(@installations)}
          />
          <div>
            Can’t find the right installation or repository?
            <.link
              target="_blank"
              class="text-indigo-600 hover:underline"
              href={"https://github.com/apps/#{github_config()[:app_name]}"}
            >
              Create/update GitHub installations
            </.link>
          </div>

          <.input
            type="select"
            field={f[:repo]}
            label="Repository"
            prompt="Select a repository"
            options={
              (@repos.ok? && @repos.result[f[:github_installation_id].value]) || []
            }
          />

          <.input
            type="select"
            field={f[:branch]}
            label="Branch"
            prompt="Select a branch"
            options={fetch_async_list(@branches)}
          />
        </.form>
      <% else %>
        <div>
          <div class="flex flex-col gap-2 font-medium text-xs text-black">
            <small class="">
              <span>
                Repository:
                <.link
                  href={"https://www.github.com/" <> @project_repo_connection.repo}
                  target="_blank"
                  class="hover:underline text-primary-600"
                >
                  <%= @project_repo_connection.repo %>
                </.link>
              </span>
            </small>

            <small class="">
              <span>
                Branch:
                <span class="text-xs font-mono bg-gray-200 rounded-md p-1">
                  <%= @project_repo_connection.branch %>
                </span>
              </span>
            </small>

            <small class="">
              <span>
                GitHub Installation ID:
                <span class="text-xs font-mono bg-gray-200 rounded-md p-1">
                  <%= @project_repo_connection.github_installation_id %>
                </span>
              </span>
            </small>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
