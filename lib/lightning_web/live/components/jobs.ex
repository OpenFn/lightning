defmodule LightningWeb.Components.Jobs do
  @moduledoc false
  use LightningWeb, :component

  import LightningWeb.Components.Form

  def credential_select(assigns) do
    ~H"""
    <.label_field
      form={@form}
      id={:project_credential_id}
      title="Credential"
      for="credentialField"
    />
    <%= error_tag(@form, :project_credential_id, class: "block w-full rounded-md") %>
    <.select_field
      form={@form}
      name={:project_credential_id}
      id="credentialField"
      prompt=""
      values={@credentials}
    />
    """
  end

  def adaptor_name_select(assigns) do
    ~H"""
    <.label_field form={@form} id={:adaptor_name} title="Adaptor" for="adaptorField" />
    <%= error_tag(@form, :adaptor_name, class: "block w-full rounded-md") %>
    <.select_field
      form={@form}
      name={:adaptor_name}
      prompt=""
      selected={@adaptor_name}
      id="adaptorField"
      values={@adaptors}
    />
    """
  end

  def adaptor_version_select(assigns) do
    ~H"""
    <.label_field
      form={@form}
      id={:adaptor}
      title="Version"
      for="adaptorVersionField"
    />
    <%= error_tag(@form, :adaptor, class: "block w-full rounded-md") %>
    <.select_field
      form={@form}
      disabled={!@adaptor_name}
      name={:adaptor}
      id="adaptorVersionField"
      values={@versions}
    />
    """
  end
end
