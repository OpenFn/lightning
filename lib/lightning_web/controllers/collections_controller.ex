defmodule LightningWeb.CollectionsController do
  use LightningWeb, :controller

  alias Ecto.Changeset
  alias Lightning.Collections
  alias Lightning.Policies.Permissions
  alias Lightning.Run
  alias Lightning.Scope
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Filters.Cursor
  alias LightningWeb.API.Problem

  action_fallback FallbackController

  require Logger

  @max_chunk_size 100

  def put(conn, %{"name" => name, "key" => key}) do
    with {:ok, collection} <- fetch_collection(conn, name, :put_collection_item) do
      case Collections.put(collection, key, conn.body_params["value"]) do
        :ok ->
          json(conn, %{upserted: 1, error: nil})

        {:error, %Changeset{} = changeset} ->
          {:error, Errors.problem(changeset, %{}, path: [:key])}

        error ->
          error
      end
    end
  end

  def put_all(conn, %{"name" => name}) do
    with {:ok, collection} <- fetch_collection(conn, name, :put_collection_item),
         {:ok, count} <-
           Collections.put_all(collection, conn.body_params["items"]) do
      json(conn, %{upserted: count, error: nil})
    end
  end

  def get(conn, %{"name" => name, "key" => key}) do
    with {:ok, collection} <- fetch_collection(conn, name, :access_collection) do
      case Collections.get(collection, key) do
        nil -> resp(conn, :no_content, "")
        item -> json(conn, item)
      end
    end
  end

  # A missing item is a success with nothing in it (error-format spec §10).
  def delete(conn, %{"name" => name, "key" => key}) do
    with {:ok, collection} <-
           fetch_collection(conn, name, :delete_collection_item) do
      case Collections.delete(collection, key) do
        :ok -> json(conn, %{key: key, deleted: 1})
        {:error, :not_found} -> json(conn, %{key: key, deleted: 0})
      end
    end
  end

  def delete_all(conn, %{"name" => name} = params) do
    with {:ok, collection} <-
           fetch_collection(conn, name, :delete_all_collection_items) do
      key_param = params["key"]
      {:ok, n} = Collections.delete_all(collection, key_param)
      json(conn, %{key: key_param, deleted: n})
    end
  end

  def stream(conn, %{"name" => name}) do
    with {:ok, collection} <- fetch_collection(conn, name, :access_collection),
         {:ok, filters} <-
           stream_filters(Map.delete(conn.query_params, "project_id")) do
      {key_pattern, filters} = Map.pop(filters, :key)
      response_limit = filters.limit

      # One item past the limit tells the response whether to carry a cursor.
      items_stream =
        Collections.stream_all(
          collection,
          %{filters | limit: response_limit + 1},
          key_pattern
        )

      case stream_chunked(conn, items_stream, response_limit) do
        {:error, conn} -> conn
        {:ok, conn} -> conn
      end
    end
  end

  defp fetch_collection(conn, name, action) do
    subject = conn.assigns.subject

    with {:ok, collection} <-
           Collections.resolve_collection(
             subject,
             name,
             conn.query_params["project_id"]
           ),
         :ok <- authorize(subject, action, collection),
         do: {:ok, collection}
  end

  # A run is never asked Lightning.Policies.Collections. It may do anything to
  # its own project's collections, and resolve_collection/3 finds it no others.
  defp authorize(%Run{}, _action, _collection), do: :ok

  defp authorize(actor, action, collection) do
    with {:ok, scope} <- Scope.fetch(actor, collection),
         do: Permissions.permit(:collections, action, scope, collection)
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

  # Every bad parameter is reported, in name order, and none is quoted
  # (error-format spec §9.4).
  defp stream_filters(query_params) do
    {params, unknown} =
      Map.split(query_params, Filters.collection_item_parameters())

    params
    |> Filters.collection_items()
    |> Errors.refuse_parameters()
    |> refuse_unknown(Map.keys(unknown))
  end

  defp refuse_unknown({:ok, _filters} = ok, []), do: ok

  defp refuse_unknown(result, unknown) do
    refused =
      case result do
        {:ok, _filters} -> []
        {:error, %Problem{errors: errors}} -> errors
      end

    entries =
      for name <- unknown,
          do:
            Errors.entry(
              {:parameter, name},
              {"is not accepted", code: :unknown_key}
            )

    {:error,
     Problem.new(:invalid_parameter,
       errors: Enum.sort_by(refused ++ entries, & &1.parameter)
     )}
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
    cursor = if cursor_data, do: Cursor.encode(cursor_data)

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
end
