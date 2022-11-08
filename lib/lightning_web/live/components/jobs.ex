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
end
