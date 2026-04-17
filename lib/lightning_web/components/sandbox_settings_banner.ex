defmodule LightningWeb.Components.SandboxSettingsBanner do
  @moduledoc """
  Banner shown at the top of a Project Settings tab when the project is a
  sandbox, communicating how changes on that tab will (or will not) flow
  to the parent project on merge.

  Three variants:

    * `:local` — changes apply only to this sandbox and do not sync on merge
    * `:editable` — changes will sync to the parent on merge
    * `:inherited` — settings are read-only, managed in the parent project

  ## Examples

      <.sandbox_settings_banner variant={:local} />

      <.sandbox_settings_banner
        variant={:inherited}
        parent_project={@parent_project}
      />
  """
  use LightningWeb, :component

  alias LightningWeb.Components.Common

  attr :variant, :atom, required: true, values: [:local, :editable, :inherited]
  attr :id, :string, required: true
  attr :parent_project, :map, default: nil

  def sandbox_settings_banner(%{variant: :local} = assigns) do
    ~H"""
    <Common.alert id={@id} type="info">
      <:message>
        Changes you make here only apply to this sandbox and won't sync to the parent project on merge.
      </:message>
    </Common.alert>
    """
  end

  def sandbox_settings_banner(%{variant: :editable} = assigns) do
    ~H"""
    <Common.alert id={@id} type="success">
      <:message>
        Changes you make here will sync to the parent project on merge.
      </:message>
    </Common.alert>
    """
  end

  def sandbox_settings_banner(%{variant: :inherited} = assigns) do
    ~H"""
    <Common.alert id={@id} type="warning">
      <:message>
        These settings are inherited from the parent project
        <.parent_link :if={@parent_project} project={@parent_project} />and can't be changed here.
      </:message>
    </Common.alert>
    """
  end

  attr :project, :map, required: true

  defp parent_link(assigns) do
    ~H"""
    (<.link
      navigate={~p"/projects/#{@project.id}/settings"}
      class="font-medium underline"
    >{@project.name}</.link>)
    """
  end
end
