defmodule CredentialsServiceWeb.FallbackController do
  @moduledoc """
  Translates context results into responses. Mirrors
  `LightningWeb.FallbackController`'s status mapping (404/403/401/422), which the
  decoupled contract keeps (see `docs/api.md` §3).
  """
  use Phoenix.Controller, formats: [:json]

  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> error("Not Found")
  end

  def call(conn, {:error, :forbidden}) do
    conn |> put_status(:forbidden) |> error("Forbidden")
  end

  def call(conn, {:error, :unauthorized}) do
    conn |> put_status(:unauthorized) |> error("Unauthorized")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: changeset_errors(changeset)})
  end

  defp error(conn, detail), do: json(conn, %{errors: %{detail: detail}})

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
