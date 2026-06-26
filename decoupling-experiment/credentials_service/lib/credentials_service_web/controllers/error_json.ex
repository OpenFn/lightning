defmodule CredentialsServiceWeb.ErrorJSON do
  @moduledoc "Renders endpoint-level errors as JSON."

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
