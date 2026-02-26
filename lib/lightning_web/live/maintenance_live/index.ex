defmodule LightningWeb.MaintenanceLive.Index do
  @moduledoc """
  LiveView for the Settings > Maintenance page.

  Provides action buttons to refresh the adaptor registry, install adaptor
  icons, and install credential schemas at runtime without restarting the app.
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

  @actions [
    "refresh_adaptor_registry",
    "install_adaptor_icons",
    "install_schemas"
  ]

  @impl true
  def mount(_params, _session, socket) do
    can_access_admin_space =
      Users
      |> Permissions.can?(
        :access_admin_space,
        socket.assigns.current_user,
        {}
      )

    if can_access_admin_space do
      {:ok,
       socket
       |> assign(
         active_menu_item: :maintenance,
         page_title: "Maintenance",
         refresh_status: %{},
         running: MapSet.new()
       ), layout: {LightningWeb.Layouts, :settings}}
    else
      {:ok,
       put_flash(socket, :nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  @impl true
  def handle_event("run_" <> action, _params, socket)
      when action in @actions do
    if superuser?(socket) do
      pid = self()

      Task.start(fn ->
        result =
          try do
            run_action(action)
          rescue
            error -> {:error, Exception.message(error)}
          end

        case result do
          {:ok, _} ->
            Lightning.API.broadcast("adaptor:refresh", {:refresh_all, node()})

          _ ->
            :noop
        end

        send(pid, {:action_complete, action, result})
      end)

      {:noreply,
       socket
       |> update(:running, &MapSet.put(&1, action))
       |> put_in_status(action, :running)}
    else
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  @impl true
  def handle_info({:action_complete, action, result}, socket) do
    status =
      case result do
        {:ok, _} -> :success
        {:error, _} -> :error
      end

    {:noreply,
     socket
     |> update(:running, &MapSet.delete(&1, action))
     |> put_in_status(action, status)}
  end

  attr :action, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :running, :boolean, required: true
  attr :status, :atom, default: nil

  defp maintenance_action(assigns) do
    ~H"""
    <div class="flex items-center justify-between rounded-lg border border-gray-200 p-4">
      <div class="flex-1 mr-4">
        <h4 class="text-sm font-medium text-gray-900">{@title}</h4>
        <p class="text-sm text-gray-500">{@description}</p>
      </div>
      <div class="flex items-center gap-3">
        <span :if={@status == :success} class="text-sm text-green-600">
          <.icon name="hero-check-circle-solid" class="h-5 w-5" /> Done
        </span>
        <span :if={@status == :error} class="text-sm text-red-600">
          <.icon name="hero-x-circle-solid" class="h-5 w-5" /> Failed
        </span>
        <button
          phx-click={"run_#{@action}"}
          disabled={@running}
          class="inline-flex items-center gap-1.5 rounded-md bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <.icon :if={@running} name="hero-arrow-path" class="h-4 w-4 animate-spin" />
          <span :if={@running}>Running...</span>
          <span :if={!@running}>Run</span>
        </button>
      </div>
    </div>
    """
  end

  defp run_action("refresh_adaptor_registry") do
    Lightning.AdaptorRegistry.refresh_sync()
  end

  defp run_action("install_adaptor_icons") do
    Lightning.AdaptorIcons.refresh()
  end

  defp run_action("install_schemas") do
    Lightning.CredentialSchemas.refresh()
  end

  defp put_in_status(socket, action, status) do
    update(socket, :refresh_status, &Map.put(&1, action, status))
  end

  defp superuser?(socket) do
    Users
    |> Permissions.can?(
      :access_admin_space,
      socket.assigns.current_user,
      {}
    )
  end
end
