defmodule LightningWeb.BrowserFallbackController do
  @moduledoc """
  Turns the errors the browser-pipeline controllers return into responses. API
  controllers answer through `LightningWeb.API.FallbackController`.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use LightningWeb, :controller

  import LightningWeb.CoreComponents, only: [translate_errors: 1]

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(LightningWeb.ErrorView)
    |> render(:"404")
  end

  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> put_view(LightningWeb.ErrorView)
    |> render(:"400")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(LightningWeb.ErrorView)
    |> render(:"401")
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
    |> json(%{errors: translate_errors(changeset)})
  end

  def call(conn, {:error, %Lightning.Extensions.Message{} = message}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: message.text})
  end

  # The OIDC token endpoint's error body, a string or a map.
  def call(conn, {:error, error}) when is_binary(error) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: error})
  end

  def call(conn, {:error, error}) when is_map(error) do
    conn
    |> put_status(:unauthorized)
    |> put_view(LightningWeb.ErrorView)
    |> render(:"401", error: error)
  end
end
