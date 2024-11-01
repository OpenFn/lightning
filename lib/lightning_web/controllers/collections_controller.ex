defmodule LightningWeb.CollectionsController do
  use LightningWeb, :controller

  alias Lightning.Collections
  alias Lightning.Policies.Permissions
  alias Lightning.Repo

  action_fallback LightningWeb.FallbackController

  @max_chunk_size 50

  @stream_limit Application.compile_env!(
                  :lightning,
                  Lightning.CollectionsController
                )[
                  :stream_limit
                ]
  @cursor_count @stream_limit + 1

  # TODO: move this into a plug or router pipeline
  # the logic _is_ different to what UserAuth does
  # so for now we've made a catch all for the new behavior
  def action(conn, _options) do
    with {:ok, bearer_token} <- get_bearer_token(conn),
         {:ok, claims} <- Lightning.Tokens.verify(bearer_token),
         conn <- conn |> assign(:claims, claims) |> put_subject() do
      apply(__MODULE__, action_name(conn), [conn, conn.params])
    else
      {:error, _} ->
        deny_access(conn)
    end
  end

  defp get_bearer_token(conn) do
    conn
    |> get_req_header("authorization")
    |> case do
      ["Bearer " <> bearer] -> {:ok, bearer}
      _ -> {:error, "Bearer Token not found"}
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

  #
  # Controller starts here
  #
  def put(conn, %{"name" => col_name, "key" => key, "value" => value}) do
    with {:ok, collection} <- Collections.get_collection(col_name),
         :ok <- authorize(conn, collection) do
      case Collections.put(collection, key, value) do
        :ok ->
          json(conn, %{upserted: 1, error: nil})

        {:error, _reason} ->
          json(conn, %{upserted: 0, error: "Format error"})
      end
    end
  end

  def put_all(conn, %{"name" => col_name, "items" => items}) do
    with {:ok, collection} <- Collections.get_collection(col_name),
         :ok <- authorize(conn, collection) do
      case Collections.put_all(collection, items) do
        {:ok, count} ->
          json(conn, %{upserted: count, error: nil})

        :error ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{upserted: 0, error: "Database Error"})
      end
    end
  end

  def get(conn, %{"name" => col_name, "key" => key}) do
    with {:ok, collection} <- Collections.get_collection(col_name),
         :ok <- authorize(conn, collection) do
      case Collections.get(collection, key) do
        nil ->
          conn
          |> put_status(:no_content)
          |> json(nil)

        item ->
          json(conn, item)
      end
    end
  end

  def delete(conn, %{"name" => col_name, "key" => key}) do
    with {:ok, collection} <- Collections.get_collection(col_name),
         :ok <- authorize(conn, collection) do
      case Collections.delete(collection, key) do
        :ok ->
          json(conn, %{keys: [key], deleted: 1, error: nil})

        {:error, :not_found} ->
          json(conn, %{keys: [key], deleted: 0, error: "Item Not Found"})
      end
    end
  end

  def stream(conn, %{"name" => col_name, "key" => key_pattern} = params) do
    with {:ok, collection} <- Collections.get_collection(col_name),
         :ok <- authorize(conn, collection),
         conn <- begin_chunking(conn) do
      case Repo.transact(fn ->
             collection
             |> Collections.stream_match(key_pattern, get_opts(params))
             |> Stream.chunk_every(@max_chunk_size)
             |> Stream.with_index()
             |> Enum.reduce_while(start_items_chunking(conn), &send_chunk/2)
             |> finish_chunking()
           end) do
        {:error, conn} -> conn
        {:ok, conn} -> conn
      end
    end
  end

  def stream(conn, %{"name" => col_name} = params) do
    with {:ok, collection} <- Collections.get_collection(col_name),
         :ok <- authorize(conn, collection),
         conn <- begin_chunking(conn) do
      case Repo.transact(fn ->
             collection
             |> Collections.stream_all(get_opts(params))
             |> Stream.chunk_every(@max_chunk_size)
             |> Stream.with_index()
             |> Enum.reduce_while(start_items_chunking(conn), &send_chunk/2)
             |> finish_chunking()
           end) do
        {:error, conn} -> conn
        {:ok, conn} -> conn
      end
    end
  end

  defp get_opts(params) do
    [limit: @stream_limit + 1]
    |> then(fn opts ->
      if cursor = params["cursor"] do
        Keyword.put(opts, :cursor, Base.decode64!(cursor))
      else
        opts
      end
    end)
  end

  defp begin_chunking(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_chunked(200)
  end

  defp start_items_chunking(conn) do
    with {:ok, conn} <- Plug.Conn.chunk(conn, ~S({"items": [)),
         do: {conn, {%{inserted_at: nil}, 0}}
  end

  defp finish_chunking({conn, {%{inserted_at: last_inserted_at}, count}}) do
    cursor =
      if count > @stream_limit do
        last_inserted_at |> DateTime.to_iso8601() |> Base.encode64()
      end

    Plug.Conn.chunk(conn, ~S(], "cursor":) <> Jason.encode!(cursor) <> "}")
  end

  defp finish_chunking({:error, conn}), do: {:error, conn}

  defp send_chunk(_chunk_items, {:error, conn}) do
    {:halt, {:error, conn}}
  end

  defp send_chunk({chunk_items, 0}, {conn, {_last, _count}}) do
    last = List.last(chunk_items)

    chunk_items
    |> Enum.map_join(",", &Jason.encode!/1)
    |> send_chunk_and_iterate(last, length(chunk_items), conn)
  end

  defp send_chunk({[_item | _chunk_items], _i}, {conn, {last, @stream_limit}}) do
    {:halt, {conn, {last, @cursor_count}}}
  end

  defp send_chunk({chunk_items, _i}, {conn, {_last, count}}) do
    taken_items = Enum.take(chunk_items, @stream_limit - count)
    last = List.last(taken_items)

    taken_items
    |> Enum.map_join(",", &Jason.encode!/1)
    |> then(fn items_chunk ->
      "," <> items_chunk
    end)
    |> send_chunk_and_iterate(last, length(chunk_items) + count, conn)
  end

  defp send_chunk_and_iterate(chunk, last, count, conn) do
    case Plug.Conn.chunk(conn, chunk) do
      {:ok, conn} ->
        if count > @stream_limit do
          {:halt, {conn, {last, @cursor_count}}}
        else
          {:cont, {conn, {last, count}}}
        end

      {:error, :closed} ->
        {:halt, {:error, conn}}
    end
  end
end
