defmodule Lightning.Security do
  @moduledoc """
  Security helpers.
  """
  alias Ecto.Changeset

  @doc """
  Redact a password inside a json on a changeset field.
  If the field has a valid string value "password":"thesecret" becomes "password":"***".
  """
  @spec redact_password(Changeset.t(), atom()) :: Changeset.t()
  def redact_password(%Changeset{valid?: true} = changeset, field) do
    with {:ok, str_to_redact} <- Changeset.fetch_change(changeset, field),
         true <- is_binary(str_to_redact) and String.valid?(str_to_redact) do
      redacted =
        String.replace(
          str_to_redact,
          ~r/\"password\":\"\w+\"/,
          "\\1\"password\":\"\*\*\*\""
        )

      Changeset.put_change(changeset, field, redacted)
    else
      _any -> changeset
    end
  end

  def redact_password(changeset, _field), do: changeset
end
