defmodule LightningWeb.ChangesetJSON do
  @moduledoc """
  Renders changesets as JSON.
  """

  def error(%{changeset: changeset}) do
    %{
      errors:
        Ecto.Changeset.traverse_errors(
          changeset,
          &LightningWeb.CoreComponents.translate_error/1
        )
    }
  end
end
