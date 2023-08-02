defmodule LightningWeb.ProjectLive.MFARequired do
  @moduledoc """
  Liveview for project access denied error messages
  """
  use LightningWeb, :live_view

  on_mount __MODULE__

  on_mount {LightningWeb.Hooks, :assign_projects}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, active_menu_item: nil)}
  end

  def on_mount(:default, _params, _session, socket) do
    %{current_user: current_user} = socket.assigns

    if current_user.mfa_enabled do
      {:halt, redirect(socket, to: "/")}
    else
      {:cont, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    apply_action(socket, socket.assigns.live_action, params)
  end

  defp apply_action(socket, :index, _params) do
    {:noreply, socket |> assign(page_title: "MFA Required for Project")}
  end
end
