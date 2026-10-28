defmodule Lightning.Credo.Check.ApiControllerNoRepo do
  use Credo.Check,
    id: "LX0002",
    base_priority: :high,
    category: :warning,
    param_defaults: [
      files: %{included: ["lib/lightning_web/controllers/api/**/*.ex"]}
    ],
    explanations: [
      check: """
      API controllers never reference `Repo` or `Ecto.Query`. A lookup or a
      query goes in a context function in `lib/lightning`, and the controller
      calls that function.

          project = Projects.get_project(id)    # not Repo.get(Project, id)

      `Ecto.Changeset` is allowed, for checking input.

      Every reference is flagged, whether in an `alias`, `import`, `require`
      or a remote call such as `Repo.get/2`. Query macros used after `import
      Ecto.Query` are not flagged one by one. The import itself is.
      """
    ]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    {_ast, issues} =
      source_file
      |> SourceFile.ast()
      |> Macro.prewalk([], fn
        {:__aliases__, meta, parts} = node, issues when is_list(parts) ->
          if forbidden?(parts),
            do: {node, [issue(issue_meta, meta, parts) | issues]},
            else: {node, issues}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp forbidden?([:Repo]), do: true
  defp forbidden?([:Lightning, :Repo]), do: true
  defp forbidden?([:Ecto, :Query | _]), do: true
  defp forbidden?(_parts), do: false

  defp issue(issue_meta, meta, parts) do
    format_issue(issue_meta,
      message:
        "API controllers don't use #{Enum.join(parts, ".")}. Put the lookup " <>
          "or query in a context function in lib/lightning and call that.",
      trigger: Enum.join(parts, "."),
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
