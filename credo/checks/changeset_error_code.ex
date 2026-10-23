defmodule Lightning.Credo.Check.ChangesetErrorCode do
  use Credo.Check,
    id: "LX0001",
    base_priority: :high,
    category: :warning,
    param_defaults: [
      files: %{included: ["lib/lightning/**/*.ex", "lib/lightning.ex"]}
    ],
    explanations: [
      check: """
      Every changeset error in `lib/lightning` names the rule it broke with a
      `code:` in its options, as Ecto's own validators leave `validation:` or
      `constraint:`. Code that reads a changeset can then tell its errors apart
      without matching on message text.

          add_error(changeset, :owner, "must have one owner", code: :one_owner)

          validate_change(changeset, :url, fn :url, url ->
            if ok?(url), do: [], else: [url: {"is not a URL", code: :format}]
          end)

      A validator fn may return its errors from a function in the same module;
      the check follows it.

      The API is one such reader: it sends each error with its code, and an
      error with neither `code:` nor an Ecto option raises there. Its codes
      are listed in `LightningWeb.API.Codes`; pick one from there or add one.

      `lib/lightning_web` is out of scope.
      """
    ]

  @block_keys [:do, :else, :after, :rescue, :catch]
  @branching [:if, :unless, :case, :cond, :with]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = SourceFile.ast(source_file)
    defs = local_defs(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        {node, check(node, defs, issue_meta) ++ issues}
      end)

    Enum.reverse(issues)
  end

  defp check({call, meta, args} = _node, defs, issue_meta)
       when is_list(args) do
    case {call_name(call), args} do
      {:add_error, [_ | _]} ->
        if coded_opts?(List.last(args)),
          do: [],
          else: [add_error_issue(issue_meta, meta)]

      {:validate_change, [_, _ | _]} ->
        args |> List.last() |> validator_issues(defs, issue_meta, meta)

      _ ->
        []
    end
  end

  defp check(_node, _defs, _issue_meta), do: []

  defp call_name({:., _, [_module, name]}) when is_atom(name), do: name
  defp call_name(name) when is_atom(name), do: name
  defp call_name(_), do: nil

  defp validator_issues({:fn, _, clauses}, defs, issue_meta, meta) do
    clauses
    |> Enum.flat_map(fn {:->, _, [_head, body]} -> tails(body, defs, []) end)
    |> Enum.flat_map(&returned_issues(&1, issue_meta, meta))
  end

  defp validator_issues(_not_fn, _defs, issue_meta, meta),
    do: [unreadable_issue(issue_meta, meta)]

  # The expressions a body can return, following branches and calls to
  # functions defined in the same file. `seen` stops recursion.
  defp tails({:__block__, _, [_ | _] = exprs}, defs, seen),
    do: tails(List.last(exprs), defs, seen)

  defp tails({:|>, _, [_lhs, {name, _, _} = rhs]}, defs, seen)
       when name in @branching,
       do: tails(rhs, defs, seen)

  defp tails({name, _, [_ | _] = args}, defs, seen) when name in @branching do
    branches = args |> List.last() |> List.wrap()

    Enum.flat_map(@block_keys, fn key ->
      case Keyword.fetch(branches, key) do
        :error -> []
        {:ok, [{:->, _, _} | _] = clauses} -> clause_tails(clauses, defs, seen)
        {:ok, body} -> tails(body, defs, seen)
      end
    end)
  end

  defp tails({name, _, args} = call, defs, seen)
       when is_atom(name) and is_list(args) do
    key = {name, length(args)}

    case Map.fetch(defs, key) do
      {:ok, bodies} ->
        if key in seen,
          do: [],
          else: Enum.flat_map(bodies, &tails(&1, defs, [key | seen]))

      :error ->
        [call]
    end
  end

  defp tails(expr, _defs, _seen), do: [expr]

  defp clause_tails(clauses, defs, seen) do
    Enum.flat_map(clauses, fn {:->, _, [_head, body]} ->
      tails(body, defs, seen)
    end)
  end

  defp returned_issues(nil, _issue_meta, _meta), do: []

  defp returned_issues(list, issue_meta, meta) when is_list(list) do
    list
    |> Enum.reject(&coded_error?/1)
    |> Enum.map(fn _ -> validate_change_issue(issue_meta, meta) end)
  end

  defp returned_issues(_unreadable, issue_meta, meta),
    do: [unreadable_issue(issue_meta, meta)]

  defp coded_error?({_field, {_message, opts}}), do: coded_opts?(opts)
  defp coded_error?(_), do: false

  defp coded_opts?(opts) when is_list(opts),
    do: Enum.any?(opts, &match?({:code, _}, &1))

  defp coded_opts?(_), do: false

  defp local_defs(ast) do
    {_ast, defs} =
      Macro.prewalk(ast, %{}, fn
        {kind, _, [head, body]} = node, acc when kind in [:def, :defp] ->
          case {def_key(head), Keyword.get(List.wrap(body), :do)} do
            {nil, _} ->
              {node, acc}

            {_, nil} ->
              {node, acc}

            {key, do_body} ->
              {node, Map.update(acc, key, [do_body], &[do_body | &1])}
          end

        node, acc ->
          {node, acc}
      end)

    defs
  end

  defp def_key({:when, _, [head | _]}), do: def_key(head)

  defp def_key({name, _, args}) when is_atom(name),
    do: {name, length(List.wrap(args))}

  defp def_key(_), do: nil

  defp add_error_issue(issue_meta, meta) do
    format_issue(issue_meta,
      message:
        "add_error has no `code:`. Pass one in its options, e.g. " <>
          "add_error(cs, :field, \"message\", code: :not_found); " <>
          "codes are listed in LightningWeb.API.Codes.",
      trigger: "add_error",
      line_no: meta[:line]
    )
  end

  defp validate_change_issue(issue_meta, meta) do
    format_issue(issue_meta,
      message:
        "validate_change returns an error with no `code:`. Return " <>
          "{field, {\"message\", code: :format}} instead of {field, \"message\"}; " <>
          "codes are listed in LightningWeb.API.Codes.",
      trigger: "validate_change",
      line_no: meta[:line]
    )
  end

  defp unreadable_issue(issue_meta, meta) do
    format_issue(issue_meta,
      message:
        "Can't see the errors this validate_change returns. Pass an fn that " <>
          "returns a literal list of {field, {\"message\", code: ...}}, " <>
          "directly or from a function in this module.",
      trigger: "validate_change",
      line_no: meta[:line]
    )
  end
end
