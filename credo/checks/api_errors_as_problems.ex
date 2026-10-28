defmodule Lightning.Credo.Check.ApiErrorsAsProblems do
  use Credo.Check,
    id: "LX0003",
    base_priority: :high,
    category: :warning,
    param_defaults: [
      files: %{
        included: [
          "lib/lightning_web/controllers/api/**/*.ex",
          "lib/lightning_web/controllers/collections_controller.ex"
        ]
      }
    ],
    explanations: [
      check: """
      API controllers never set an error status themselves. Every error is an
      RFC 9457 problem document built by `LightningWeb.API.Problem`: return the
      error from the action so `LightningWeb.API.FallbackController` renders
      it, or build one with `Problem.new/2` and send it with
      `Problem.respond/2`.

          {:error, :not_found}    # not conn |> put_status(:not_found) |> json(...)

      `put_status/2`, `send_resp/3` and `resp/3` are flagged, piped or not,
      when the status is a 4xx or 5xx integer or an atom such as
      `:not_found`. Success statuses and statuses held in a variable are not
      flagged.
      """
    ]

  @functions %{put_status: 2, send_resp: 3, resp: 3}

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    {_ast, issues} =
      source_file
      |> SourceFile.ast()
      |> Macro.prewalk([], fn
        {:|>, _, [_conn, call]} = node, issues ->
          {node, check_call(call, 1, issue_meta, issues)}

        node, issues ->
          {node, check_call(node, 0, issue_meta, issues)}
      end)

    Enum.reverse(issues)
  end

  defp check_call(call, piped, issue_meta, issues) do
    with {fun, meta, args} <- call_parts(call),
         arity when is_integer(arity) <- @functions[fun],
         true <- length(args) + piped == arity,
         status = Enum.at(args, 1 - piped),
         true <- error_status?(status) do
      [issue(issue_meta, meta, fun, status) | issues]
    else
      _ -> issues
    end
  end

  defp call_parts({{:., _, [_module, fun]}, meta, args}) when is_list(args),
    do: {fun, meta, args}

  defp call_parts({fun, meta, args}) when is_atom(fun) and is_list(args),
    do: {fun, meta, args}

  defp call_parts(_node), do: nil

  defp error_status?(code) when is_integer(code), do: code in 400..599

  defp error_status?(status) when is_atom(status) do
    error_status?(Plug.Conn.Status.code(status))
  rescue
    _ -> false
  end

  defp error_status?(_status), do: false

  defp issue(issue_meta, meta, fun, status) do
    format_issue(issue_meta,
      message:
        "API controllers don't set an error status with #{fun}(#{inspect(status)}). " <>
          "Return the error to FallbackController, or use Problem.new/2 " <>
          "and Problem.respond/2.",
      trigger: Atom.to_string(fun),
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
