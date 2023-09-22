defmodule LightningWeb.ChangesetJSON do
  @moduledoc """
  Renders changesets as JSON.
  """

  def error(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(
      changeset,
      &LightningWeb.Components.NewInputs.translate_error/1
    )
  end

  def error(%{changeset: %Ecto.Changeset{} = changeset}) do
    %{errors: error(changeset)}
  end
end
