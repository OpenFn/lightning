defmodule LightningWeb.RunLive.Show do
  @moduledoc """
  Show page for individual runs.
  """
  use LightningWeb, :live_view

  alias Lightning.Invocation.Run

  import Ecto.Query

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(active_menu_item: :runs, page_title: "Run")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def apply_action(socket, :show, %{"id" => id}) do
    run =
      from(r in Run, where: r.id == ^id, preload: :output_dataclip)
      |> Lightning.Repo.one()

    socket |> assign(run: run)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layout.page_content>
      <:header>
        <Layout.header socket={@socket} title={@page_title} />
      </:header>
      <Layout.centered>
        <LightningWeb.RunLive.Components.run_viewer run={@run} />
      </Layout.centered>
    </Layout.page_content>
    """
  end
end
