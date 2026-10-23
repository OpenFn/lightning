defmodule LightningWeb.ProjectLive.GithubSyncComponent do
  @moduledoc false

  use LightningWeb, :live_component
  alias Lightning.VersionControl
  alias Lightning.VersionControl.ProjectRepoConnection
  alias LightningWeb.Components.Common
  alias LightningWeb.Components.GithubComponents
  alias Phoenix.LiveView.AsyncResult

  # While the first sync is setting up, re-check GitHub this often, for this long
  @poll_interval :timer.seconds(10)
  @poll_for :timer.minutes(5)

  @impl true
  def update(%{poll: gen}, socket) do
    %{poll_gen: current, poll_until: until} = socket.assigns

    if gen == current and DateTime.before?(DateTime.utc_now(), until) and
         polling?(socket.assigns) do
      {:ok, socket |> maybe_refresh_status() |> schedule_poll()}
    else
      {:ok, socket}
    end
  end

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
    params = Map.put(params, "project_id", socket.assigns.project.id)
    changeset = validate_changes(socket.assigns.project_repo_connection, params)

    {:noreply,
     socket
     |> assign(changeset: changeset)
     |> maybe_fetch_branches()
     |> maybe_check_workspace()}
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

  def handle_event("toggle-legacy-format", _params, socket) do
    changeset = socket.assigns.changeset
    current = Ecto.Changeset.get_field(changeset, :sync_version)

    # Form fields read from the changeset's params before its changes, so the
    # flip has to go through the params, like the "validate" event does.
    params =
      (changeset.params || %{})
      |> Map.put("project_id", socket.assigns.project.id)
      |> Map.put("sync_version", to_string(!current))

    {:noreply,
     assign(socket,
       changeset:
         validate_changes(socket.assigns.project_repo_connection, params)
     )}
  end

  def handle_event("toggle-advanced", _params, socket) do
    {:noreply, update(socket, :show_advanced, &(!&1))}
  end

  def handle_event("show-advanced", _params, socket) do
    {:noreply, assign(socket, show_advanced: true)}
  end

  def handle_event("refresh-status", _params, socket) do
    {:noreply,
     socket
     |> refresh_status()
     |> assign(
       poll_until: DateTime.add(DateTime.utc_now(), @poll_for, :millisecond)
     )
     |> schedule_poll()}
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
      # New connections default to the v2 YAML format.
      changeset:
        ProjectRepoConnection.configure_changeset(repo_connection, %{
          sync_version: true
        })
    )
    |> assign_async([:installations, :repos], fn ->
      # repos are grouped using the installation_id
      fetch_user_installations_and_repos(user)
    end)
    # branches are grouped using the repo
    |> assign_async(:branches, fn -> {:ok, %{branches: %{}}} end)
    |> assign(workspace_check: nil, workspace_key: nil, show_advanced: false)
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
    |> refresh_status()
    |> assign(
      poll_gen: 0,
      poll_until: DateTime.add(DateTime.utc_now(), @poll_for, :millisecond)
    )
    |> schedule_poll()
  end

  defp refresh_status(%{assigns: %{project_repo_connection: conn}} = socket) do
    socket
    |> assign_async(:verify_connection, fn -> verify_connection(conn) end)
    |> maybe_assign_sync_status(conn)
  end

  # A tick that lands while GitHub is still answering the last one waits
  defp maybe_refresh_status(socket) do
    if :loading in Keyword.values(status_checks(socket.assigns)),
      do: socket,
      else: refresh_status(socket)
  end

  defp schedule_poll(socket) do
    gen = socket.assigns.poll_gen + 1

    send_update_after(
      __MODULE__,
      [id: socket.assigns.id, poll: gen],
      @poll_interval
    )

    assign(socket, poll_gen: gen)
  end

  defp polling?(assigns) do
    checks = status_checks(assigns)

    overall(checks) in [:loading, :setting_up] or
      :running in Keyword.values(checks)
  end

  # Re-checked only when installation, repo, branch, format or workspace
  # change, as the user picks them
  defp maybe_check_workspace(socket) do
    %{changeset: changeset, user: user} = socket.assigns
    connection = Ecto.Changeset.apply_changes(changeset)

    %{github_installation_id: installation, repo: repo, branch: branch} =
      connection

    key =
      {installation, repo, branch, connection.sync_version,
       connection.workspace_path}

    cond do
      nil in [installation, repo, branch] ->
        assign(socket, workspace_check: nil, workspace_key: nil)

      key == socket.assigns.workspace_key ->
        socket

      true ->
        socket
        |> assign(workspace_key: key)
        |> assign_async(
          :workspace_check,
          fn ->
            with {:ok, check} <-
                   VersionControl.check_workspace(user, connection) do
              {:ok, %{workspace_check: check}}
            end
          end,
          reset: true
        )
    end
  end

  defp maybe_assign_sync_status(socket, %{sync_version: true} = repo_connection) do
    assign_async(socket, :sync_status, fn ->
      with {:ok, status} <- VersionControl.get_sync_status(repo_connection) do
        {:ok, %{sync_status: status}}
      end
    end)
  end

  defp maybe_assign_sync_status(socket, _legacy_connection),
    do: assign(socket, :sync_status, nil)

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
    |> maybe_force_branch_error_action()
  end

  # When the project-tree branch guard fails on a branch the user just
  # selected, set the changeset action so Phoenix renders the error inline.
  # We only promote the action when the conflict error is present so other
  # "blank" errors stay hidden until the user submits.
  defp maybe_force_branch_error_action(changeset) do
    branch_errors = Keyword.get_values(changeset.errors, :branch)

    if Enum.any?(branch_errors, fn {_msg, opts} ->
         Keyword.get(opts, :code) == :tree_branch_conflict
       end) do
      Map.put(changeset, :action, :validate)
    else
      changeset
    end
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

      # Only a decoded body is worth unwrapping. Tesla.Middleware.JSON leaves
      # the body a binary for an HTML or plain-text response, and recursing
      # into that lands on the clause below, putting a page of GitHub's HTML in
      # a flash.
      %Tesla.Env{body: %{} = body} ->
        error_message(body)

      # Usually this is our export pre-flight failing with a plain string that
      # names both colliding entities, which the generic message below would
      # lose. Not always, though. refresh_oauth_token/1 passes GitHub's body
      # straight through.
      message when is_binary(message) ->
        message

      _error ->
        "Oops! An error occurred while connecting to GitHub. Please try again later"
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

      # The export pre-flight in initiate_sync/2 fails with a plain string
      # naming both colliding entities. Without this it reaches the catch-all
      # below and the user is told they lack GitHub access, which is false.
      {:error, message} when is_binary(message) ->
        socket
        |> put_flash(:error, message)
        |> push_navigate(
          to: ~p"/projects/#{socket.assigns.project}/settings#vcs"
        )

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
         %{assigns: %{changeset: changeset, branches: branches, user: user}} =
           socket
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
            branches = fetch_branches(user, installation, repo)
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
        |> Task.async_stream(
          fn installation ->
            {installation["id"], fetch_repos(installation["id"])}
          end,
          timeout: 30_000,
          on_timeout: :kill_task
        )
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

  defp fetch_branches(user, installation_id, repo_name) do
    case VersionControl.fetch_repo_branches(user, installation_id, repo_name) do
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

  defp show_invalid_oauth_error?(installations) do
    !installations.ok? && installations.failed &&
      match?(
        {:error,
         %Lightning.VersionControl.GithubError{code: :invalid_oauth_token}},
        installations.failed
      )
  end

  defp show_no_installations_warning?(installations) do
    installations.ok? && installations.result == []
  end

  defp show_api_error?(installations) do
    !installations.ok? && installations.failed &&
      !match?(
        {:error,
         %Lightning.VersionControl.GithubError{code: :invalid_oauth_token}},
        installations.failed
      )
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp error_banner(assigns) do
    ~H"""
    <Common.alert
      id="github-error-banner"
      type="warning"
      header={@title}
      class="mb-4"
    >
      <:message>{render_slot(@inner_block)}</:message>
    </Common.alert>
    """
  end

  # One state per row of the status block: :loading, :ok, :running, :none,
  # {:setting_up, run | nil}, or a problem (see problem?/1)
  defp status_checks(%{project_repo_connection: conn} = assigns) do
    repo = repo_check(assigns.verify_connection, conn)

    if conn.sync_version do
      status = assigns.sync_status

      [
        repo: repo,
        tracking: tracking_check(status, conn),
        last_pull: run_check(status, :last_pull),
        last_deploy: run_check(status, :last_deploy)
      ]
    else
      [repo: repo]
    end
  end

  # GitHub's contents and secrets APIs can lag a just-pushed commit
  defp repo_check(%AsyncResult{failed: {:error, %{code: code}} = failed}, conn)
       when code in [:file_not_found, :repo_secret_not_found] do
    if recent?(conn, 120), do: {:setting_up, nil}, else: {:error, failed}
  end

  defp repo_check(%AsyncResult{failed: failed}, _conn) when not is_nil(failed),
    do: {:error, failed}

  defp repo_check(%AsyncResult{ok?: true}, _conn), do: :ok
  defp repo_check(_verify, _conn), do: :loading

  defp tracking_check(%AsyncResult{failed: failed}, _conn)
       when not is_nil(failed),
       do: :unavailable

  defp tracking_check(%AsyncResult{ok?: true, result: status} = result, conn) do
    # The alias is only known once the first pull files this project, as it
    # may have been given a (virtual) local alias. No alias, no clashes.
    clashes =
      alias_clashes(
        status.projects,
        conn.project_id,
        workspace_alias(result, conn.project_id)
      )

    case {status.tracking, clashes} do
      {{:other_project, uuid}, _clashes} ->
        {:other_project, uuid, find_project(status.projects, uuid)[:name]}

      {_tracking, [clash | _]} ->
        {:clash, clash.alias, clashes}

      {:ok, []} ->
        :ok

      _pending ->
        pending_check(first_run(status), conn)
    end
  end

  defp tracking_check(_status, _conn), do: :loading

  # This uuid's local copy in the workspace, or nil
  defp find_project(_projects, nil), do: nil
  defp find_project(projects, uuid), do: Enum.find(projects, &(&1.uuid == uuid))

  # The alias the CLI files this project under in the workspace: `requested`,
  # else the alias of its existing local copy, else `main`
  # (see `@openfn/cli` projects/fetch.ts)
  defp project_alias(projects, project_id, requested) do
    requested || find_project(projects, project_id)[:alias] || "main"
  end

  # The workspace's local project copies that share `alias` with this project
  # but not its uuid or host. The CLI refuses to pull with any of these around.
  defp alias_clashes(projects, project_id, alias) do
    # the host the CLI was given, so it matches the files it writes
    host = URI.parse(VersionControl.endpoint_url()).host

    Enum.filter(
      projects,
      &(&1.alias == alias and (&1.uuid != project_id or &1.host != host))
    )
  end

  # Nothing has committed this project's checkout yet
  defp pending_check(nil, conn),
    do: if(recent?(conn, 300), do: {:setting_up, nil}, else: :not_synced)

  defp pending_check(%{status: status} = run, _conn) when status != "completed",
    do: {:setting_up, run}

  defp pending_check(%{conclusion: "success"}, _conn), do: :not_synced
  defp pending_check(run, _conn), do: {:failed_run, run}

  # Which run commits the first checkout depends on the (unsaved) direction,
  # so take whichever ran last
  defp first_run(%{last_pull: pull, last_deploy: deploy}) do
    [pull, deploy]
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(& &1.created_at, DateTime, fn -> nil end)
  end

  defp run_check(%AsyncResult{ok?: true, result: status}, key) do
    case status[key] do
      nil ->
        :none

      %{status: status} when status != "completed" ->
        :running

      %{conclusion: "success"} ->
        :ok

      %{conclusion: conclusion} when conclusion in ["cancelled", "skipped"] ->
        :none

      _failed ->
        {:failed_run, status[key]}
    end
  end

  defp run_check(%AsyncResult{failed: failed}, _key) when not is_nil(failed),
    do: :none

  defp run_check(_status, _key), do: :loading

  defp recent?(conn, seconds),
    do: DateTime.diff(DateTime.utc_now(), conn.inserted_at) < seconds

  defp overall(checks) do
    checks = Keyword.values(checks)

    cond do
      Enum.any?(checks, &problem?/1) -> :attention
      :loading in checks -> :loading
      Enum.any?(checks, &match?({:setting_up, _run}, &1)) -> :setting_up
      true -> :healthy
    end
  end

  defp problem?(check) do
    check in [:unavailable, :not_synced] or
      (is_tuple(check) and elem(check, 0) != :setting_up)
  end

  defp overall_title(:attention), do: "Needs attention"
  defp overall_title(:loading), do: "Checking sync status..."
  defp overall_title(:setting_up), do: "Setting up"
  defp overall_title(:healthy), do: "Sync healthy"

  defp check_icon(check) do
    cond do
      check in [:ok, :healthy] ->
        {"hero-check-circle-solid", "text-green-500"}

      check == :none ->
        {"hero-minus-circle", "text-gray-400"}

      match?({tag, _} when tag in [:error, :failed_run], check) ->
        {"hero-x-circle-solid", "text-red-500"}

      check == :attention or problem?(check) ->
        {"hero-exclamation-triangle-solid", "text-yellow-500"}

      true ->
        {"hero-arrow-path", "animate-spin text-blue-500"}
    end
  end

  attr :check, :any, required: true

  defp check_icon_tag(assigns) do
    {name, class} = check_icon(assigns.check)
    assigns = assign(assigns, name: name, class: class)

    ~H"""
    <.icon name={@name} class={"h-5 w-5 shrink-0 #{@class}"} />
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :check, :any, required: true
  slot :summary
  slot :detail

  defp check_row(assigns) do
    ~H"""
    <li id={@id} class="px-4 py-3">
      <div class="flex items-center gap-3">
        <.check_icon_tag check={@check} />
        <span class="text-sm text-gray-900">{@label}</span>
        <span class="ml-auto flex shrink-0 items-center gap-2 whitespace-nowrap text-xs text-gray-500">
          {render_slot(@summary)}
        </span>
      </div>
      <div :if={@detail != []} class="mt-2 ml-8">
        {render_slot(@detail)}
      </div>
    </li>
    """
  end

  attr :verify_connection, AsyncResult, required: true
  attr :sync_status, :any, required: true
  attr :project_repo_connection, :map, required: true
  attr :can_reconnect, :boolean, required: true
  attr :changeset, Ecto.Changeset, required: true
  attr :repos, AsyncResult, required: true
  attr :project, :map, required: true
  attr :myself, :any, required: true

  defp sync_health(assigns) do
    checks = status_checks(assigns)

    assigns =
      assign(assigns,
        checks: checks,
        overall: overall(checks),
        loading:
          assigns.verify_connection.loading ||
            (assigns.sync_status && assigns.sync_status.loading)
      )

    ~H"""
    <div id="sync-health" class="mb-4 rounded-md border border-gray-200">
      <div class="flex items-center gap-3 border-b border-gray-200 px-4 py-3">
        <.check_icon_tag check={@overall} />
        <h3 id="sync-health-title" class="text-sm font-medium text-gray-900">
          {overall_title(@overall)}
        </h3>
        <.button
          id="refresh-sync-status-button"
          type="button"
          theme="secondary"
          class="ml-auto"
          disabled={!!@loading}
          phx-click="refresh-status"
          phx-target={@myself}
        >
          <.icon
            name="hero-arrow-path-mini"
            class={"h-4 w-4 #{if(@loading, do: "animate-spin")}"}
          />
          <span class="sr-only">Refresh sync status</span>
        </.button>
      </div>
      <div
        :if={outdated_workflows?(@sync_status)}
        class="border-b border-gray-200 px-4 py-3"
      >
        <Common.alert
          id="outdated-workflows"
          type="warning"
          header="This repository has the old OpenFn GitHub workflows"
          actions={reconnect_action(@can_reconnect, "outdated-workflows-reconnect")}
        >
          <:message>
            This project was connected with an earlier version of GitHub sync. Reconnect to update the workflow files and get full sync status.
          </:message>
        </Common.alert>
      </div>
      <ul class="divide-y divide-gray-100">
        <.repo_row check={@checks[:repo]} can_reconnect={@can_reconnect} />
        <%= if @project_repo_connection.sync_version do %>
          <.tracking_row check={@checks[:tracking]} can_reconnect={@can_reconnect} />
          <.run_row
            id="last-pull-run"
            label="Last sync: OpenFn --> GitHub"
            check={@checks[:last_pull]}
            sync_status={@sync_status}
            key={:last_pull}
          />
          <.run_row
            id="last-deploy-run"
            label="Last deploy: GitHub --> OpenFn"
            check={@checks[:last_deploy]}
            sync_status={@sync_status}
            key={:last_deploy}
          />
        <% end %>
      </ul>
      <.reconnect_modal
        :if={@can_reconnect}
        id="reconnect_modal"
        changeset={@changeset}
        myself={@myself}
        project={@project}
        repos={@repos}
      />
    </div>
    """
  end

  defp outdated_workflows?(sync_status),
    do:
      match?(
        %AsyncResult{ok?: true, result: %{workflows: :outdated}},
        sync_status
      )

  defp reconnect_action(true, id),
    do: [
      %{
        id: id,
        text: "Reconnect",
        click: show_modal("reconnect_modal"),
        target: nil
      }
    ]

  defp reconnect_action(false, _id), do: []

  attr :check, :any, required: true
  attr :can_reconnect, :boolean, required: true

  defp repo_row(assigns) do
    ~H"""
    <.check_row
      id="check-repo"
      label="Repository configured (workflow files and secret)"
      check={@check}
    >
      <:detail :if={match?({:setting_up, _}, @check)}>
        <p class="text-xs text-gray-500">
          GitHub can take a minute to show newly pushed files. Checking again shortly.
        </p>
      </:detail>
      <:detail :if={match?({:error, _}, @check)}>
        <Common.alert
          id="verify-connection-error"
          type="warning"
          header="Your GitHub repository is not properly connected with Lightning."
          actions={reconnect_action(@can_reconnect, "reconnect-button")}
        >
          <:message>
            <%= case @check do %>
              <% {:error, {:error, %{message: message}}} when is_binary(message) -> %>
                <p><code>GitHub Error: {message}</code></p>
              <% {:error, {:error, %{"message" => message}}} -> %>
                <p><code>GitHub Error: {message}</code></p>
              <% _other -> %>
                <p>There was a problem connecting to GitHub</p>
            <% end %>
          </:message>
        </Common.alert>
      </:detail>
    </.check_row>
    """
  end

  attr :check, :any, required: true
  attr :can_reconnect, :boolean, required: true

  defp tracking_row(assigns) do
    ~H"""
    <.check_row id="check-tracking" label="Branch tracks this project" check={@check}>
      <:detail :if={match?({:setting_up, _}, @check)}>
        <Common.alert id="first-sync-running" type="info">
          <:message>
            First sync running...
            <.link
              :if={elem(@check, 1)}
              href={elem(@check, 1).url}
              target="_blank"
              class="font-medium underline"
            >
              View run
            </.link>
          </:message>
        </Common.alert>
      </:detail>
      <:detail :if={match?({:failed_run, _}, @check)}>
        <Common.alert
          id="first-sync-failed"
          type="danger"
          header={"The first sync #{run_state(elem(@check, 1))}"}
        >
          <:message>
            Nothing has been committed for this project yet.
            <.link
              href={elem(@check, 1).url}
              target="_blank"
              class="font-medium underline"
            >
              See the run log on GitHub
            </.link>
          </:message>
        </Common.alert>
      </:detail>
      <:detail :if={match?({:other_project, _, _}, @check)}>
        <Common.alert
          id="tracking-other-project"
          type="warning"
          actions={reconnect_action(@can_reconnect, "tracking-reconnect-button")}
        >
          <:message>
            This branch tracks another project:
            <.project_label uuid={elem(@check, 1)} name={elem(@check, 2)} />.
            Reconnect with a different workspace folder, or use a separate
            branch for each project.
          </:message>
        </Common.alert>
      </:detail>
      <:detail :if={match?({:clash, _, _}, @check)}>
        <Common.alert
          id="alias-clash"
          type="warning"
          header={"Another project in this workspace also uses the alias \"#{elem(@check, 1)}\""}
          actions={reconnect_action(@can_reconnect, "clash-reconnect-button")}
        >
          <:message>
            <.clash_list clashes={elem(@check, 2)} />
            <p class="mt-2">
              The CLI can't tell them apart, so syncs will fail. Remove the
              stale file from the branch, or reconnect with a different
              workspace folder or local alias.
            </p>
          </:message>
        </Common.alert>
      </:detail>
      <:detail :if={@check == :not_synced}>
        <p class="text-xs text-gray-500">
          Nothing has been synced to this branch yet. Initiate a sync below.
        </p>
      </:detail>
      <:detail :if={@check == :unavailable}>
        <p class="text-xs text-gray-500">Could not load sync status from GitHub.</p>
      </:detail>
    </.check_row>
    """
  end

  attr :clashes, :list, required: true

  defp clash_list(assigns) do
    ~H"""
    <ul class="space-y-1">
      <li :for={clash <- @clashes}>
        <code class="break-all">{clash.path}</code>
        <span :if={clash.uuid}>
          (<.project_label uuid={clash.uuid} name={clash.name} />)
        </span>
      </li>
    </ul>
    """
  end

  attr :uuid, :string, required: true
  attr :name, :string, default: nil

  defp project_label(assigns) do
    ~H"""
    <span :if={@name} class="font-medium">{@name}</span>
    <code>{@uuid}</code>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :check, :any, required: true
  attr :sync_status, AsyncResult, required: true
  attr :key, :atom, required: true

  defp run_row(assigns) do
    assigns =
      assign(assigns,
        run: assigns.sync_status.ok? && assigns.sync_status.result[assigns.key]
      )

    ~H"""
    <.check_row id={@id} label={@label} check={@check}>
      <:summary>
        <%= if @run do %>
          <Common.datetime :if={@run.created_at} datetime={@run.created_at} />
          <.link href={@run.url} target="_blank" class="link">View run</.link>
          <.pill color={run_color(@run)}>{run_state(@run)}</.pill>
        <% else %>
          <span :if={@check == :none}>No runs yet</span>
        <% end %>
      </:summary>
    </.check_row>
    """
  end

  # "legacy" or "v2" when the repo's shared openfn-pull.yml is set up for the
  # other format, which connecting replaces
  defp pull_workflow_other_format(
         %AsyncResult{ok?: true, result: %{pull_workflow: found}},
         form
       ) do
    case {found, sync_version?(form)} do
      {:v1, true} -> "legacy"
      {:v2, false} -> "v2"
      _same_or_none -> nil
    end
  end

  defp pull_workflow_other_format(_workspace_check, _form), do: nil

  # The project whose workspace an export to GitHub would take over. Importing
  # (deploy) from a workspace that tracks another project is the normal case.
  defp replaces_project(
         %AsyncResult{
           ok?: true,
           result: %{tracking: {:other_project, _}} = check
         },
         form
       ) do
    if sync_version?(form) and form[:sync_direction].value != :deploy,
      do: tracked_project_name(check) || "another project"
  end

  defp replaces_project(_workspace_check, _form), do: nil

  defp tracked_project_name(%{tracking: {:other_project, uuid}} = check),
    do: find_project(check.projects, uuid)[:name]

  # The alias of this project's local copy in the workspace, once synced
  defp workspace_alias(%AsyncResult{ok?: true, result: status}, project_id),
    do: find_project(status.projects, project_id)[:alias]

  defp workspace_alias(_sync_status, _project_id), do: nil

  # A workspace at the repo root is stored as nil or "."
  defp workspace_label(connection) do
    case ProjectRepoConnection.workspace_path(connection) do
      path when path in ["", "."] -> "<root>"
      path -> path
    end
  end

  attr :workspace_check, AsyncResult, required: true
  attr :form, :map, required: true
  attr :project, :map, required: true
  attr :myself, :any, required: true

  # Pull direction files this project under an alias, which mustn't clash with
  # another local copy (the pull action runs --force, so the CLI won't stop
  # it). Deploy direction takes the workspace's project as it is.
  defp workspace_check(assigns) do
    ~H"""
    <div id="workspace-check" class="mt-2">
      <.async_result :let={check} assign={@workspace_check}>
        <:loading>
          <p class="flex items-center gap-1 text-xs text-gray-500">
            <.icon name="hero-arrow-path" class="h-4 w-4 animate-spin" />
            Checking the workspace on GitHub...
          </p>
        </:loading>
        <:failed>
          <p class="text-xs text-gray-500">
            Could not check the workspace on GitHub.
          </p>
        </:failed>
        <%= if @form[:sync_direction].value == :deploy do %>
          <p
            :if={alias = tracked_alias(check, @project.id)}
            class="text-xs text-gray-500"
          >
            The workspace holds a project under the alias <code
              id="workspace-alias"
              class="font-mono"
            >{alias}</code>, which
            will be imported.
          </p>
        <% else %>
          <.pull_alias_check
            check={check}
            form={@form}
            project={@project}
            myself={@myself}
          />
        <% end %>
      </.async_result>
    </div>
    """
  end

  defp tracked_alias(%{tracking: tracking, projects: projects}, project_id) do
    uuid =
      case tracking do
        :ok -> project_id
        {:other_project, uuid} -> uuid
        :pending -> nil
      end

    find_project(projects, uuid)[:alias]
  end

  attr :check, :map, required: true
  attr :form, :map, required: true
  attr :project, :map, required: true
  attr :myself, :any, required: true

  defp pull_alias_check(assigns) do
    %{check: check, form: form, project: project} = assigns

    %{alias: alias, clashes: clashes, error: error} =
      form_alias(check, form, project)

    takeover_uuid =
      case check.tracking do
        {:other_project, uuid} -> uuid
        _tracking -> nil
      end

    assigns =
      assign(assigns,
        alias: alias,
        clashes: clashes,
        alias_error: error,
        takeover_uuid: takeover_uuid
      )

    ~H"""
    <%!-- One box for both problems: taking over another project's folder,
    and an alias the CLI can't tell apart from another copy --%>
    <Common.alert
      :if={@takeover_uuid || @clashes != []}
      id="workspace-warning"
      type="warning"
      header={
        if(@takeover_uuid,
          do:
            "#{tracked_project_name(@check) || "Another project"} already syncs to this folder",
          else: "Another project in this folder is already saved as \"#{@alias}\""
        )
      }
    >
      <:message>
        <div :if={@takeover_uuid} id="workspace-tracks-other-project">
          <p>
            If you connect, this project's syncs and theirs will keep
            overwriting each other's files. To keep them apart, pick a
            different branch, or a different workspace folder under
            <.advanced_link myself={@myself} />.
          </p>
          <p class="mt-1 text-xs">Project <code>{@takeover_uuid}</code></p>
        </div>
        <div
          :if={@clashes != []}
          id="workspace-alias-clash"
          class={@takeover_uuid && "mt-3"}
        >
          <p :if={@takeover_uuid}>
            This project would also be saved as "{@alias}", which is taken:
          </p>
          <.clash_list clashes={@clashes} />
          <p class="mt-2">
            Connecting is disabled until this project is saved under a
            different name. Set a local alias or pick a different workspace
            folder under <.advanced_link myself={@myself} />.
          </p>
        </div>
      </:message>
    </Common.alert>
    <p :if={@alias_error} id="local-alias-error" class="mt-1 text-xs text-red-600">
      Local alias: {@alias_error}
    </p>
    <p
      :if={@clashes == []}
      id="workspace-alias-note"
      class="mt-1 text-xs text-gray-500"
    >
      This project will be saved in the workspace as <code
        id="workspace-alias"
        class="font-mono"
      >{@alias}</code>.
    </p>
    """
  end

  # The alias the first pull will file this project under, and what it clashes
  # with. An invalid alias won't be used, so check against what will. Its
  # error isn't on the field until the form is submitted, so read the
  # changeset.
  defp form_alias(check, form, project) do
    error = form.source.errors[:local_alias]

    requested =
      if !error, do: Ecto.Changeset.get_field(form.source, :local_alias)

    alias = project_alias(check.projects, project.id, requested)

    %{
      alias: alias,
      clashes: alias_clashes(check.projects, project.id, alias),
      error: error && elem(error, 0)
    }
  end

  # The CLI won't pull while the alias clashes, so don't let them connect
  defp alias_clash?(
         %AsyncResult{ok?: true, result: %{projects: _} = check},
         form,
         project
       ) do
    sync_version?(form) and form[:sync_direction].value != :deploy and
      form_alias(check, form, project).clashes != []
  end

  defp alias_clash?(_workspace_check, _form, _project), do: false

  attr :myself, :any, required: true

  defp advanced_link(assigns) do
    ~H"""
    <button
      type="button"
      class="font-medium underline"
      phx-click="show-advanced"
      phx-target={@myself}
    >
      Advanced settings
    </button>
    """
  end

  # status is queued/in_progress until the run completes with a conclusion
  defp run_state(%{status: "completed", conclusion: conclusion}),
    do: conclusion

  defp run_state(%{status: status}), do: status

  defp run_color(run) do
    case run_state(run) do
      "success" -> "green"
      state when state in ["failure", "timed_out", "startup_failure"] -> "red"
      state when state in ["queued", "in_progress", "waiting"] -> "blue"
      _other -> "gray"
    end
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
        <.workspace_fields :if={sync_version?(f)} form={f} />
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
  attr :project_id, :string, required: true
  attr :myself, :any, required: true

  # Inverted: sync_version is true (v2) unless the legacy switch is on. The
  # hidden input carries the current value with the form's phx-change events.
  defp config_format_toggle(assigns) do
    assigns = assign(assigns, :legacy?, !sync_version?(assigns.form))

    ~H"""
    <Common.wrapper_tooltip
      id="legacy-format"
      placement="top"
      class="mt-4 flex w-fit items-center"
      tooltip="Legacy formats use config.json, state.json and spec.yaml files in your GitHub repo."
      subtitle="If you already have a repo in the legacy format, you may prefer to keep that structure. The modern 'v2' format uses openfn.yaml and automatically expands workflows to disk."
    >
      <input
        type="hidden"
        name={@form[:sync_version].name}
        value={to_string(!@legacy?)}
      />
      <button
        id="toggle-legacy-format-switch"
        type="button"
        role="switch"
        aria-checked={to_string(@legacy?)}
        aria-labelledby="legacy-format-label"
        phx-click="toggle-legacy-format"
        phx-target={@myself}
        class={[
          if(@legacy?, do: "bg-indigo-600", else: "bg-gray-200"),
          "relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-indigo-600 focus:ring-offset-2"
        ]}
      >
        <span
          aria-hidden="true"
          class={[
            if(@legacy?, do: "translate-x-5", else: "translate-x-0"),
            "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"
          ]}
        >
        </span>
      </button>
      <span class="ml-3 text-sm text-gray-900" id="legacy-format-label">
        Use legacy formats (config.json)
      </span>
    </Common.wrapper_tooltip>
    """
  end

  attr :form, :map, required: true

  defp workspace_fields(assigns) do
    ~H"""
    <div class="mt-4">
      <.input
        type="text"
        field={@form[:workspace_path]}
        label="Workspace folder"
        placeholder="repository root"
        class="placeholder:italic placeholder:text-slate-400"
        phx-debounce="500"
      />
      <p class="mt-1 text-xs text-gray-500">
        The folder holding the project's openfn.yaml and files.
      </p>
      <div :if={@form[:sync_direction].value != :deploy} class="mt-4">
        <.input
          type="text"
          field={@form[:local_alias]}
          label="Local alias"
          placeholder="main"
          class="placeholder:italic placeholder:text-slate-400"
          phx-debounce="300"
        />
        <p class="mt-1 text-xs text-gray-500">
          The name this project is saved under in the workspace, from the next
          pull.
        </p>
      </div>
    </div>
    """
  end

  defp sync_version?(form) do
    form[:sync_version].value in [true, "true"]
  end

  attr :form, :map, required: true

  defp sync_order_radio(assigns) do
    ~H"""
    <div class="mb-4">
      <.label>
        Initial Setup
      </.label>
      <p class="text-sm text-gray-500">
        Choose the direction of the first sync: export this project to GitHub, or import an existing project from GitHub.
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
                <span class="font-medium">OpenFn --> GitHub:</span> Export to GitHub
              </label>

              <p id="pull_first_sync_option_description" class="text-gray-500">
                Commit a copy of your current OpenFn project to GitHub. This does not affect any workflows or configuration here.
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
                Replace this OpenFn project with the workflows, collections and channels that are already committed to GitHub.
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
  attr :pull_workflow_other_format, :string, default: nil
  attr :replaces_project, :string, default: nil

  defp accept_checkbox(assigns) do
    ~H"""
    <div class={[
      "mt-4 flex gap-3 rounded-md border p-3",
      if(@form[:sync_direction].value == :deploy,
        do: "border-red-300 bg-red-50",
        else: "border-yellow-300 bg-yellow-50"
      )
    ]}>
      <.input
        type="checkbox"
        field={@form[:accept]}
        required="true"
        hidden_input={false}
      />
      <span class="text-sm text-gray-900">
        I understand that
        <%= if @form[:sync_direction].value == :deploy do %>
          my current OpenFn project <b>will be destroyed</b> and
        <% end %>
        <%= if @replaces_project do %>
          <b id="replaces-project">{"#{@replaces_project}'s files in this folder will be replaced"}</b>, and
        <% end %>
        the following files will be committed to <b><%= @form[
          :repo
        ].value %></b>:
        <ul class="my-2 space-y-1 text-xs text-gray-700">
          <li class="flex items-start gap-1.5">
            <.icon name="hero-document-plus" class="h-4 w-4 shrink-0 text-gray-500" />
            <code class="break-all">
              .github/workflows/openfn-pull.yml -> {@default_branch}
            </code>
          </li>
          <li
            :if={@pull_workflow_other_format}
            id="pull-workflow-other-format"
            class="ml-5 text-red-700"
          >
            This file is set up for the {@pull_workflow_other_format} format.
            Replacing it stops syncs from OpenFn for every project connected
            to this repository with that format.
          </li>
          <li class="flex items-start gap-1.5">
            <.icon name="hero-document-plus" class="h-4 w-4 shrink-0 text-gray-500" />
            <code class="break-all">
              .github/workflows/openfn-{@project.id}-deploy.yml -> {@form[
                :branch
              ].value}
            </code>
          </li>
          <%!-- v2 commits no config: the CLI writes openfn.yaml on pull --%>
          <%= if to_string(@form[:config_path].value) == "" and !sync_version?(@form) do %>
            <li class="flex items-start gap-1.5">
              <.icon
                name="hero-document-plus"
                class="h-4 w-4 shrink-0 text-gray-500"
              />
              <code class="break-all">
                openfn-{@project.id}-config.json -> {@form[:branch].value}
              </code>
            </li>
          <% end %>
        </ul>
        Existing versions of these files on these branches will be overwritten (but will still exist in git history).
      </span>
    </div>
    """
  end
end
