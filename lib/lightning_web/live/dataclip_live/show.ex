defmodule LightningWeb.DataclipLive.Show do
  @moduledoc """
  One dataclip: its details, and its body, which the page fetches from the
  dataclip controller itself. The page has no events; the LiveView's job is
  the project check and the props.
  """
  use LightningWeb, :live_view

  alias Lightning.Invocation

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :check_limits}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(active_menu_item: :dataclip)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    %{project: project} = socket.assigns

    if Invocation.dataclip_in_project?(id, project.id) do
      {:noreply,
       socket
       |> assign(:id, id)
       |> assign(:page_title, "Dataclip")
       |> assign(:dataclip, Invocation.get_dataclip!(id))}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Dataclip not found")
       |> push_navigate(to: ~p"/projects/#{project}/history")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.design_system_page
      name="DataclipShowPage"
      props={
        %{
          project: %{
            id: @project.id,
            parentId: @project.parent_id,
            color: @project.color
          },
          projectLabel: @project_label,
          dataclip: dataclip_json(@dataclip)
        }
      }
      banner={assigns[:banner]}
      current_user={@current_user}
    />
    """
  end

  # The shape the design system's DataclipDetail type expects: what the
  # details card shows, never the body.
  defp dataclip_json(dataclip) do
    %{
      id: dataclip.id,
      type: dataclip.type,
      insertedAt: dataclip.inserted_at,
      updatedAt: dataclip.updated_at,
      wipedAt: dataclip.wiped_at
    }
  end
end
