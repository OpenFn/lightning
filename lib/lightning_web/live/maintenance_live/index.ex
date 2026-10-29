defmodule LightningWeb.MaintenanceLive.Index do
  @moduledoc """
  Superuser-only page for on-demand `Lightning.Adaptors` maintenance.

  Neither action blocks the LiveView. The registry refresh is queued on the
  scheduler and returns at once. The icon refresh can run for up to two
  minutes, so it goes through `start_async` and flashes its result when it
  completes.
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users
  alias Lightning.UpdateCheck
  alias Lightning.UsageTracking

  @impl true
  def mount(_params, _session, socket) do
    if superuser?(socket) do
      {:ok,
       socket
       |> assign(active_menu_item: :maintenance, page_title: "Maintenance")
       |> assign(update_check: update_check_settings(), checking_update?: false)
       |> assign_new(:update_status, fn -> nil end)
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
          socket
          |> assign(update_status: status)
          |> put_flash(:info, update_flash(status))

        {:error, :disabled} ->
          put_flash(
            socket,
            :error,
            "The update check is turned off. Set UPDATE_CHECK_ENABLED=true and restart."
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

  defp update_flash(%{update_available?: true, latest: latest}),
    do: "v#{latest} is available."

  defp update_flash(_status), do: "You're on the latest version."

  defp update_check_settings do
    config = Lightning.Config.update_check()

    %{
      enabled: Lightning.Config.update_check_enabled?(),
      registry: config[:registry],
      repository: config[:repository],
      tag: config[:tag]
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
