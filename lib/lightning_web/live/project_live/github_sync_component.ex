defmodule LightningWeb.ProjectLive.GithubSyncComponent do
  @moduledoc false

  use LightningWeb, :live_component
  alias Lightning.VersionControl
  alias Lightning.VersionControl.ProjectRepoConnection
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS

  @impl true
  def update(
        %{
          user: _,
          project: _,
          project_repo_connection: _,
          can_install_github: _,
          can_initiate_github_sync: _,
          action: action
        } = assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(assigns)
     |> apply_action(action, assigns)}
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

  def handle_event("reconnect", _params, socket) do
    if socket.assigns.can_install_github do
      {:noreply, reconnect_github(socket)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action")}
    end
  end

  def handle_event("initiate-sync", _params, socket) do
    if socket.assigns.can_initiate_github_sync do
      {:noreply, initiate_github_sync(socket)}
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

  defp apply_action(socket, :new, %{
         project_repo_connection: repo_connection,
         user: user
       }) do
    socket
    |> assign(changeset: ProjectRepoConnection.changeset(repo_connection, %{}))
    |> assign_async([:installations, :repos], fn ->
      # repos are grouped using the installation_id
      fetch_user_installations_and_repos(user)
    end)
    # branches are grouped using the repo
    |> assign_async(:branches, fn -> {:ok, %{branches: %{}}} end)
  end

  defp apply_action(socket, :show, %{
         project_repo_connection: repo_connection,
         user: user
       }) do
    socket
    |> assign_async([:installations, :repos], fn ->
      # repos are grouped using the installation_id
      fetch_user_installations_and_repos(user)
    end)
    |> assign_async(:verify_connection, fn ->
      verify_connection(repo_connection)
    end)
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

  defp reconnect_github(%{assigns: assigns} = socket) do
    repo_connection = assigns.project_repo_connection

    case VersionControl.reconfigure_github_connection(
           repo_connection,
           assigns.user
         ) do
      :ok ->
        socket
        |> put_flash(:info, "Connection made successfully!")
        |> push_navigate(
          to: ~p"/projects/#{socket.assigns.project}/settings#vcs"
        )

      {:error, _} ->
        put_flash(
          socket,
          :error,
          "Oops! Looks like you don't have access to this installation in Github"
        )
    end
  end

  defp initiate_github_sync(%{assigns: assigns} = socket) do
    repo_connection = assigns.project_repo_connection

    case VersionControl.inititiate_sync(repo_connection, assigns.user.email) do
      :ok ->
        socket
        |> put_flash(:info, "Github sync initiated successfully!")
        |> push_navigate(
          to: ~p"/projects/#{socket.assigns.project}/settings#vcs"
        )

      {:error, _} ->
        put_flash(
          socket,
          :error,
          "Oops! An error occured while connecting to Github. Please try again later"
        )
    end
  end

  defp can_access_github_installation?(repo_connection, async_installations) do
    async_installations.ok? and
      Enum.any?(async_installations.result, fn {_name, id} ->
        id == repo_connection.github_installation_id
      end)
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

  defp verify_connection(repo_connection) do
    case VersionControl.verify_github_connection(repo_connection) do
      :ok -> {:ok, %{verify_connection: :ok}}
      error -> error
    end
  end

  defp github_config do
    Application.get_env(:lightning, :github_app, [])
  end

  attr :id, :string, required: true
  attr :verify_connection, AsyncResult, required: true
  attr :myself, :any, required: true
  attr :can_reconnect, :boolean, required: true

  defp verify_connection_banner(assigns) do
    ~H"""
    <div class="mb-2">
      <.async_result assign={@verify_connection}>
        <:loading>
          <div class="rounded-md bg-blue-50 p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <svg
                  class="animate-spin h-5 w-5 text-blue-400"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle
                    class="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    stroke-width="4"
                  >
                  </circle>
                  <path
                    class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  >
                  </path>
                </svg>
              </div>
              <div class="ml-3">
                <p class="text-sm text-blue-700">
                  Verifying connection...
                </p>
              </div>
            </div>
          </div>
        </:loading>
        <:failed :let={_failure}>
          <div class="border-l-4 border-yellow-400 bg-yellow-50 p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <Heroicons.exclamation_triangle class="h-5 w-5 text-yellow-400" />
              </div>
              <div class="ml-3">
                <p class="text-sm text-yellow-700">
                  Your github project is not properly connected with Lightning.
                  <%= if @can_reconnect do %>
                    <a
                      id="reconnect-project-button"
                      href="#"
                      class="font-medium text-yellow-700 underline hover:text-yellow-600"
                      phx-click="reconnect"
                      phx-target={@myself}
                      phx-disable-with="Connecting..."
                    >
                      Click here to reconnect
                    </a>
                  <% else %>
                    Reach out to the admin who made this installation to reconnect
                  <% end %>
                </p>
              </div>
            </div>
          </div>
        </:failed>
        <div class="rounded-md bg-green-50 p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <Heroicons.check_circle class="h-5 w-5 text-green-400" />
            </div>
            <div class="ml-3">
              <p class="text-sm font-medium text-green-800">
                Your project is all setup
              </p>
            </div>
            <div class="ml-auto pl-3">
              <div class="-mx-1.5 -my-1.5">
                <button
                  type="button"
                  class="inline-flex rounded-md bg-green-50 p-1.5 text-green-500 hover:bg-green-100 focus:outline-none focus:ring-2 focus:ring-green-600 focus:ring-offset-2 focus:ring-offset-green-50"
                >
                  <span class="sr-only">Dismiss</span>
                  <Heroicons.x_mark
                    class="h-5 w-5"
                    phx-click={JS.toggle(to: "##{@id}")}
                  />
                </button>
              </div>
            </div>
          </div>
        </div>
      </.async_result>
    </div>
    """
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
