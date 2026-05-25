defmodule Lightning.Projects.AdminSearchParams do
  @moduledoc """
  Normalized query params for the superuser projects table.
  """

  use Lightning.Schema

  @primary_key false

  @default_sort "name"
  @allowed_sorts ~w(name inserted_at description owner scheduled_deletion)
  @default_page 1
  @default_page_size 10
  @max_page_size 100

  @type t :: %__MODULE__{
          filter: String.t(),
          sort: String.t(),
          dir: String.t(),
          page: pos_integer(),
          page_size: pos_integer()
        }

  embedded_schema do
    field :filter, :string, default: ""
    field :sort, :string, default: @default_sort
    field :dir, :string, default: "asc"
    field :page, :integer, default: @default_page
    field :page_size, :integer, default: @default_page_size
  end

  def new(params \\ %{})
  def new(%__MODULE__{} = params), do: params
  def new(nil), do: new(%{})

  def new(params) when is_map(params) do
    params = stringify_param_keys(params)

    %__MODULE__{}
    |> cast(
      %{
        "filter" => normalize_filter(Map.get(params, "filter")),
        "sort" => normalize_sort(Map.get(params, "sort")),
        "dir" => normalize_dir(Map.get(params, "dir")),
        "page" => parse_positive_int(Map.get(params, "page"), @default_page),
        "page_size" =>
          Map.get(params, "page_size")
          |> parse_positive_int(@default_page_size)
          |> min(@max_page_size)
      },
      [:filter, :sort, :dir, :page, :page_size]
    )
    |> apply_action!(:validate)
  end

  def default_uri_params do
    new()
    |> to_uri_params()
  end

  def pagination_opts(%__MODULE__{} = params) do
    [page: params.page, page_size: params.page_size]
  end

  def to_uri_params(%__MODULE__{} = params) do
    %{
      "filter" => params.filter,
      "sort" => params.sort,
      "dir" => params.dir,
      "page" => Integer.to_string(params.page),
      "page_size" => Integer.to_string(params.page_size)
    }
  end

  def to_uri_params(params) when is_map(params) do
    params
    |> new()
    |> to_uri_params()
  end

  defp normalize_sort(sort) when is_binary(sort) do
    if sort in @allowed_sorts, do: sort, else: @default_sort
  end

  defp normalize_sort(sort) when is_atom(sort) do
    sort
    |> Atom.to_string()
    |> normalize_sort()
  end

  defp normalize_sort(_), do: @default_sort

  defp normalize_dir(dir) when dir in ["asc", :asc], do: "asc"
  defp normalize_dir(dir) when dir in ["desc", :desc], do: "desc"
  defp normalize_dir(_), do: "asc"

  defp normalize_filter(nil), do: ""

  defp normalize_filter(filter) do
    filter
    |> to_string()
    |> String.trim()
  end

  defp stringify_param_keys(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp parse_positive_int(value, _default) when is_integer(value) and value > 0,
    do: value

  defp parse_positive_int(value, default) do
    case Integer.parse(to_string(value || "")) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end
end
