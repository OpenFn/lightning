defmodule LightningWeb.API.Filters do
  @moduledoc """
  Reads a list route's query string into the typed values its context takes.

  A filter function answers `{:ok, filters}`, or `{:error, changeset}` with an
  error on every bad parameter, for
  `LightningWeb.API.Errors.refuse_parameters/1`.
  `page/1` never refuses.
  """
  alias Ecto.Changeset
  alias Lightning.Config
  alias Lightning.Invocation.LogLine
  alias Lightning.Invocation.Query
  alias Lightning.Scope

  defmodule Cursor do
    @moduledoc false
    # The id of the last item a page carried, base64 encoded.
    use Ecto.Type

    def type, do: :integer

    def cast(cursor) when is_binary(cursor) do
      with {:ok, decoded} <- Base.decode64(cursor),
           {id, ""} <- Integer.parse(decoded) do
        {:ok, id}
      else
        _invalid -> :error
      end
    end

    def cast(_cursor), do: :error

    def load(id), do: {:ok, id}
    def dump(id), do: {:ok, id}

    def encode(id), do: Base.encode64(to_string(id))
  end

  @collection_item_params %{
    created_after: :utc_datetime_usec,
    created_before: :utc_datetime_usec,
    cursor: Cursor,
    key: :string,
    limit: :integer,
    updated_after: :utc_datetime_usec,
    updated_before: :utc_datetime_usec
  }

  @collection_item_parameters Enum.map(
                                Map.keys(@collection_item_params),
                                &Atom.to_string/1
                              )

  @run_states Lightning.Run.states() |> Enum.map(&to_string/1)
  @work_order_states Lightning.WorkOrder.states() |> Enum.map(&to_string/1)
  @log_levels Ecto.Enum.dump_values(LogLine, :level)

  @doc """
  The run filters in `params`, or a changeset with an error on every bad
  parameter, none quoting its value.

  `state` is a comma-separated list of run states.
  """
  @spec runs(map(), Scope.t()) :: {:ok, map()} | {:error, Changeset.t()}
  def runs(params, scope) do
    params
    |> split_list("state")
    |> cast(
      Query.run_filter_types(),
      scope,
      &Changeset.validate_subset(&1, :state, @run_states)
    )
  end

  @doc """
  The work order filters in `params`, or a changeset with an error on every bad
  parameter, none quoting its value.

  `id` and `state` are comma-separated lists, `id` also a repeated parameter.
  """
  @spec work_orders(map(), Scope.t()) :: {:ok, map()} | {:error, Changeset.t()}
  def work_orders(params, scope) do
    params
    |> split_list("id")
    |> split_list("state")
    |> cast(
      Query.work_order_filter_types(),
      scope,
      &Changeset.validate_subset(&1, :state, @work_order_states)
    )
  end

  @doc """
  The log line filters in `params`, or a changeset with an error on every bad
  parameter, none quoting its value.
  """
  @spec log_lines(map(), Scope.t()) :: {:ok, map()} | {:error, Changeset.t()}
  def log_lines(params, scope) do
    cast(
      params,
      Query.log_line_filter_types(),
      scope,
      &Changeset.validate_inclusion(&1, :level, @log_levels)
    )
  end

  @doc """
  The collection item filters in `params`, or a changeset with an error on
  every bad parameter, none quoting its value.

  `limit` defaults to `Lightning.Config.collections_default_stream_limit/0`.
  An empty value is a value, not a missing one. `cursor` is the one the
  previous response carried. Parameters outside
  `collection_item_parameters/0` are left out.
  """
  @spec collection_items(map()) :: {:ok, map()} | {:error, Changeset.t()}
  def collection_items(params) do
    {%{limit: Config.collections_default_stream_limit()},
     @collection_item_params}
    |> Changeset.cast(params, Map.keys(@collection_item_params),
      empty_values: []
    )
    |> Changeset.validate_number(:limit, greater_than_or_equal_to: 0)
    |> Changeset.apply_action(:validate)
  end

  @doc "The names of the parameters `collection_items/1` reads."
  @spec collection_item_parameters() :: [String.t()]
  def collection_item_parameters, do: @collection_item_parameters

  @doc """
  The page `params` asks for, as `Lightning.Repo.paginate/2` takes it.

  Each value is read as Scrivener reads one: the number a string starts with,
  so `5abc` is 5 and `2.0` is 2. A value below 1, or one with no number to
  read, is left out and the default applies; it is never refused. Above 100,
  `page_size` is cut to 100 by the repo.
  """
  @spec page(map()) :: [page: pos_integer(), page_size: pos_integer()]
  def page(params) do
    for key <- [:page, :page_size],
        {:ok, number} <- [leading_number(params[Atom.to_string(key)])],
        do: {key, number}
  end

  defp leading_number(value) when is_binary(value),
    do: value |> Integer.parse() |> leading_number()

  defp leading_number({number, _rest}), do: leading_number(number)

  defp leading_number(number) when is_integer(number) and number > 0,
    do: {:ok, number}

  defp leading_number(_value), do: :error

  defp cast(params, types, scope, validate) do
    {%{}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> validate.()
    |> require_operator_project(params, scope)
    |> Changeset.apply_action(:validate)
  end

  defp require_operator_project(changeset, params, scope) do
    if Scope.operator?(scope) and not Map.has_key?(params, "project_id"),
      do:
        Changeset.add_error(changeset, :project_id, "can't be blank",
          validation: :required
        ),
      else: changeset
  end

  defp split_list(params, key) do
    case params do
      %{^key => value} when is_binary(value) ->
        Map.put(params, key, String.split(value, ",", trim: true))

      _other ->
        params
    end
  end
end
