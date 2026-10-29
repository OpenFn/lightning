defmodule LightningWeb.MaintenanceLive.Index do
  @moduledoc """
  Superuser-only page for on-demand `Lightning.Adaptors` maintenance, and for
  seeing whether the app and its connected workers are up to date.

  The workers card follows `LightningWeb.WorkerPresence`, so it updates as
  workers connect and disconnect.

  Neither action blocks the LiveView. The registry refresh is queued on the
  scheduler and returns at once. The icon refresh can run for up to two
  minutes, so it goes through `start_async` and flashes its result when it
  completes.
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users
  alias Lightning.UpdateCheck
  alias Lightning.UpdateCheck.Releases
  alias Lightning.UsageTracking
  alias LightningWeb.WorkerPresence

  @impl true
  def mount(_params, _session, socket) do
    if superuser?(socket) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Lightning.PubSub, WorkerPresence.topic())
      end

      {:ok,
       socket
       |> assign(active_menu_item: :maintenance, page_title: "Maintenance")
       |> assign(update_check: update_check_settings(), checking_update?: false)
       |> assign_new(:update_status, fn -> nil end)
       |> assign_workers()
       |> assign_async(:usage_tracking, fn ->
         {:ok, %{usage_tracking: usage_tracking_status()}}
       end), layout: {LightningWeb.Layouts, :settings}}
    else
      {:ok,
       socket
       |> put_flash(:nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  @impl true
  def handle_event("refresh_adaptors", _params, socket) do
    if superuser?(socket) do
      socket =
        case Lightning.Adaptors.refresh() do
          :ok ->
            put_flash(socket, :info, "Adaptor refresh queued.")

          {:error, reason} ->
            put_flash(socket, :error, "Refresh failed: #{inspect(reason)}")
        end

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  def handle_event("check_for_update", _params, socket) do
    if superuser?(socket) do
      {:noreply,
       socket
       |> assign(checking_update?: true)
       |> start_async(:check_for_update, fn -> UpdateCheck.check_now() end)}
    else
      {:noreply,
       socket
       |> put_flash(:nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  def handle_event("refresh_icons", _params, socket) do
    if superuser?(socket) do
      {:noreply,
       socket
       |> put_flash(:info, "Icon refresh started.")
       |> start_async(:refresh_icons, fn ->
         Lightning.Adaptors.refresh_icons()
       end)}
    else
      {:noreply,
       socket
       |> put_flash(:nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign_workers(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:refresh_icons, {:ok, result}, socket) do
    socket =
      case result do
        {:ok, %{updated: updated, unchanged: unchanged}} ->
          put_flash(
            socket,
            :info,
            "Icon refresh complete — #{updated} updated, #{unchanged} unchanged."
          )

        {:error, reason} ->
          put_flash(socket, :error, "Icon refresh failed: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  def handle_async(:check_for_update, {:ok, result}, socket) do
    socket = assign(socket, checking_update?: false)

    socket =
      case result do
        {:ok, status} ->
          socket = socket |> assign(update_status: status) |> assign_workers()

          put_flash(
            socket,
            :info,
            update_flash(status, socket.assigns.outdated_worker_count)
          )

        {:error, :disabled} ->
          put_flash(
            socket,
            :error,
            "The update check is turned off. Set UPDATE_CHECK_ENABLED=true and restart."
          )

        {:error, :no_release_found} ->
          put_flash(
            socket,
            :error,
            "Update check failed: no release matches the #{socket.assigns.update_check.tag} tag."
          )

        {:error, reason} ->
          put_flash(socket, :error, "Update check failed: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  def handle_async(:check_for_update, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(checking_update?: false)
     |> put_flash(:error, "Update check failed: #{inspect(reason)}")}
  end

  def handle_async(:refresh_icons, {:exit, reason}, socket) do
    {:noreply,
     put_flash(socket, :error, "Icon refresh failed: #{inspect(reason)}")}
  end

  defp update_flash(%{update_available?: true, latest: latest}, _outdated),
    do: "v#{latest} is available."

  defp update_flash(_status, outdated) when outdated > 0,
    do: "A newer worker version is available."

  defp update_flash(_status, _outdated), do: "You're on the latest version."

  # Workers are grouped by the versions they report, newest first, and each
  # group is compared with the latest worker release from the update status.
  defp assign_workers(socket) do
    status = socket.assigns.update_status
    workers = WorkerPresence.list_workers()

    groups =
      workers
      |> Enum.group_by(&{&1.worker_version, &1.api_version})
      |> Enum.map(fn {{version, api_version}, group} ->
        %{
          version: version,
          api_version: api_version,
          count: length(group),
          capacity: group |> Enum.map(& &1.capacity) |> Enum.sum(),
          outdated?: UpdateCheck.worker_outdated?(status, version)
        }
      end)
      |> Enum.sort(&(compare_versions(&1.version, &2.version) != :lt))

    assign(socket,
      worker_groups: groups,
      worker_count: length(workers),
      worker_capacity: groups |> Enum.map(& &1.capacity) |> Enum.sum(),
      outdated_worker_count:
        groups
        |> Enum.filter(& &1.outdated?)
        |> Enum.map(& &1.count)
        |> Enum.sum()
    )
  end

  # Versions that don't parse, including missing ones, sort last.
  defp compare_versions(a, b) do
    case {Releases.parse_version(a), Releases.parse_version(b)} do
      {{:ok, a}, {:ok, b}} -> Version.compare(a, b)
      {{:ok, _a}, :error} -> :gt
      {:error, {:ok, _b}} -> :lt
      _neither -> :eq
    end
  end

  defp update_check_settings do
    config = Lightning.Config.update_check()

    %{
      enabled: Lightning.Config.update_check_enabled?(),
      registry: config[:registry],
      repository: config[:repository],
      tag: config[:tag],
      worker_registry: config[:worker_registry],
      worker_repository: config[:worker_repository]
    }
  end

  defp usage_tracking_status do
    %{
      enabled: Lightning.Config.usage_tracking_enabled?(),
      cleartext: Lightning.Config.usage_tracking_cleartext_uuids_enabled?(),
      host: Lightning.Config.usage_tracking_host(),
      identity: UsageTracking.instance_identity()
    }
  end

  attr :status, :map, default: nil

  defp update_status_pill(%{status: %{update_available?: true}} = assigns) do
    ~H"""
    <.pill id="update-status" color="yellow">Update available</.pill>
    """
  end

  defp update_status_pill(%{status: %{}} = assigns) do
    ~H"""
    <.pill id="update-status" color="green">Up to date</.pill>
    """
  end

  defp update_status_pill(assigns) do
    ~H"""
    <.pill id="update-status" color="gray">Not checked yet</.pill>
    """
  end

  attr :status, :map, default: nil
  attr :count, :integer, required: true
  attr :outdated, :integer, required: true

  defp workers_status_pill(%{outdated: outdated} = assigns) when outdated > 0 do
    ~H"""
    <.pill id="workers-status" color="yellow">Update available</.pill>
    """
  end

  defp workers_status_pill(%{count: 0} = assigns) do
    ~H"""
    <.pill id="workers-status" color="gray">None connected</.pill>
    """
  end

  defp workers_status_pill(%{status: %{worker: %{latest: latest}}} = assigns)
       when is_binary(latest) do
    ~H"""
    <.pill id="workers-status" color="green">Up to date</.pill>
    """
  end

  # Checked, but no worker release was found or the lookup failed.
  defp workers_status_pill(%{status: %{}} = assigns) do
    ~H"""
    <.pill id="workers-status" color="gray">Unknown</.pill>
    """
  end

  defp workers_status_pill(assigns) do
    ~H"""
    <.pill id="workers-status" color="gray">Not checked yet</.pill>
    """
  end

  attr :enabled, :boolean, required: true

  defp usage_status_pill(%{enabled: true} = assigns) do
    ~H"""
    <.pill id="usage-metrics-status" color="green">Enabled</.pill>
    """
  end

  defp usage_status_pill(assigns) do
    ~H"""
    <.pill id="usage-metrics-status" color="red">Disabled</.pill>
    """
  end

  attr :id, :string, default: nil
  attr :tone, :string, default: "gray", values: ["gray", "red"]
  attr :class, :string, default: nil
  attr :value, :string, required: true

  # phx-no-format keeps the value flush against the tags; any whitespace
  # inside them would show as padding on the shaded background.
  defp inline_code(assigns) do
    ~H"""
    <code id={@id} class={[inline_code_classes(@tone), @class]} phx-no-format>{@value}</code>
    """
  end

  defp inline_code_classes("gray"),
    do: "rounded bg-secondary-100 px-1.5 py-0.5 font-mono text-xs"

  defp inline_code_classes("red"),
    do: "rounded bg-red-100 px-1 font-mono"

  defp superuser?(socket) do
    Permissions.can?(
      Users,
      :access_admin_space,
      socket.assigns.current_user,
      {}
    )
  end
end
