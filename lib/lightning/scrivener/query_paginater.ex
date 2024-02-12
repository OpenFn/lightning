defimpl Scrivener.Paginater, for: Ecto.Query do
  import Ecto.Query

  alias Scrivener.Config
  alias Scrivener.Page

  @moduledoc false

  @spec paginate(Ecto.Query.t(), Scrivener.Config.t()) :: Scrivener.Page.t()
  def paginate(query, %Config{
        page_size: page_size,
        page_number: page_number,
        module: repo,
        caller: caller,
        options: options
      }) do
    total_entries =
      Keyword.get(options, :total_entries) ||
        total_entries(query, repo, caller, options)

    total_pages = total_pages(total_entries, page_size)

    allow_overflow_page_number =
      Keyword.get(options, :allow_overflow_page_number, false)

    page_number =
      if allow_overflow_page_number,
        do: page_number,
        else: min(total_pages, page_number)

    %Page{
      page_size: page_size,
      page_number: page_number,
      entries:
        entries(
          query,
          repo,
          page_number,
          total_pages,
          page_size,
          caller,
          options
        ),
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  defp entries(_, _, page_number, total_pages, _, _, _)
       when page_number > total_pages,
       do: []

  defp entries(query, repo, page_number, _, page_size, caller, options) do
    offset =
      Keyword.get_lazy(options, :offset, fn -> page_size * (page_number - 1) end)

    opts = Keyword.take(options, [:prefix, :timeout])

    query
    |> offset(^offset)
    |> limit(^page_size)
    |> all(repo, caller, opts)
  end

  defp total_entries(query, repo, caller, options) do
    prefix = options[:prefix]
    limit = options[:limit]

    total_entries =
      query
      |> exclude(:preload)
      |> exclude(:order_by)
      |> limit_count(limit)
      |> aggregate()
      |> one(repo, caller, prefix)

    total_entries || 0
  end

  defp limit_count(query, nil), do: query
  defp limit_count(query, limit), do: query |> limit(^limit)

  defp aggregate(%{distinct: %{expr: expr}} = query)
       when expr == true or is_list(expr) do
    query
    |> exclude(:select)
    |> count()
  end

  defp aggregate(
         %{
           group_bys: [
             %Ecto.Query.QueryExpr{
               expr: [
                 {{:., [], [{:&, [], [source_index]}, field]}, [], []} | _
               ]
             }
             | _
           ]
         } = query
       ) do
    query
    |> exclude(:select)
    |> select([{x, source_index}], struct(x, ^[field]))
    |> count()
  end

  defp aggregate(query) do
    query
    |> exclude(:select)
    |> select(count("*"))
  end

  defp count(query) do
    query
    |> subquery
    |> select(count("*"))
  end

  defp total_pages(0, _), do: 1

  defp total_pages(total_entries, page_size) do
    (total_entries / page_size) |> Float.ceil() |> round
  end

  defp all(query, repo, caller, []) do
    repo.all(query, caller: caller)
  end

  defp all(query, repo, caller, opts) do
    repo.all(query, Keyword.put(opts, :caller, caller))
  end

  defp one(query, repo, caller, nil) do
    repo.one(query, caller: caller)
  end

  defp one(query, repo, caller, prefix) do
    repo.one(query, caller: caller, prefix: prefix)
  end
end
