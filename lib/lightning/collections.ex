defmodule Lightning.Collections do
  @moduledoc """
  Access to collections of unique key-value pairs shared across multiple workflows.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Lightning.Accounts.User
  alias Lightning.Collections.Audit
  alias Lightning.Collections.Collection
  alias Lightning.Collections.Item
  alias Lightning.Config
  alias Lightning.Extensions.Message
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.Scope
  alias Lightning.Services.CollectionHook

  @doc """
  Returns the list of collections with optional ordering and preloading.

  ## Parameters

    - `opts`: A keyword list of options.
      - `:order_by` (optional): The field by which to order the results. Default is `[asc: :name]`.
      - `:preload` (optional): A list of associations to preload. Default is `[:project]`.

  ## Examples

      iex> list_collections()
      [%Collection{}, ...]

      iex> list_collections(order_by: [asc: :inserted_at], preload: [:project, :user])
      [%Collection{}, ...]

  ## Returns

    - A list of `%Collection{}` structs, preloaded and ordered as specified.
  """
  @spec list_collections(keyword()) :: [Collection.t()]
  def list_collections(opts \\ []) do
    order_by = Keyword.get(opts, :order_by, asc: :name)
    preload = Keyword.get(opts, :preload, [:project])

    Repo.all(from(c in Collection, order_by: ^order_by, preload: ^preload))
  end

  @spec list_project_collections(Project.t(), keyword()) ::
          [Collection.t(), ...] | []
  def list_project_collections(%Project{id: project_id}, opts \\ []) do
    order_by = Keyword.get(opts, :order_by, asc: :name)

    query =
      from c in Collection,
        where: c.project_id == ^project_id,
        order_by: ^order_by

    Repo.all(query)
  end

  @doc "The collection with primary key `id`, or `nil`."
  @spec get_collection_by_id(Ecto.UUID.t()) :: Collection.t() | nil
  def get_collection_by_id(id), do: Repo.get(Collection, id)

  @doc """
  The collection with primary key `id` in the project `project_id`, or
  `{:error, :not_found}` when the id is malformed or no collection in that
  project has it.
  """
  @spec get_collection_for_project(Ecto.UUID.t(), term()) ::
          {:ok, Collection.t()} | {:error, :not_found}
  def get_collection_for_project(project_id, id) do
    if Lightning.Validators.valid_uuid?(id) do
      Collection
      |> where(id: ^id, project_id: ^project_id)
      |> Repo.fetch_one()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Looks up a collection scoped to a specific project.

  Unambiguous by construction: there is at most one collection with a given
  name in a project.
  """
  @spec get_collection(Ecto.UUID.t(), String.t()) ::
          {:ok, Collection.t()} | {:error, :not_found}
  def get_collection(project_id, name) do
    case Repo.get_by(Collection, project_id: project_id, name: name) do
      nil -> {:error, :not_found}
      collection -> {:ok, collection}
    end
  end

  @doc """
  The collection `name` names for `subject`, among the collections it has
  standing on: a user's standing is a project role or support access, a run's
  is its own project. `project_id`, as the request sent it, narrows the search
  to one project; one that isn't a UUID names nothing.

  A collection the subject has no standing on never counts, so neither
  `{:error, :not_found}` nor `{:error, :ambiguous_name}` says anything about
  projects it can't see. Whether the subject may act on the collection is still
  the policy's call.
  """
  @spec resolve_collection(
          User.t() | Run.t(),
          String.t(),
          String.t() | nil
        ) ::
          {:ok, Collection.t()} | {:error, :not_found | :ambiguous_name}
  def resolve_collection(subject, name, project_id \\ nil) do
    case named(name, project_id) do
      nil -> {:error, :not_found}
      query -> query |> standing_collections(subject) |> only_one()
    end
  end

  defp only_one([]), do: {:error, :not_found}
  defp only_one([collection]), do: {:ok, collection}
  defp only_one([_ | _]), do: {:error, :ambiguous_name}

  defp named(name, nil), do: from(c in Collection, where: c.name == ^name)

  defp named(name, project_id) do
    if Lightning.Validators.valid_uuid?(project_id),
      do: from(c in named(name, nil), where: c.project_id == ^project_id)
  end

  defp standing_collections(query, %Run{} = run) do
    project_id =
      run |> Ecto.assoc([:work_order, :workflow]) |> select([w], w.project_id)

    query |> where([c], c.project_id in subquery(project_id)) |> Repo.all()
  end

  defp standing_collections(query, %User{} = user) do
    collections = Repo.all(query)
    scopes = Scope.fetch_all(user, Enum.map(collections, & &1.project_id))

    standing =
      for {project_id, scope} <- scopes,
          Scope.has_standing?(scope),
          into: MapSet.new(),
          do: project_id

    Enum.filter(collections, &(&1.project_id in standing))
  end

  @doc """
  Creates a collection, recording `actor` as having created it.

  Returns `{:error, :exceeds_limit, message}`, and writes nothing, when the
  collection hook refuses the create.

  ## Options

    * `:id` - The id to create the collection under, rather than a new one

  ## Examples

      iex> create_collection(%{"name" => "patients", "project_id" => project_id}, actor)
      {:ok, %Collection{}}

      iex> create_collection(%{"name" => nil, "project_id" => project_id}, actor)
      {:error, %Ecto.Changeset{}}
  """
  @spec create_collection(map(), Lightning.Actor.t(), [{:id, Ecto.UUID.t()}]) ::
          {:ok, Collection.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :exceeds_limit, Message.t()}
  def create_collection(attrs, actor, opts \\ []) do
    changeset = Collection.changeset(%Collection{id: opts[:id]}, attrs)

    Multi.new()
    |> Multi.run(:limiter, fn _repo, _changes ->
      case CollectionHook.handle_create(attrs) do
        :ok -> {:ok, nil}
        {:error, :exceeds_limit, message} -> {:error, message}
      end
    end)
    |> Multi.insert(:create, changeset)
    |> Multi.insert(:audit, fn %{create: collection} ->
      Audit.event("created", collection.id, actor, changeset)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{create: collection}} ->
        {:ok, collection}

      {:error, :limiter, message, _changes} ->
        {:error, :exceeds_limit, message}

      {:error, :create, changeset, _changes} ->
        {:error, changeset}

      {:error, :audit, changeset, _changes} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
    end
  end

  @doc """
  Renames a collection, recording `actor` as having renamed it. A write that
  leaves the name as it was records nothing.

  Returns `{:error, :concurrent_edit}` when another request deleted the
  collection while this one ran.

  ## Examples

      iex> update_collection(collection, %{"name" => "patients"}, actor)
      {:ok, %Collection{}}

      iex> update_collection(collection, %{"name" => nil}, actor)
      {:error, %Ecto.Changeset{}}
  """
  @spec update_collection(Collection.t(), map(), Lightning.Actor.t()) ::
          {:ok, Collection.t()} | {:error, Ecto.Changeset.t() | :concurrent_edit}
  def update_collection(collection, attrs, actor) do
    changeset = Collection.rename_changeset(collection, attrs)

    Multi.new()
    |> Multi.update(:update, changeset, stale_error_field: :id)
    |> then(fn multi ->
      case Audit.event("updated", collection.id, actor, changeset) do
        :no_changes -> multi
        event -> Multi.insert(multi, :audit, event)
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{update: collection}} ->
        {:ok, collection}

      {:error, :update, %Changeset{errors: [id: {_, stale: true}]}, _} ->
        {:error, :concurrent_edit}

      {:error, :update, changeset, _changes} ->
        {:error, changeset}

      {:error, :audit, changeset, _changes} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
    end
  end

  @spec delete_collection(Ecto.UUID.t()) ::
          {:ok, Collection.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :not_found}
  def delete_collection(collection_id) do
    case get_collection_by_id(collection_id) do
      nil ->
        {:error, :not_found}

      collection ->
        Repo.transact(fn ->
          :ok =
            CollectionHook.handle_delete(
              collection.project_id,
              collection.byte_size_sum
            )

          Repo.delete(collection)
        end)
    end
  end

  @spec get(Collection.t(), String.t()) :: Item.t() | nil
  def get(%{id: collection_id}, key) do
    Repo.get_by(Item, collection_id: collection_id, key: key)
  end

  @spec get_all(Collection.t(), Enum.t(), String.t() | nil) :: Enum.t()
  def get_all(%{id: collection_id}, params, key_pattern \\ nil) do
    params = Map.new(params)
    cursor = Map.get(params, :cursor)
    limit = Map.fetch!(params, :limit)

    collection_id
    |> all_query(cursor, limit)
    |> filter_by_inserted_at(params)
    |> filter_by_updated_at(params)
    |> then(fn query ->
      if key_pattern do
        where(query, [i], like(i.key, ^format_pattern(key_pattern)))
      else
        query
      end
    end)
    |> Repo.all()
  end

  @doc """
  Every item `get_all/3` would find for `filters` and `key_pattern`, from
  `filters`' cursor on and at most `filters`' `:limit` of them when it has one.
  Items are read a page at a time, so that no transaction is held while the
  caller consumes the stream.
  """
  @spec stream_all(Collection.t(), map(), String.t() | nil) :: Enumerable.t()
  def stream_all(collection, filters, key_pattern \\ nil) do
    {limit, filters} = Map.pop(filters, :limit)
    max_page_size = Config.collections_stream_page_size()
    page_size = if limit, do: min(limit, max_page_size), else: max_page_size
    filters = Map.put(filters, :limit, page_size)

    Map.get(filters, :cursor)
    |> Stream.unfold(fn
      :drained ->
        nil

      cursor ->
        case get_all(collection, Map.put(filters, :cursor, cursor), key_pattern) do
          [] -> nil
          page when length(page) < page_size -> {page, :drained}
          page -> {page, List.last(page).id}
        end
    end)
    |> Stream.flat_map(& &1)
    |> then(&if(limit, do: Stream.take(&1, limit), else: &1))
  end

  @doc """
  Writes `value` under `key`. The item is validated before the collection hook
  is asked about its size, so an invalid item is refused as invalid, never as
  over a limit.

  A bad value or a key that can't be stored is refused with one changeset
  holding every error. The key's errors are on `:key`.
  """
  @spec put(Collection.t(), String.t(), term()) ::
          :ok
          | {:error, Changeset.t()}
          | {:error, :exceeds_limit, Message.t()}
  def put(collection, key, value) do
    item = get(collection, key) || %Item{collection_id: collection.id}

    changeset =
      item
      |> Item.value_changeset(%{value: value})
      |> Item.key_changeset(%{key: key})

    if changeset.valid?,
      do: upsert_item(collection, changeset),
      else: {:error, changeset}
  end

  @doc """
  Writes every item of `items`, the request's list of
  `%{"key" => _, "value" => _}` objects, in one transaction.

  A list with any bad item is refused whole, writing nothing, with a changeset
  whose errors carry each bad item's position in `items` as their `key:`. An
  item is bad if it isn't an object or fails validation, or if an earlier item
  already uses its key, and then the error names the earlier one. The
  collection hook is asked about the size only once every item is valid.
  """
  @spec put_all(Collection.t(), term()) ::
          {:ok, non_neg_integer()}
          | {:error, Changeset.t()}
          | {:error, :exceeds_limit, Message.t()}
  def put_all(collection, items) do
    with {:ok, items} <- validate_items(collection, items) do
      insert_items(collection, items)
    end
  end

  defp validate_items(collection, items) when is_list(items) do
    {checked, _firsts} =
      items
      |> Enum.with_index()
      |> Enum.map_reduce(%{}, fn {item, index}, firsts ->
        key = request_key(item)
        first = if key, do: Map.get(firsts, key)
        firsts = if key, do: Map.put_new(firsts, key, index), else: firsts

        {check_item(collection, item, index, first), firsts}
      end)

    case Enum.flat_map(checked, fn {_item, errors} -> errors end) do
      [] -> {:ok, Enum.map(checked, fn {item, []} -> item end)}
      errors -> refuse_items(errors)
    end
  end

  defp validate_items(_collection, nil),
    do: refuse_items(items: {"can't be blank", validation: :required})

  defp validate_items(_collection, _items),
    do:
      refuse_items(
        items: {"is invalid", validation: :cast, type: {:array, :map}}
      )

  defp request_key(%{"key" => key}) when is_binary(key), do: key
  defp request_key(_item), do: nil

  # `{item, errors}`, each error placed at this item's position by `key:`.
  # `first` is the position of the earlier item holding the same key.
  defp check_item(collection, item, index, first) when is_map(item) do
    changeset =
      Item.changeset(
        %Item{collection_id: collection.id},
        Map.take(item, ["key", "value"])
      )

    own =
      for {field, {message, opts}} <- Enum.reverse(changeset.errors),
          do: {:items, {message, [{:key, ["items", index, field]} | opts]}}

    duplicate =
      if first,
        do: [
          items:
            {"names the same key as #/items/#{first}",
             code: :duplicate, key: ["items", index, "key"]}
        ],
        else: []

    {Changeset.apply_changes(changeset), own ++ duplicate}
  end

  defp check_item(_collection, _item, index, _first) do
    {nil,
     [
       items:
         {"is invalid", key: ["items", index], validation: :cast, type: :map}
     ]}
  end

  # A changeset holds its errors newest first, as add_error leaves them.
  defp refuse_items(errors) do
    changeset = Changeset.change({%{}, %{items: {:array, :map}}})
    {:error, %{changeset | errors: Enum.reverse(errors), valid?: false}}
  end

  defp insert_items(collection, items) do
    now = DateTime.utc_now()

    {item_list, {key_list, new_used_mem}} =
      Enum.map_reduce(items, {[], 0}, fn %Item{key: key, value: value},
                                         {key_list, mem_used} ->
        {
          %{
            collection_id: collection.id,
            key: key,
            value: value,
            inserted_at: now,
            updated_at: now
          },
          {
            [key | key_list],
            mem_used + byte_size(key) + byte_size(value)
          }
        }
      end)

    Multi.new()
    |> Multi.one(
      :items_used_mem,
      from(c in Item,
        where: c.collection_id == ^collection.id and c.key in ^key_list,
        select: fragment("sum(octet_length(key) + octet_length(value))::bigint")
      )
    )
    |> Multi.run(:increment_size, fn _repo, %{items_used_mem: items_used_mem} ->
      {:ok, new_used_mem - (items_used_mem || 0)}
    end)
    |> Multi.run(:hook, fn _repo, %{increment_size: increment_size} ->
      handle_put_items(collection, increment_size)
    end)
    |> Multi.insert_all(:items, Item, item_list,
      conflict_target: [:collection_id, :key],
      on_conflict: {:replace, [:value, :updated_at]}
    )
    |> Multi.update_all(
      :collection,
      fn %{increment_size: increment_size} ->
        increment = [byte_size_sum: increment_size]

        from(c in Collection,
          where: c.id == ^collection.id,
          update: [inc: ^increment]
        )
      end,
      []
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{items: {count, nil}}} -> {:ok, count}
      {:error, :hook, message, _changes} -> {:error, :exceeds_limit, message}
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  end

  @spec delete(Collection.t(), String.t()) :: :ok | {:error, :not_found}
  def delete(collection, key) do
    case get(collection, key) do
      nil -> {:error, :not_found}
      item -> delete_item(item)
    end
  end

  @spec delete_all(Collection.t(), String.t() | nil) :: {:ok, non_neg_integer()}
  def delete_all(collection, key_pattern \\ nil) do
    items_query =
      from(i in Item, where: i.collection_id == ^collection.id)
      |> then(fn query ->
        case key_pattern do
          nil -> query
          pattern -> where(query, [i], like(i.key, ^format_pattern(pattern)))
        end
      end)

    Multi.new()
    |> Multi.one(
      :items_used_mem,
      select(
        items_query,
        [i],
        fragment("sum(octet_length(key) + octet_length(value))::bigint")
      )
    )
    |> Multi.merge(fn
      %{items_used_mem: nil} ->
        Multi.put(Multi.new(), :delete, {0, nil})

      %{items_used_mem: items_used_mem} ->
        update_count_query =
          if key_pattern && items_used_mem do
            increment = [byte_size_sum: -items_used_mem]

            from(c in Collection,
              where: c.id == ^collection.id,
              update: [inc: ^increment]
            )
          else
            from(c in Collection,
              where: c.id == ^collection.id,
              update: [set: [byte_size_sum: 0]]
            )
          end

        Multi.new()
        |> Multi.run(:hook, fn _repo, _changes ->
          handle_delete_items(collection, items_used_mem)
        end)
        |> Multi.delete_all(:delete, items_query)
        |> Multi.update_all(:update_collection, update_count_query, [])
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{delete: {count, nil}}} -> {:ok, count}
      _other_error -> {:ok, 0}
    end
  end

  defp upsert_item(collection, %Changeset{data: %Item{} = stored} = changeset) do
    %Item{key: key, value: value} = Changeset.apply_changes(changeset)

    increment_size =
      if is_nil(stored.value),
        do: byte_size(key) + byte_size(value),
        else: byte_size(value) - byte_size(stored.value)

    Multi.new()
    |> Multi.run(:limiter, fn _repo, _changes ->
      handle_put_items(collection, increment_size)
    end)
    |> Multi.insert(:item, changeset,
      conflict_target: [:collection_id, :key],
      on_conflict: [set: [value: value, updated_at: DateTime.utc_now()]]
    )
    |> Multi.update_all(
      :collection,
      fn %{item: %{collection_id: collection_id}} ->
        from(c in Collection,
          where: c.id == ^collection_id,
          update: [inc: ^[byte_size_sum: increment_size]]
        )
      end,
      []
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
      {:error, :limiter, message, _changes} -> {:error, :exceeds_limit, message}
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  end

  defp delete_item(%{collection_id: collection_id, key: key, value: value}) do
    Multi.new()
    |> Multi.one(
      :collection,
      from(c in Collection, where: c.id == ^collection_id)
    )
    |> Multi.run(:hook, fn _repo, %{collection: collection} ->
      handle_delete_items(collection, byte_size(key) + byte_size(value))
    end)
    |> Multi.delete_all(:item, fn _no_change ->
      from(i in Item, where: i.collection_id == ^collection_id and i.key == ^key)
    end)
    |> Multi.update_all(
      :update_collection,
      fn _changes ->
        increment = [byte_size_sum: -(byte_size(key) + byte_size(value))]

        from(c in Collection,
          where: c.id == ^collection_id,
          update: [inc: ^increment]
        )
      end,
      []
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{item: {1, nil}}} -> :ok
      {:ok, %{item: {0, nil}}} -> {:error, :not_found}
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  end

  defp all_query(collection_id, cursor, limit) do
    Item
    |> where([i], i.collection_id == ^collection_id)
    |> order_by([i], asc: i.id)
    |> limit(^limit)
    |> then(fn query ->
      case cursor do
        nil -> query
        ts_cursor -> where(query, [i], i.id > ^ts_cursor)
      end
    end)
  end

  defp filter_by_inserted_at(query, params) do
    query
    |> filter_by_created_before(params)
    |> filter_by_created_after(params)
  end

  defp filter_by_updated_at(query, params) do
    query
    |> filter_by_updated_before(params)
    |> filter_by_updated_after(params)
  end

  defp filter_by_created_after(query, %{created_after: created_after}),
    do: where(query, [i], i.inserted_at >= ^created_after)

  defp filter_by_created_after(query, _params), do: query

  defp filter_by_created_before(query, %{created_before: created_before}),
    do: where(query, [i], i.inserted_at < ^created_before)

  defp filter_by_created_before(query, _params), do: query

  defp filter_by_updated_after(query, %{updated_after: updated_after}),
    do: where(query, [i], i.updated_at >= ^updated_after)

  defp filter_by_updated_after(query, _params), do: query

  defp filter_by_updated_before(query, %{updated_before: updated_before}),
    do: where(query, [i], i.updated_at < ^updated_before)

  defp filter_by_updated_before(query, _params), do: query

  defp format_pattern(pattern) do
    pattern
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("*", "%")
  end

  defp handle_put_items(collection, delta_size) do
    case CollectionHook.handle_put_items(collection, delta_size) do
      :ok -> {:ok, nil}
      {:error, :exceeds_limit, message} -> {:error, message}
    end
  end

  defp handle_delete_items(collection, items_size) do
    if items_size do
      :ok = CollectionHook.handle_delete_items(collection, items_size)
    end

    {:ok, nil}
  end
end
