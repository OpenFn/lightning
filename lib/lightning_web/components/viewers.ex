defmodule LightningWeb.Components.Viewers do
  @moduledoc """
  Components for rendering Dataclips.
  """

  use LightningWeb, :component

  import React

  attr :id, :string, required: true
  attr :json, :string, required: true

  # react imports
  jsx("assets/js/react/components/CollectionPreviewViewer.tsx")

  def collection_preview_viewer(assigns) do
    ~H"""
    <.CollectionPreviewViewer id={@id} json={@json} />
    """
  end
end
