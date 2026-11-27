defmodule LightningWeb.API.SessionParams do
  @moduledoc """
  The body of `POST /api/session`. A sign-in sends `email` and `password`, and
  may send the MFA code with them. Finishing a pending sign-in sends only the
  code. The code is `mfa_code` or `backup_code`, never both.
  """
  import Ecto.Changeset

  alias LightningWeb.API.Errors
  alias LightningWeb.API.Problem
  alias LightningWeb.API.Request

  @type code :: {:totp, String.t()} | {:backup_code, String.t()}
  @type sign_in :: %{
          email: String.t(),
          password: String.t(),
          code: code() | nil
        }

  @types [
    email: :string,
    password: :string,
    mfa_code: :string,
    backup_code: :string
  ]

  @spec sign_in(map()) :: {:ok, sign_in()} | {:error, Problem.t()}
  def sign_in(body) do
    with {:ok, params} <- parse(body, [:email, :password]) do
      {:ok,
       %{email: params.email, password: params.password, code: code(params)}}
    end
  end

  @spec continuation(map()) :: {:ok, code()} | {:error, Problem.t()}
  def continuation(body) do
    required = if is_map_key(body, "backup_code"), do: [], else: [:mfa_code]

    with {:ok, params} <- parse(body, required), do: {:ok, code(params)}
  end

  # An empty string is a value, so an empty password is a wrong password.
  defp parse(body, required) do
    with :ok <- Request.check_object(body) do
      fields = Keyword.keys(@types)

      changeset =
        {%{}, Map.new(@types)}
        |> cast(body, fields, empty_values: [])
        |> validate_not_null()
        |> validate_required(required)
        |> validate_one_code()

      case Request.unknown_keys(body, [], fields) ++
             Errors.from_changeset(changeset) do
        [] -> {:ok, apply_changes(changeset)}
        entries -> Errors.refuse(entries)
      end
    end
  end

  # `cast` reads a JSON null as a key never sent, but a null code would then
  # quietly ask for MFA instead of refusing the body.
  defp validate_not_null(changeset) do
    Enum.reduce(@types, changeset, fn {field, _type}, changeset ->
      case Map.fetch(changeset.params, Atom.to_string(field)) do
        {:ok, nil} -> add_error(changeset, field, "is invalid", code: :type)
        _sent_or_not -> changeset
      end
    end)
  end

  defp validate_one_code(
         %{params: %{"mfa_code" => _, "backup_code" => _}} = changeset
       ),
       do:
         add_error(changeset, :backup_code, "can't be sent with %{other}",
           code: :exclusive,
           other: "mfa_code"
         )

  defp validate_one_code(changeset), do: changeset

  defp code(%{mfa_code: code}), do: {:totp, code}
  defp code(%{backup_code: code}), do: {:backup_code, code}
  defp code(_params), do: nil
end
