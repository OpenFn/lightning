defmodule LightningWeb.ChangesetView do
  alias LightningWeb.Components.NewInputs
  use LightningWeb, :view

  def render("error.json", %{changeset: changeset}) do
    # When encoded, the changeset returns its errors
    # as a JSON object. So we just pass it forward.
    %{errors: NewInputs.translate_errors(changeset)}
  end
end
