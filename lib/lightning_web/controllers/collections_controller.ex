defmodule LightningWeb.CollectionsController do
  use LightningWeb, :controller

  alias Lightning.Collections
  alias Lightning.Policies.Permissions
  alias Lightning.Repo

  action_fallback LightningWeb.FallbackController

  @max_chunk_size 50

  @default_limit Application.compile_env!(:lightning, __MODULE__)[:stream_limit]

  @valid_params [
    "key",
    "cursor",
    "limit",
    "created_after",
    "created_before"
  ]

  require Logger

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
          json(conn, %{key: key, deleted: 1, error: nil})

        {:error, :not_found} ->
          json(conn, %{key: key, deleted: 0, error: "Item Not Found"})
      end
    end
  end

  def delete_all(conn, %{"name" => col_name} = params) do
    with {:ok, collection} <- Collections.get_collection(col_name),
         :ok <- authorize(conn, collection) do
      key_param = params["key"]

      case Collections.delete_all(collection, key_param) do
        {:ok, n} ->
          json(conn, %{key: key_param, deleted: n, error: nil})

        {:error, :not_found} ->
          json(conn, %{key: key_param, deleted: 0, error: "Items Not Found"})
      end
    end
  end

  def stream(conn, %{"name" => col_name, "key" => key_pattern}) do
    with {:ok, collection, filters, response_limit} <-
           validate_query(conn, col_name) do
      case Repo.transact(fn ->
             items_stream =
               Collections.stream_match(collection, key_pattern, filters)

             stream_chunked(conn, items_stream, response_limit)
           end) do
        {:error, conn} -> conn
        {:ok, conn} -> conn
      end
    end
  end

  def stream(conn, %{"name" => col_name}) do
    with {:ok, collection, filters, response_limit} <-
           validate_query(conn, col_name) do
      case Repo.transact(fn ->
             items_stream = Collections.stream_all(collection, filters)

             stream_chunked(conn, items_stream, response_limit)
           end) do
        {:error, conn} -> conn
        {:ok, conn} -> conn
      end
    end
  end

  defmodule ChunkAcc do
    defstruct conn: nil,
              count: 0,
              limit: 0,
              last: nil,
              cursor_data: nil
  end

  defp stream_chunked(conn, items_stream, response_limit) do
    with %{halted: false} = conn <- begin_chunking(conn) do
      items_stream
      |> Stream.chunk_every(@max_chunk_size)
      |> Stream.with_index()
      |> Enum.reduce_while(
        %ChunkAcc{conn: conn, limit: response_limit},
        &send_chunk/2
      )
      |> finish_chunking()
    end
  end

  defp validate_query(conn, col_name) do
    with {:ok, collection} <- Collections.get_collection(col_name),
         :ok <- authorize(conn, collection),
         query_params <-
           Enum.into(conn.query_params, %{
             "cursor" => nil,
             "limit" => "#{@default_limit}"
           }),
         {:ok, filters} <- validate_query_params(query_params) do
      # returns one more from db than the limit to determine if there are more items for the cursor
      db_query_filters = Map.update(filters, :limit, @default_limit, &(&1 + 1))
      response_limit = Map.fetch!(filters, :limit)

      {:ok, collection, db_query_filters, response_limit}
    end
  end

  defp validate_query_params(
         %{"cursor" => cursor, "limit" => limit} = query_params
       ) do
    with invalid_params when map_size(invalid_params) == 0 <-
           Map.drop(query_params, @valid_params),
         {:ok, cursor} <- validate_cursor(cursor),
         {limit, ""} <- Integer.parse(limit),
         valid_params <- Map.take(query_params, @valid_params) do
      filters =
        valid_params
        |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
        |> Map.put(:limit, limit)
        |> Map.put(:cursor, cursor)

      {:ok, filters}
    else
      _invalid ->
        {:error, :bad_request}
    end
  end

  defp validate_cursor(nil), do: {:ok, nil}

  defp validate_cursor(cursor) do
    with {:ok, decoded} <- Base.decode64(cursor),
         {:ok, datetime, _off} <- DateTime.from_iso8601(decoded) do
      {:ok, datetime}
    end
  end

  defp begin_chunking(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_chunked(200)
    |> Plug.Conn.chunk(~S({"items": [))
    |> case do
      {:ok, conn} ->
        conn

      {:error, reason} ->
        Logger.warning("Error starting chunking: #{inspect(reason)}")
        halt(conn)
    end
  end

  defp finish_chunking(%ChunkAcc{conn: conn, cursor_data: cursor_data}) do
    cursor =
      if cursor_data do
        cursor_data |> DateTime.to_iso8601() |> Base.encode64()
      end

    Plug.Conn.chunk(conn, ~S(], "cursor":) <> Jason.encode!(cursor) <> "}")
  end

  defp finish_chunking({:error, conn}), do: conn

  defp send_chunk({chunk_items, 0}, acc) do
    {taken_items, acc} = take_and_accumulate(chunk_items, acc)

    taken_items
    |> Enum.map_join(",", &Jason.encode!/1)
    |> send_chunk_and_iterate(acc)
  end

  defp send_chunk(
         {_chunk_items, _i},
         %ChunkAcc{count: sent_count, last: last, limit: limit} = acc
       )
       when sent_count == limit do
    {:halt, %ChunkAcc{acc | cursor_data: last.inserted_at}}
  end

  defp send_chunk({chunk_items, _i}, acc) do
    {taken_items, acc} = take_and_accumulate(chunk_items, acc)

    taken_items
    |> Enum.map_join(",", &Jason.encode!/1)
    |> then(fn items_chunk ->
      "," <> items_chunk
    end)
    |> send_chunk_and_iterate(acc)
  end

  defp take_and_accumulate(
         chunk_items,
         %ChunkAcc{count: sent_count, limit: limit} = acc
       ) do
    taken_items = Enum.take(chunk_items, limit - sent_count)
    last = List.last(taken_items)
    taken_count = length(taken_items)

    cursor_data =
      if taken_count > 0 and length(chunk_items) > taken_count do
        last.inserted_at
      end

    acc =
      struct(acc, %{
        count: sent_count + taken_count,
        last: last,
        cursor_data: cursor_data
      })

    {taken_items, acc}
  end

  defp send_chunk_and_iterate(
         chunk,
         %ChunkAcc{conn: conn, cursor_data: cursor_data} = acc
       ) do
    case Plug.Conn.chunk(conn, chunk) do
      {:ok, conn} ->
        if cursor_data do
          {:halt, %{acc | conn: conn}}
        else
          {:cont, %{acc | conn: conn}}
        end

      {:error, :closed} ->
        {:halt, {:error, conn}}
    end
  end
end
