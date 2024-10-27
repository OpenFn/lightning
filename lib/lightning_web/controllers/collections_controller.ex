defmodule LightningWeb.CollectionsController do
  use LightningWeb, :controller

  alias Lightning.Collections
  alias Lightning.Policies.Permissions
  alias Lightning.Repo

  action_fallback LightningWeb.FallbackController

  # TODO: move this into a plug or router pipeline
  # the logic _is_ different to what UserAuth does
  # so for now we've made a catch all for the new behavior
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

  # TODO: move this to somewhere more appropriate
  defp put_subject(conn) do
    conn.assigns.claims
    |> Lightning.Tokens.get_subject()
    |> then(fn subject ->
      conn |> assign(:subject, subject)
    end)
  end

  # TODO: move this to somewhere more appropriate
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
      conn =
        conn
        |> put_resp_content_type("application/json")
        |> send_chunked(200)

      collection_items = collection_stream(collection)

      # Take a stream of items (they enter the stream in batches of @query_all_limit)
      # we then chunk them into groups of 20 and send them to the client
      # since a chunk for each line seems a bit too many
      # we can play/adjust this number to see what works best
      wrap_array(collection_items, &Jason.encode!/1)
      |> Stream.chunk_every(20)
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

  defp wrap_array(stream, encode_func) do
    Stream.concat([
      ["["],
      stream
      |> Stream.map(fn item -> encode_func.(item) end)
      |> Stream.intersperse(","),
      ["]"]
    ])
  end

  defp collection_stream(collection) do
    Stream.unfold(nil, fn cursor ->
      Repo.transaction(fn ->
        Collections.stream_all(collection, cursor)
        |> Enum.to_list()
      end)
      |> case do
        {:ok, []} -> nil
        {:ok, items} -> {items, items |> List.last() |> Map.get(:updated_at)}
      end
    end)
    |> Stream.flat_map(& &1)
  end
end
