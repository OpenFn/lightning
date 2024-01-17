defmodule LightningWeb.RunLive.Show do
  @moduledoc """
  Show page for individual runs.
  """
  use LightningWeb, :live_view

  import Ecto.Query

  alias Lightning.Invocation
  alias Lightning.Invocation.Run
  alias Lightning.Repo

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       active_menu_item: :runs,
       page_title: "Run"
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def apply_action(socket, :show, %{"id" => id}) do
    run =
      from(r in Run,
        where: r.id == ^id,
        preload: [
          [output_dataclip: ^Invocation.Query.dataclip_with_body()],
          [input_dataclip: ^Invocation.Query.dataclip_with_body()],
          :job,
          :attempts,
          [credential: [:user]]
        ]
      )
      |> Lightning.Repo.one()
      |> Repo.preload(:log_lines)

    socket
    |> assign(run: run)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title><%= @page_title %></:title>
        </LayoutComponents.header>
      </:header>
      <LayoutComponents.centered>
        <LightningWeb.RunLive.Components.run_viewer
          run={@run}
          project_id={@project.id}
          show_input_dataclip={true}
        />
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end
end
