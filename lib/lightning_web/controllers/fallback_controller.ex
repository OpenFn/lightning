defmodule LightningWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use LightningWeb, :controller

  # This clause is an example of how to handle resources that cannot be found.
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(LightningWeb.ErrorView)
    |> render(:"404")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(LightningWeb.ErrorView)
    |> render(:"401", error: %{error: :unauthirized})
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(LightningWeb.ErrorView)
    |> render(:"403")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: LightningWeb.ChangesetJSON)
    |> render("error.json", changeset: changeset)
  end

  def call(conn, {:error, error}) when is_map(error) do
    conn
    |> put_status(:unauthorized)
    |> put_view(LightningWeb.ErrorView)
    |> render(:"401", error: error)
  end
end
