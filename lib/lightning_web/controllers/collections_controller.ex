defmodule LightningWeb.CollectionsController do
  use LightningWeb, :controller

  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Extensions.Message
  alias Lightning.Policies.Permissions

  action_fallback LightningWeb.FallbackController

  require Logger

  @max_chunk_size 100

  @limits Application.compile_env!(:lightning, __MODULE__)

  @default_stream_limit @limits[:default_stream_limit]
  @max_database_limit @limits[:max_database_limit]

  @timestamp_params [
    "created_after",
    "created_before",
    "updated_after",
    "updated_before"
  ]

  @valid_params ["key", "cursor", "limit" | @timestamp_params]

  @spec put(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def put(conn, %{"key" => key, "value" => value} = params) do
    with {:ok, collection} <- resolve(params),
         :ok <- authorize(conn, collection),
         :ok <- Collections.put(collection, key, value) do
      json(conn, %{upserted: 1, error: nil})
    else
      {:error, %Ecto.Changeset{}} ->
        json(conn, %{upserted: 0, error: "Format error"})

      error ->
        maybe_handle_limit_error(conn, error)
    end
  end

  def put(conn, _params), do: missing_body(conn, "value")

  @spec put_all(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def put_all(conn, %{"items" => items} = params) do
    with {:ok, collection} <- resolve(params),
         :ok <- authorize(conn, collection),
         {:ok, count} <- Collections.put_all(collection, items) do
      json(conn, %{upserted: count, error: nil})
    else
      {:error, :duplicate_key} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{upserted: 0, error: "Duplicate key found"})

      error ->
        maybe_handle_limit_error(conn, error)
    end
  end

  def put_all(conn, _params), do: missing_body(conn, "items")

  @spec get(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def get(conn, %{"key" => key} = params) do
    with {:ok, collection} <- resolve(params),
         :ok <- authorize(conn, collection) do
      case Collections.get(collection, key) do
        nil -> resp(conn, :no_content, "")
        item -> json(conn, item)
      end
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"key" => key} = params) do
    with {:ok, collection} <- resolve(params),
         :ok <- authorize(conn, collection) do
      case Collections.delete(collection, key) do
        :ok ->
          json(conn, %{key: key, deleted: 1, error: nil})

        {:error, :not_found} ->
          json(conn, %{key: key, deleted: 0, error: "Item Not Found"})
      end
    end
  end

  @spec delete_all(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete_all(conn, params) do
    with {:ok, collection} <- resolve(params),
         :ok <- authorize(conn, collection) do
      key_param = params["key"]
      {:ok, n} = Collections.delete_all(collection, key_param)
      json(conn, %{key: key_param, deleted: n, error: nil})
    end
  end

  @spec stream(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def stream(conn, params) do
    with {:ok, collection} <- resolve(params),
         :ok <- authorize(conn, collection),
         {:ok, filters} <- parse_query_params(conn.query_params) do
      key_pattern = conn.query_params["key"]
      items_stream = stream_all_in_chunks(collection, filters, key_pattern)
      response_limit = Map.fetch!(filters, :limit)

      case stream_chunked(conn, items_stream, response_limit) do
        {:error, conn} -> conn
        {:ok, conn} -> conn
      end
    end
  end

  @doc """
  Browser-pipeline download for a project-scoped collection.

  Always v2 since the UI links to project-scoped download URLs.
  """
  @spec download(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def download(conn, %{"project_id" => project_id, "name" => name}) do
    with {:ok, collection} <- Collections.get_collection(project_id, name),
         :ok <- authorize(conn, collection) do
      items_stream =
        stream_all_in_chunks(
          collection,
          %{cursor: nil, limit: @max_database_limit + 1},
          nil
        )

      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{name}.json")
      )
      |> stream_as_json_array(items_stream)
    end
  end

  # Resolves a collection by project + name when project_id is present, or by
  # name alone otherwise. Any `{:error, reason}` is rendered by the fallback
  # controller (404 for `:not_found`, 409 for `:conflict`).
  @spec resolve(map()) :: {:ok, Collection.t()} | {:error, atom()}
  defp resolve(%{"project_id" => project_id, "name" => name}),
    do: Collections.get_collection(project_id, name)

  defp resolve(%{"name" => name}),
    do: Collections.get_collection(name)

  defp authorize(conn, collection) do
    subject = conn.assigns[:subject] || conn.assigns[:current_user]

    Permissions.can(
      Lightning.Policies.Collections,
      :access_collection,
      subject,
      collection
    )
  end

  defp missing_body(conn, field) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Missing required field: #{field}"})
  end

  defp stream_as_json_array(conn, items_stream) do
    conn = send_chunked(conn, 200)
    {:ok, conn} = Plug.Conn.chunk(conn, "[")

    {conn, _first?} =
      Enum.reduce_while(items_stream, {conn, true}, fn item, {conn, first?} ->
        prefix = if first?, do: "", else: ","

        case Plug.Conn.chunk(conn, prefix <> Jason.encode!(item)) do
          {:ok, conn} -> {:cont, {conn, false}}
          {:error, :closed} -> {:halt, {conn, false}}
        end
      end)

    {:ok, conn} = Plug.Conn.chunk(conn, "]")
    conn
  end

  # Streams records from database without depending on holding a transaction from database pool.
  # It streams one more than the limit to allow determining if there are more items for the response cursor.
  defp stream_all_in_chunks(collection, %{limit: limit} = filters, key_pattern)
       when limit <= @max_database_limit do
    filters = Map.put(filters, :limit, limit + 1)

    Collections.get_all(collection, filters, key_pattern)
  end

  defp stream_all_in_chunks(
         collection,
         %{cursor: initial_cursor} = filters,
         key_pattern
       ) do
    filters = Map.put(filters, :limit, @max_database_limit + 1)

    Stream.unfold(initial_cursor, fn cursor ->
      filters = Map.put(filters, :cursor, cursor)

      case Collections.get_all(collection, filters, key_pattern) do
        [] -> nil
        list -> {list, List.last(list).id}
      end
    end)
    |> Stream.flat_map(& &1)
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

  defp parse_query_params(query_params) do
    query_params
    |> Enum.into(%{
      "cursor" => nil,
      "limit" => "#{@default_stream_limit}"
    })
    |> validate_query_params()
  end

  defp validate_query_params(
         %{"cursor" => cursor, "limit" => limit} = query_params
       ) do
    with invalid_params when map_size(invalid_params) == 0 <-
           Map.drop(query_params, @valid_params),
         {:ok, cursor} <- validate_cursor(cursor),
         {limit, ""} <- Integer.parse(limit),
         :ok <- validate_timestamps(query_params) do
      filters =
        query_params
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
         {id, ""} <- Integer.parse(decoded) do
      {:ok, id}
    end
  end

  defp validate_timestamps(params) do
    params
    |> Map.take(@timestamp_params)
    |> Enum.all?(fn {_key, value} ->
      match?({:ok, _dt, _time}, DateTime.from_iso8601(value))
    end)
    |> case do
      true -> :ok
      false -> :error
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
        Base.encode64(to_string(cursor_data))
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
    {:halt, %ChunkAcc{acc | cursor_data: last.id}}
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
        last.id
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

  defp maybe_handle_limit_error(
         conn,
         {:error, :exceeds_limit, %Message{text: error_msg}}
       ) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{upserted: 0, error: error_msg})
  end

  defp maybe_handle_limit_error(_conn, error), do: error
end
