defmodule LightningWeb.Components.CollaborativeEditor do
  @moduledoc """
  React component for collaborative workflow editing using Yjs.
  """
  use LightningWeb, :component
  import React

  attr :workflow_id, :string, required: true
  attr :workflow_name, :string, required: true

  jsx("assets/js/react/components/CollaborativeEditor.tsx")
end
