defmodule LightningWeb.DataclipLive.FormComponent do
  @moduledoc """
  Form Component for working with a single dataclip
  """
  use LightningWeb, :live_component

  import LightningWeb.Components.Form

  alias Lightning.Invocation

  @impl true
  def update(%{dataclip: dataclip, project: project} = assigns, socket) do
    types = Lightning.Invocation.Dataclip.source_types()

    changeset =
      Invocation.change_dataclip(dataclip, %{"project_id" => project.id})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:types, Enum.zip(types, types))}
  end
end
