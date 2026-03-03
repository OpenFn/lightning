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
       |> put_flash(:error, "You are not authorized to perform this action")
       |> push_navigate(to: ~p"/projects/#{socket.assigns.project}/settings#vcs")}
    end
  end

  def handle_event("delete-connection", _params, socket) do
    if socket.assigns.can_install_github do
      {:ok, _} =
        VersionControl.remove_github_connection(
          socket.assigns.project_repo_connection,
          socket.assigns.user
        )

      {:noreply,
       socket
       |> put_flash(:info, "Connection removed successfully")
       |> push_navigate(to: ~p"/projects/#{socket.assigns.project}/settings#vcs")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action")
       |> push_navigate(to: ~p"/projects/#{socket.assigns.project}/settings#vcs")}
    end
  end

  def handle_event("reconnect", %{"connection" => params}, socket) do
    if socket.assigns.can_install_github do
      {:noreply, reconnect_github(socket, params)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action")
       |> push_navigate(to: ~p"/projects/#{socket.assigns.project}/settings#vcs")}
    end
  end

  def handle_event("initiate-sync", _params, socket) do
    if socket.assigns.can_initiate_github_sync do
      {:noreply, initiate_github_sync(socket)}
    else
      project = socket.assigns.project

      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action")
       |> push_navigate(to: ~p"/projects/#{project}/settings#vcs")}
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
     |> assign_async(:branches, fn -> {:ok, %{branches: %{}}} end, reset: true)
     |> maybe_fetch_branches()}
  end

  defp apply_action(socket, :new, %{
         project_repo_connection: repo_connection,
         user: user
       }) do
    socket
    |> assign(
      changeset: ProjectRepoConnection.configure_changeset(repo_connection, %{})
    )
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
    |> assign(
      changeset: ProjectRepoConnection.configure_changeset(repo_connection, %{})
    )
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
    |> ProjectRepoConnection.configure_changeset(params)
    |> then(fn changeset ->
      installation =
        Ecto.Changeset.get_field(changeset, :github_installation_id)

      if is_nil(installation) do
        changeset
        |> Ecto.Changeset.put_change(:repo, nil)
        |> Ecto.Changeset.put_change(:branch, nil)
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

      {:error, error} ->
        socket
        |> put_flash(:error, error_message(error))
        |> push_navigate(
          to: ~p"/projects/#{socket.assigns.project}/settings#vcs"
        )
    end
  end

  defp error_message(error) do
    case error do
      %{text: error_msg} ->
        error_msg

      %Lightning.VersionControl.GithubError{message: message} ->
        "GitHub Error: #{message}"

      %{"message" => message} ->
        "GitHub Error: #{message}"

      %{"error_description" => message} ->
        "GitHub Error: #{message}"

      %Tesla.Env{body: body} ->
        error_message(body)

      _error ->
        "Oops! An error occured while connecting to GitHub. Please try again later"
    end
  end

  defp reconnect_github(%{assigns: assigns} = socket, params) do
    repo_connection = assigns.project_repo_connection

    case VersionControl.reconfigure_github_connection(
           repo_connection,
           params,
           assigns.user
         ) do
      :ok ->
        socket
        |> put_flash(:info, "Connected to GitHub")
        |> push_navigate(
          to: ~p"/projects/#{socket.assigns.project}/settings#vcs"
        )

      {:error, %{text: error_msg}} ->
        socket
        |> put_flash(:error, error_msg)
        |> push_navigate(
          to: ~p"/projects/#{socket.assigns.project}/settings#vcs"
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, changeset: changeset)

      {:error, _} ->
        socket
        |> put_flash(
          :error,
          "Oops! Looks like you don't have access to this installation in GitHub"
        )
        |> push_navigate(
          to: ~p"/projects/#{socket.assigns.project}/settings#vcs"
        )
    end
  end

  defp initiate_github_sync(%{assigns: assigns} = socket) do
    repo_connection = assigns.project_repo_connection
    commit_message = "user #{assigns.user.email} initiated a sync from Lightning"

    case VersionControl.initiate_sync(repo_connection, commit_message) do
      :ok ->
        socket
        |> put_flash(:info, "GitHub sync initiated")
        |> push_navigate(
          to: ~p"/projects/#{socket.assigns.project}/settings#vcs"
        )

      {:error, error} ->
        socket
        |> put_flash(:error, error_message(error))
        |> push_navigate(
          to: ~p"/projects/#{socket.assigns.project}/settings#vcs"
        )
    end
  end

  defp can_access_github_installation?(repo_connection, async_installations) do
    async_installations.ok? and
      Enum.any?(async_installations.result, fn installation ->
        installation["id"] == repo_connection.github_installation_id
      end)
  end

  defp maybe_fetch_branches(
         %{assigns: %{changeset: changeset, branches: branches}} = socket
       ) do
    installation = Ecto.Changeset.get_field(changeset, :github_installation_id)
    repo = Ecto.Changeset.get_field(changeset, :repo)
    branches = (branches.ok? && branches.result) || %{}

    cond do
      installation && repo && is_nil(branches[repo]) ->
        # replaces the existing assign. I wish there was a clean way
        # to merge the result instead
        assign_async(
          socket,
          :branches,
          fn ->
            branches = fetch_branches(installation, repo)
            {:ok, %{branches: %{repo => branches}}}
          end,
          reset: true
        )

      is_nil(installation) or is_nil(repo) ->
        assign_async(socket, :branches, fn -> {:ok, %{branches: %{}}} end,
          reset: true
        )

      true ->
        socket
    end
  end

  defp fetch_user_installations_and_repos(user) do
    with {:ok, %{"installations" => installations}} <-
           VersionControl.fetch_user_installations(user) do
      installations =
        Enum.map(installations, fn %{"account" => account, "id" => id} ->
          %{
            "account" => "#{account["type"]}: #{account["login"]}",
            "id" => to_string(id)
          }
        end)

      repos =
        installations
        |> Task.async_stream(fn installation ->
          {installation["id"], fetch_repos(installation["id"])}
        end)
        |> Stream.filter(&match?({:ok, _}, &1))
        |> Map.new(fn {:ok, val} -> val end)

      {:ok, %{installations: installations, repos: repos}}
    end
  end

  defp fetch_repos(installation_id) do
    case VersionControl.fetch_installation_repos(installation_id) do
      {:ok, body} ->
        body["repositories"]
        |> Enum.map(fn g_repo ->
          Map.take(g_repo, ["full_name", "default_branch"])
        end)
        |> Enum.sort_by(fn g_repo -> String.downcase(g_repo["full_name"]) end)

      _other ->
        []
    end
  end

  defp fetch_branches(installation_id, repo_name) do
    case VersionControl.fetch_repo_branches(installation_id, repo_name) do
      {:ok, body} ->
        body
        |> Enum.map(fn branch -> Map.take(branch, ["name"]) end)
        |> Enum.sort_by(fn branch -> String.downcase(branch["name"]) end)

      _other ->
        []
    end
  end

  defp installations_select_options(async_installations) do
    installations = (async_installations.ok? && async_installations.result) || []

    Enum.map(installations, fn installation ->
      {installation["account"], installation["id"]}
    end)
  end

  defp repos_select_options(async_repos, installation_id) do
    repos =
      (async_repos.ok? && async_repos.result[installation_id]) ||
        []

    Enum.map(repos, fn repo -> repo["full_name"] end)
  end

  defp branches_select_options(async_branches, repo_name) do
    branches = (async_branches.ok? && async_branches.result[repo_name]) || []
    Enum.map(branches, fn branch -> branch["name"] end)
  end

  defp get_default_branch(async_repos, selected_repo) do
    if async_repos.ok? do
      async_repos.result
      |> Map.values()
      |> List.flatten()
      |> Enum.find(fn repo -> repo["full_name"] == selected_repo end)
      |> case do
        %{"default_branch" => branch} ->
          branch

        nil ->
          nil
      end
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
  attr :repos, AsyncResult, required: true
  attr :myself, :any, required: true
  attr :can_reconnect, :boolean, required: true
  attr :changeset, Ecto.Changeset, required: true
  attr :project, :map, required: true

  defp verify_connection_banner(assigns) do
    ~H"""
    <div id={@id} class="mb-2">
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
        <:failed :let={failure}>
          <div class="bg-yellow-50 p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <Heroicons.exclamation_triangle class="h-5 w-5 text-yellow-400" />
              </div>
              <div class="ml-3">
                <h3 class="text-sm font-medium text-yellow-800">
                  Your GitHub project is not properly connected with Lightning.
                </h3>
                <div class="mt-2 text-sm text-yellow-700">
                  <%= case failure do %>
                    <% {:error, %Lightning.VersionControl.GithubError{message: message}} -> %>
                      <p>There was a problem connecting to GitHub</p>
                      <p><code>GitHub Error: {message}</code></p>
                    <% {:error, %{"message" => message}} -> %>
                      <p>There was a problem connecting to GitHub</p>
                      <p><code>GitHub Error: {message}</code></p>
                    <% _other -> %>
                      <p>There was a problem connecting to GitHub</p>
                  <% end %>
                </div>
                <div class="mt-4">
                  <div class="-mx-2 -my-1.5 flex">
                    <%= if @can_reconnect do %>
                      <.button
                        theme="warning"
                        phx-click={show_modal("reconnect_modal")}
                      >
                        Click here to reconnect
                      </.button>
                      <.reconnect_modal
                        id="reconnect_modal"
                        changeset={@changeset}
                        myself={@myself}
                        project={@project}
                        repos={@repos}
                      />
                    <% end %>
                  </div>
                </div>
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
                Your repository is properly configured.
              </p>
            </div>
            <div class="ml-auto pl-3">
              <div class="-mx-1.5 -my-1.5">
                <.button
                  phx-click={JS.hide(to: "##{@id}")}
                  type="button"
                  theme="success"
                >
                  <span class="sr-only">Dismiss</span>
                  <.icon name="hero-x-mark" class="h-5 w-5" />
                </.button>
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
            <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <div class="px-6">
        <p class="text-sm text-gray-500">
          You are about to disconnect this project from GitHub.
          Until you reconnect, you will not be able to sync this project to GitHub.
        </p>
      </div>
      <.modal_footer>
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          theme="danger"
          phx-disable-with="Removing..."
          phx-click="delete-connection"
          phx-target={@myself}
        >
          Disconnect
        </.button>
        <.button type="button" phx-click={hide_modal(@id)} theme="secondary">
          Cancel
        </.button>
      </.modal_footer>
    </.modal>
    """
  end

  attr :id, :string, required: true
  attr :repos, AsyncResult, required: true
  attr :myself, :any, required: true
  attr :changeset, Ecto.Changeset, required: true
  attr :project, :map, required: true

  defp reconnect_modal(assigns) do
    ~H"""
    <.modal id={@id}>
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Reconnect to GitHub
          </span>
          <button
            phx-click={hide_modal(@id)}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <.form
        :let={f}
        id="reconnect-project-form"
        as={:connection}
        for={@changeset}
        phx-submit="reconnect"
        phx-target={@myself}
      >
        <div>
          <.sync_order_radio form={f} />
        </div>
        <div>
          <.accept_checkbox
            project={@project}
            form={f}
            default_branch={
              get_default_branch(
                @repos,
                f[:repo].value
              )
            }
          />
        </div>
        <.modal_footer>
          <.button
            id="reconnect-project-button"
            type="submit"
            theme="primary"
            phx-disable-with="Connecting..."
          >
            Reconnect
          </.button>
        </.modal_footer>
      </.form>
    </.modal>
    """
  end

  attr :form, :map, required: true

  defp sync_order_radio(assigns) do
    ~H"""
    <div class="mb-4">
      <.label>
        Initial Setup Action
      </.label>
      <p class="text-sm text-gray-500">
        Do you want to initialize this 2-way sync by committing your current
        OpenFn project to GitHub or do you want to overwrite your current OpenFn
        project, importing a previously created project from a GitHub repo?
      </p>
      <fieldset class="mt-4">
        <legend class="sr-only">Direction of <em>Initial</em> Sync</legend>
        <div class="space-y-5">
          <div class="relative flex items-start">
            <div class="flex h-6 items-center">
              <.input
                type="radio"
                field={@form[:sync_direction]}
                id="pull_first_sync_option"
                aria-describedby="pull_first_sync_option_description"
                value="pull"
                checked={@form[:sync_direction].value != :deploy}
              />
            </div>
            <div class="ml-3 text-sm leading-6">
              <label for="pull_first_sync_option" class="text-gray-900">
                <span class="font-medium">OpenFn --> GitHub:</span>
                Export to GitHub (default, non-destructive)
              </label>

              <p id="pull_first_sync_option_description" class="text-gray-500">
                This option will commit a copy of your current OpenFn project to a GitHub repo.
              </p>
            </div>
          </div>
          <div class="relative flex items-start">
            <div class="flex h-6 items-center">
              <.input
                type="radio"
                field={@form[:sync_direction]}
                id="deploy_first_sync_option"
                aria-describedby="deploy_first_sync_option_description"
                value="deploy"
                checked={@form[:sync_direction].value == :deploy}
              />
            </div>
            <div class="ml-3 text-sm leading-6">
              <label for="deploy_first_sync_option" class="text-gray-900">
                <span class="font-medium">GitHub --> OpenFn:</span>
                Import from GitHub (overwrite this project)
              </label>
              <p id="deploy_first_sync_option_description" class="text-gray-500">
                If you already have <code>config.json</code>
                and <code>project.yaml</code>
                files tracked on GitHub and you want to <b>overwrite</b>
                this project on OpenFn, you can choose this advanced option.
              </p>
            </div>
          </div>
        </div>
      </fieldset>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :project, :map, required: true
  attr :default_branch, :string

  defp accept_checkbox(assigns) do
    ~H"""
    <div class={[
      "mt-4 bg-amber-200 flex gap-3 rounded-md p-3",
      @form[:sync_direction].value == :deploy && "bg-red-200"
    ]}>
      <.input
        type="checkbox"
        field={@form[:accept]}
        required="true"
        hidden_input={false}
      />
      <span>
        I understand that
        <%= if @form[:sync_direction].value == :deploy do %>
          my current OpenFn project <b>will be destroyed</b> and
        <% end %>
        the following files will be committed to <b><%= @form[
          :repo
        ].value %></b>:
        <ul class="my-2">
          <li>
            <.icon name="hero-document-plus" class="h-4 w-4" />
            <code>
              .github/workflows/openfn-pull.yml -> {@default_branch}
            </code>
          </li>
          <li>
            <.icon name="hero-document-plus" class="h-4 w-4" />
            <code>
              .github/workflows/openfn-{@project.id}-deploy.yml -> {@form[
                :branch
              ].value}
            </code>
          </li>
          <%= if to_string(@form[:config_path].value) == "" do %>
            <li>
              <.icon name="hero-document-plus" class="h-4 w-4" />
              <code>
                ./openfn-{@project.id}-config.json -> {@form[
                  :branch
                ].value}
              </code>
            </li>
          <% end %>
        </ul>
        Existing versions of these files on these branches will be overwritten. (I'll be able to find them in my git history if needed.)
      </span>
    </div>
    """
  end
end
