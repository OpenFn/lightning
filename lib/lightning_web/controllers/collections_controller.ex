defmodule LightningWeb.CollectionsController do
  use LightningWeb, :controller

  alias Lightning.Collections
  alias Lightning.Policies.Permissions

  action_fallback LightningWeb.FallbackController

  def action(conn, _options) do
    conn
    |> get_req_header("authorization")
    |> case do
      ["Bearer " <> bearer_token] -> {:ok, bearer_token}
      _ -> {:error, "Bearer Token not found"}
    end
    |> case do
      {:error, _} ->
        deny_access(conn)

      {:ok, bearer_token} ->
        bearer_token
        |> Lightning.Tokens.verify()
        |> case do
          {:ok, claims} ->
            conn =
              conn
              |> assign(:claims, claims)
              |> put_subject()

            apply(__MODULE__, action_name(conn), [conn, conn.params])

          {:error, _} ->
            deny_access(conn)
        end
    end
  end

  defp put_subject(conn) do
    conn.assigns.claims
    |> Lightning.Tokens.get_subject()
    |> then(fn subject ->
      conn |> assign(:subject, subject)
    end)
  end

  defp deny_access(conn) do
    conn
    |> put_status(:unauthorized)
    |> put_view(LightningWeb.ErrorView)
    |> render(:"401")
    |> halt()
  end

  defp authorize(conn, collection) do
    Permissions.can(
      Lightning.Policies.Collections,
      :access_collection,
      conn.assigns.subject,
      collection
    )
  end

  def all(conn, %{"collection" => collection}) do
    with {:ok, collection} <- Collections.get_collection(collection),
         :ok <- authorize(conn, collection) do
      conn = send_chunked(conn, 200)

      Stream.unfold(0, fn n ->
        if n < 10 do
          {n, n + 1}
        else
          nil
        end
      end)
      |> Enum.map(&Integer.to_string/1)
      |> Enum.reduce_while(conn, fn chunk, conn ->
        case Plug.Conn.chunk(conn, chunk) do
          {:ok, conn} ->
            {:cont, conn}

          {:error, :closed} ->
            {:halt, conn}
        end
      end)
    end
  end
end
