defmodule LightningWeb.CollectionsController do
  use LightningWeb, :controller

  action_fallback LightningWeb.FallbackController

  # get bearer token
  #   check if runtoken
  #     match collection against run
  #   check if user api token
  #     match collection against user

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
          {:ok, _claims} ->
            # determine is run belongs to project which owns the collection
            apply(__MODULE__, action_name(conn), [conn, conn.params])

          {:error, _} ->
            deny_access(conn)
        end
    end
  end

  defp deny_access(conn) do
    conn
    |> put_status(:unauthorized)
    |> put_view(LightningWeb.ErrorView)
    |> render(:"401")
    |> halt()
  end

  def all(conn, _params) do
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
