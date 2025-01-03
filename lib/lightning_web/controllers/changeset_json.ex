defmodule LightningWeb.ChangesetJSON do
  @moduledoc """
  Renders changesets as JSON.
  """

  import LightningWeb.CoreComponents, only: [translate_error: 1]

  def errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(
      changeset,
      &translate_error/1
    )
  end

  def errors(%{changeset: %Ecto.Changeset{} = changeset}) do
    %{errors: errors(changeset)}
  end
end
