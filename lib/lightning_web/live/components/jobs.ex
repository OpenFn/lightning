defmodule LightningWeb.Components.Jobs do
  @moduledoc false
  use LightningWeb, :component

  import LightningWeb.Components.Form

  def credential_select(assigns) do
    assigns =
      assign(assigns,
        credentials:
          assigns.credentials |> Enum.map(&{&1.credential.name, &1.id})
      )
      |> assign_new(:disabled, fn -> false end)

    ~H"""
    <.label_field
      form={@form}
      field={:project_credential_id}
      title="Credential"
      for="credentialField"
      tooltip="To connect to an external system that requires authentication you
        usually want a credential with the same 'type' as your adaptor. Hint: If
        you are using the common adaptor there is no need for credentials."
    />
    <%= error_tag(@form, :project_credential_id, class: "block w-full rounded-md") %>
    <.select_field
      form={@form}
      name={:project_credential_id}
      id="credentialField"
      prompt=""
      values={@credentials}
      disabled={@disabled}
    />
    """
  end
end
