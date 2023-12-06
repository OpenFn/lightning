defmodule LightningWeb.ChangesetView do
  use LightningWeb, :view

  import LightningWeb.CoreComponents, only: [translate_errors: 1]

  def render("error.json", %{changeset: changeset}) do
    # When encoded, the changeset returns its errors
    # as a JSON object. So we just pass it forward.
    %{errors: translate_errors(changeset)}
  end
end
