defmodule LightningWeb.API.HistoryBody do
  @moduledoc """
  Reads the bodies of the routes that act on a project's history: the
  `{"state": "cancelled"}` of a work order or run `PATCH`, and the selection a
  bulk action or an export takes, `filter` or `work_order_ids`.

  Each answers `{:ok, value}`, a 400 `malformed` problem for a body that isn't
  a JSON object, or a 422 `invalid` problem holding every entry.
  """
  alias Lightning.Invocation.Query
  alias Lightning.WorkOrders.SearchParams
  alias LightningWeb.API.Errors
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Problem
  alias LightningWeb.API.Request

  @max_ids 100
  @not_a_uuid {"is not a UUID", validation: :cast, type: :binary_id}

  # The list endpoint's filters. `project_id` is the path's, never the body's.
  @filter_keys Map.keys(Query.work_order_filter_types()) -- [:project_id]

  @typedoc """
  The work orders a bulk action names, as the History page's search, and
  whether the request listed them by id rather than by filter.
  """
  @type selection :: %{search: SearchParams.t(), by_id?: boolean()}

  @doc """
  Checks a body asking to cancel: only `state`, and only `"cancelled"`.
  """
  @spec cancel(map()) :: :ok | {:error, Problem.t()}
  def cancel(body) do
    with :ok <- Request.check_object(body) do
      entries =
        Request.unknown_keys(body, [], [:state]) ++
          case body do
            %{"state" => "cancelled"} ->
              []

            %{"state" => _other} ->
              [
                Errors.entry(
                  ["state"],
                  {"must be cancelled", code: :not_allowed}
                )
              ]

            _missing ->
              [
                Errors.entry(
                  ["state"],
                  {"can't be blank", validation: :required}
                )
              ]
          end

      Errors.refuse(entries)
    end
  end

  @doc """
  The refusal of a cancel whose record has nothing a worker hasn't claimed.
  """
  @spec not_cancellable(String.t()) :: {:error, Problem.t()}
  def not_cancellable(detail),
    do: Errors.refuse([Errors.entry(["state"], {detail, code: :not_allowed})])

  @doc """
  The selection in `body`: `filter`, the list endpoint's filters, or
  `work_order_ids`, at most #{@max_ids}, but not both. `extra` lists the other
  keys the route accepts, which are returned as sent under `:extra`.

  With `required: false`, a body sending neither selects every work order.
  With `ids: false`, only `filter` selects, and `work_order_ids` is an
  unknown key.
  """
  @spec selection(map(), Lightning.Scope.t(), [atom()], keyword()) ::
          {:ok, selection(), map()} | {:error, Problem.t()}
  def selection(body, scope, extra, opts \\ []) do
    with {:ok, selection, entries, extra} <-
           selection_entries(body, scope, extra, opts),
         :ok <- Errors.refuse(entries) do
      {:ok, selection, extra}
    end
  end

  @doc """
  As `selection/4`, but answers the 422's entries rather than refusing, so a
  route can add the entries for its `extra` keys and report them together.
  The selection is `nil` when there are entries.
  """
  @spec selection_entries(map(), Lightning.Scope.t(), [atom()], keyword()) ::
          {:ok, selection() | nil, [Errors.entry()], map()}
          | {:error, Problem.t()}
  def selection_entries(body, scope, extra, opts \\ []) do
    with :ok <- Request.check_object(body) do
      ids? = Keyword.get(opts, :ids, true)
      selectors = if ids?, do: [:filter, :work_order_ids], else: [:filter]
      unknown = Request.unknown_keys(body, [], selectors ++ extra)
      required? = Keyword.get(opts, :required, true)
      body = if ids?, do: body, else: Map.delete(body, "work_order_ids")

      {search, entries} =
        case body do
          %{"filter" => _, "work_order_ids" => _} ->
            {nil, [exclusive()]}

          %{"filter" => filter} ->
            filter(filter, scope)

          %{"work_order_ids" => ids} ->
            ids(ids)

          _neither when required? ->
            {nil,
             [
               Errors.entry(
                 ["filter"],
                 {"send filter or work_order_ids", validation: :required}
               )
             ]}

          _neither ->
            filter(%{}, scope)
        end

      entries = unknown ++ entries

      selection =
        if entries == [],
          do: %{search: search, by_id?: Map.has_key?(body, "work_order_ids")}

      {:ok, selection, entries,
       Map.take(body, Enum.map(extra, &Atom.to_string/1))}
    end
  end

  defp exclusive,
    do:
      Errors.entry(
        ["work_order_ids"],
        {"can't be sent with filter", code: :exclusive}
      )

  defp filter(filter, scope) when is_map(filter) do
    unknown = Request.unknown_keys(filter, ["filter"], @filter_keys)

    case Filters.work_orders(Map.drop(filter, ["project_id"]), scope) do
      {:ok, filters} ->
        {SearchParams.from_filters(filters), unknown}

      {:error, changeset} ->
        entries =
          changeset.errors
          |> Enum.reverse()
          |> Enum.map(fn {field, error} ->
            Errors.entry(["filter", field], error)
          end)

        {nil, unknown ++ entries}
    end
  end

  defp filter(_not_an_object, _scope),
    do: {nil, [Errors.entry(["filter"], {"must be an object", code: :type})]}

  defp ids(ids) when is_list(ids) and length(ids) > @max_ids,
    do:
      {nil,
       [
         Errors.entry(
           ["work_order_ids"],
           {"should have at most %{count} item(s)",
            validation: :length, kind: :max, count: @max_ids}
         )
       ]}

  defp ids(ids) when is_list(ids) do
    entries =
      for {id, index} <- Enum.with_index(ids),
          not uuid?(id),
          do: Errors.entry(["work_order_ids", index], @not_a_uuid)

    if entries == [],
      do: {SearchParams.from_filters(%{id: ids}), []},
      else: {nil, entries}
  end

  defp ids(_not_a_list),
    do:
      {nil, [Errors.entry(["work_order_ids"], {"must be a list", code: :type})]}

  @doc """
  An entry for an optional id in the body that isn't a UUID, or `[]`.
  """
  @spec id_entries(map(), String.t()) :: [Errors.entry()]
  def id_entries(body, key) do
    case body do
      %{^key => nil} ->
        []

      %{^key => id} ->
        if uuid?(id), do: [], else: [Errors.entry([key], @not_a_uuid)]

      _absent ->
        []
    end
  end

  defp uuid?(id), do: match?({:ok, _id}, Request.id({[], id}))
end
