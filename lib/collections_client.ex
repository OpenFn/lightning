defmodule CollectionsClient do
  @moduledoc false

  @collection "tesla-demo"
  @personal_token ""

  def put_all(prefix, amount \\ 1_000) do
    items = Enum.map(1..amount, fn i ->
      i_str = String.pad_leading(to_string(i), 5, "0")
      %{
        key: "#{prefix}:foo#{i_str}:bar#{i_str}",
        value: Jason.encode!(%{
          someid1: "soo#{1_000_000 + i}",
          somefield1: "zar#{1_000_000 + i}",
          anotherfield1: "yaz#{1_000_000 + i}"
        })
      }
    end)

    @collection
    |> client()
    |> Tesla.post("/", %{items: items})
    |> case do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:error, reason} ->
        throw reason
    end
  end

  def delete_all do
    prefix = "rogerKey*"

    @collection
    |> client()
    |> Tesla.delete("/", query: [key: prefix])
    |> case do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:error, reason} ->
        throw reason
    end
  end

  def get_all(limit \\ nil) do
    # import Ecto.Query

    # alias Lightning.Collections.Collection
    # alias Lightning.Collections.Item
    # alias Lightning.Repo
    # %{id: collection_id} = Repo.get_by(Collection, name: @collection)
    # expected_count =
    #   from(i in Item, where: i.collection_id == ^collection_id)
    #   |> Repo.aggregate(:count)

    {first_items, initial_cursor} = get(nil, limit)

    Stream.unfold(initial_cursor, fn cursor ->
      if cursor do
        {_items, _cursor} = get(cursor, limit)
      end
    end)
    |> Enum.to_list()
    |> List.flatten()
    |> Enum.concat(first_items)
    |> Enum.count()
    |> IO.inspect(label: "count")

    # IO.inspect(expected_count, label: "expected count")
  end

  def get_match_all(limit \\ nil) do
    # import Ecto.Query

    # alias Lightning.Collections.Collection
    # alias Lightning.Collections.Item
    # alias Lightning.Repo
    # %{id: collection_id} = Repo.get_by(Collection, name: @collection)
    # expected_count =
    #   from(i in Item, where: i.collection_id == ^collection_id)
    #   |> Repo.aggregate(:count)

    {first_items, initial_cursor} = get_match("*", nil, limit)

    Stream.unfold(initial_cursor, fn cursor ->
      if cursor do
        {_items, _cursor} = get_match("*", cursor, limit)
      end
    end)
    |> Enum.to_list()
    |> List.flatten()
    |> Enum.concat(first_items)
    |> Enum.count()
    |> IO.inspect(label: "count")

    # IO.inspect(expected_count, label: "expected count")
  end

  defp get(cursor, limit) do
    query_params = if cursor, do: [cursor: cursor], else: []
    query_params = if limit, do: query_params ++ [limit: limit], else: query_params

    @collection
    |> client()
    |> Tesla.get("/", query: query_params)
    |> case do
      {:ok, %{body: %{"cursor" => cursor, "items" => items}}} ->
        {items, cursor}

      {:error, reason} ->
        throw reason
    end
  end


  defp get_match(key, cursor, limit) do
    query_params = if cursor, do: [cursor: cursor], else: []
    query_params = if limit, do: query_params ++ [limit: limit], else: query_params

    @collection
    |> client()
    |> Tesla.get("/", query: query_params)
    |> case do
      {:ok, %{body: %{"cursor" => cursor, "items" => items}}} ->
        {items, cursor}

      {:error, reason} ->
        throw reason
    end
  end

  defp client(collection) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "https://app.staging.openfn.org/collections/#{collection}"},
      # {Tesla.Middleware.BaseUrl, "http://localhost:4000/collections/#{collection}"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{@personal_token}"}]}
    ])
  end
end
