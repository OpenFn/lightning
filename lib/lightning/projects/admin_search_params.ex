defmodule Lightning.Projects.AdminSearchParams do
  @moduledoc """
  Query params for the superuser projects table.
  """

  use Lightning.Schema

  @primary_key false

  @default_sort "name"
  @allowed_sorts ~w(name inserted_at description owner scheduled_deletion)
  @default_page 1
  @default_page_size 10
  @max_page_size 100

  @type t :: %__MODULE__{
          search_term: String.t(),
          sort_by: String.t(),
          sort_direction: String.t(),
          page: pos_integer(),
          page_size: pos_integer()
        }

  embedded_schema do
    field :search_term, :string, default: ""
    field :sort_by, :string, default: @default_sort
    field :sort_direction, :string, default: "asc"
    field :page, :integer, default: @default_page
    field :page_size, :integer, default: @default_page_size
  end

  def new(params \\ %{})
  def new(%__MODULE__{} = params), do: params
  def new(nil), do: new(%{})

  def new(params) when is_map(params) do
    %__MODULE__{}
    |> cast(params, [:search_term, :sort_by, :sort_direction, :page, :page_size])
    |> update_change(:search_term, &trim_search_term/1)
    |> ensure_allowed(:sort_by, @allowed_sorts, @default_sort)
    |> ensure_allowed(:sort_direction, ~w(asc desc), "asc")
    |> ensure_positive_int(:page, @default_page)
    |> ensure_page_size()
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
      "search_term" => params.search_term,
      "sort_by" => params.sort_by,
      "sort_direction" => params.sort_direction,
      "page" => Integer.to_string(params.page),
      "page_size" => Integer.to_string(params.page_size)
    }
  end

  def to_uri_params(params) when is_map(params) do
    params
    |> new()
    |> to_uri_params()
  end

  defp trim_search_term(nil), do: ""
  defp trim_search_term(term), do: String.trim(term)

  defp ensure_allowed(changeset, field, allowed, default) do
    value = get_field(changeset, field)

    if value in allowed do
      changeset
    else
      put_change(changeset, field, default)
    end
  end

  defp ensure_positive_int(changeset, field, default) do
    value = get_field(changeset, field)

    if is_integer(value) and value > 0 do
      changeset
    else
      put_change(changeset, field, default)
    end
  end

  defp ensure_page_size(changeset) do
    value = get_field(changeset, :page_size)

    if is_integer(value) and value > 0 do
      put_change(changeset, :page_size, min(value, @max_page_size))
    else
      put_change(changeset, :page_size, @default_page_size)
    end
  end
end
