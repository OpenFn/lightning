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
          action: _
        } = assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(changeset: ProjectRepoConnection.changeset(repo_connection, %{}))
     |> assign_async([:installations, :repos], fn ->
       # repos are grouped using the installation_id
       fetch_user_installations_and_repos(user)
     end)
     # branches are grouped using the repo
     |> assign_async(:branches, fn -> {:ok, %{branches: %{}}} end)
     |> assign_async(:verify_connection, fn ->
       verify_connection(repo_connection)
     end)}
  end

  @impl true
  def handle_event("validate", %{"connection" => params}, socket) do
    changeset = validate_changes(socket.assigns.project_repo_connection, params)

    {:noreply,
     socket
     |> assign(changeset: changeset)
     |> maybe_fetch_branches()}
  end

  def handle_event("save", %{"connection" => params}, socket) do
    if socket.assigns.can_install_github do
      {:noreply, create_connection(socket, params)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action")}
    end
  end

  def handle_event("delete-connection", _params, socket) do
    if socket.assigns.can_install_github do
      project = socket.assigns.project

      {:ok, _} =
        VersionControl.remove_github_connection(
          socket.assigns.project_repo_connection,
          socket.assigns.user
        )

      {:noreply,
       socket
       |> put_flash(:info, "Connection removed successfully")
       |> push_navigate(to: ~p"/projects/#{project}/settings#vcs")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action")}
    end
  end

  def handle_event("refresh-installations", _params, socket) do
    changeset = validate_changes(socket.assigns.project_repo_connection, %{})
    user = socket.assigns.user

    {:noreply,
     socket
     |> assign(changeset: changeset)
     |> assign_async([:installations, :repos], fn ->
       fetch_user_installations_and_repos(user)
     end)
     |> assign_async(:branches, fn -> {:ok, %{branches: %{}}} end)}
  end

  def handle_event("refresh-branches", _params, socket) do
    changeset = validate_changes(socket.assigns.changeset, %{branch: nil})

    {:noreply,
     socket
     |> assign(changeset: changeset)
     |> assign_async(:branches, fn -> {:ok, %{branches: %{}}} end)
     |> maybe_fetch_branches()}
  end

  defp validate_changes(repo_connection, params) do
    repo_connection
    |> ProjectRepoConnection.changeset(params)
    |> then(fn changeset ->
      installation =
        Ecto.Changeset.get_change(changeset, :github_installation_id)

      if is_nil(installation) do
        changeset |> Ecto.Changeset.change(%{repo: nil, branch: nil})
      else
        changeset
      end
    end)
    |> then(fn changeset ->
      repo = Ecto.Changeset.get_change(changeset, :repo)

      if is_nil(repo) do
        changeset |> Ecto.Changeset.change(%{branch: nil})
      else
        changeset
      end
    end)
  end

  defp create_connection(socket, params) do
    params = Map.merge(params, %{"project_id" => socket.assigns.project.id})

    case VersionControl.create_github_connection(params, socket.assigns.user) do
      {:ok, _connection} ->
        socket
        |> put_flash(:info, "Connection made successfully")
        |> push_navigate(
          to: ~p"/projects/#{socket.assigns.project}/settings#vcs"
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, changeset: changeset)

      {:error, _other} ->
        put_flash(socket, :error, "Oops! Could not connect to Github")
    end
  end

  defp maybe_fetch_branches(
         %{assigns: %{changeset: changeset, branches: branches}} = socket
       ) do
    installation = Ecto.Changeset.get_field(changeset, :github_installation_id)
    repo = Ecto.Changeset.get_field(changeset, :repo)
    branches = (branches.ok? && branches.result) || %{}

    if installation && repo && is_nil(branches[repo]) do
      # replaces the existing assign. I wish there was a clean way
      # to merge the result instead
      assign_async(socket, :branches, fn ->
        branches = fetch_branches(installation, repo)
        {:ok, %{branches: Map.new([{repo, branches}])}}
      end)
    else
      socket
    end
  end

  defp fetch_user_installations_and_repos(user) do
    with {:ok, %{"installations" => installations}} <-
           VersionControl.fetch_user_installations(user) do
      installations =
        Enum.map(installations, fn %{"account" => account, "id" => id} ->
          {"#{account["type"]}: #{account["login"]}", to_string(id)}
        end)

      repos =
        installations
        |> Task.async_stream(fn {_account, id} ->
          {to_string(id), fetch_repos(id)}
        end)
        |> Stream.filter(&match?({:ok, _}, &1))
        |> Map.new(fn {:ok, val} -> val end)

      {:ok, %{installations: installations, repos: repos}}
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

  defp verify_connection(%{__meta__: meta} = repo_connection)
       when meta.state == :loaded do
    case VersionControl.verify_github_connection(repo_connection) do
      :ok -> {:ok, %{verify_connection: :ok}}
      error -> error
    end
  end

  defp verify_connection(_), do: {:ok, %{verify_connection: :ok}}

  defp github_config do
    Application.get_env(:lightning, :github_app, [])
  end

  defp confirm_connection_removal_modal(assigns) do
    ~H"""
    <.modal id={@id} width="max-w-md">
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Remove Integration?
          </span>
          <button
            phx-click={hide_modal(@id)}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <div class="px-6">
        <p class="text-sm text-gray-500">
          You are about to disconnect this project from GitHub.
          Until you reconnect, you will not be able to sync this project to Github.
        </p>
      </div>
      <div class="flex flex-row-reverse gap-4 mx-6 mt-2">
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          color_class="bg-red-600 hover:bg-red-700 text-white"
          phx-disable-with="Removing..."
          phx-click="delete-connection"
          phx-target={@myself}
        >
          Disconnect
        </.button>
        <button
          type="button"
          phx-click={hide_modal(@id)}
          class="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
        >
          Cancel
        </button>
      </div>
    </.modal>
    """
  end
end
