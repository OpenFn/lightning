defmodule LightningWeb.ChangesetJSON do
  @moduledoc """
  Renders changesets as JSON.
  """

  import LightningWeb.CoreComponents, only: [translate_error: 1]

  def error(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(
      changeset,
      &translate_error/1
    )
  end

  def error(%{changeset: %Ecto.Changeset{} = changeset}) do
    %{errors: error(changeset)}
  end
end
