defmodule PickerTreeBenchmark do
  @moduledoc """
  Measures `Lightning.Projects.get_project_tree_for_user/1` latency and the
  number of `Lightning.Repo` queries it issues, against three workspace
  shapes that bracket what real customers look like:

    * `:small`   — one workspace, a handful of sandboxes, user is root owner.
    * `:medium`  — one workspace, two levels of nesting, user is editor on the
                   root and viewer on a subset of sandboxes.
    * `:large`   — three independent workspaces with many sandboxes at the
                   configured max nesting depth, user holds memberships across
                   all three plus some deep direct memberships.

  Run from the lightning project root:

      MIX_ENV=test mix ecto.create
      MIX_ENV=test mix ecto.migrate
      MIX_ENV=test mix run benchmarking/picker_tree_benchmark.exs

  Output is one line per scenario with wall-clock latency and query count.
  """

  alias Lightning.Factories
  alias Lightning.Projects

  @telemetry_handler "picker-tree-benchmark-query-counter"

  def run do
    attach_query_counter()

    try do
      results = Enum.map(scenarios(), &measure/1)
      render(results)
    after
      detach_query_counter()
    end
  end

  defp render(results) do
    headers = ["Scenario", "Memberships", "Items returned", "Queries", "Latency"]

    rows =
      Enum.map(results, fn r ->
        [
          Atom.to_string(r.scenario),
          Integer.to_string(r.memberships),
          Integer.to_string(r.items),
          Integer.to_string(r.queries),
          "#{r.latency_ms} ms"
        ]
      end)

    widths =
      [headers | rows]
      |> Enum.zip()
      |> Enum.map(fn column -> column |> Tuple.to_list() |> Enum.map(&String.length/1) |> Enum.max() end)

    format_row = fn cells ->
      cells
      |> Enum.zip(widths)
      |> Enum.map_join(" | ", fn {cell, w} -> String.pad_trailing(cell, w) end)
    end

    separator =
      widths
      |> Enum.map(fn w -> String.duplicate("-", w) end)
      |> Enum.join("-+-")

    IO.puts("")
    IO.puts(format_row.(headers))
    IO.puts(separator)
    for row <- rows, do: IO.puts(format_row.(row))
    IO.puts("")
  end

  defp scenarios do
    [
      {:small_owner, &build_small_owner/0},
      {:big_workspace_owner, &build_big_workspace_owner/0},
      {:scattered_memberships, &build_scattered_memberships/0},
      {:deep_member_no_root, &build_deep_member_no_root/0},
      {:editor_with_explicit_members, &build_editor_with_explicit_members/0}
    ]
  end

  defp measure({name, builder}) do
    %{user: user, memberships: memberships} = builder.()

    reset_query_count()
    {duration_us, result} = :timer.tc(fn -> Projects.get_project_tree_for_user(user) end)

    %{
      scenario: name,
      memberships: memberships,
      items: length(result),
      queries: get_query_count(),
      latency_ms: div(duration_us, 1_000)
    }
  end

  defp build_small_owner do
    user = Factories.insert(:user)
    root = Factories.insert(:project, project_users: [%{user: user, role: :owner}])
    for _ <- 1..5, do: Factories.insert(:project, parent: root)

    %{user: user, memberships: 1}
  end

  defp build_big_workspace_owner do
    user = Factories.insert(:user)
    root = Factories.insert(:project, project_users: [%{user: user, role: :owner}])

    max_depth = Lightning.Config.max_sandbox_nesting_depth()

    _ =
      Enum.reduce(1..max_depth, [root], fn _, parents ->
        Enum.flat_map(parents, fn p ->
          for _ <- 1..3, do: Factories.insert(:project, parent: p)
        end)
      end)

    %{user: user, memberships: 1}
  end

  defp build_scattered_memberships do
    user = Factories.insert(:user)

    for _ <- 1..20 do
      Factories.insert(:project, project_users: [%{user: user, role: :viewer}])
    end

    %{user: user, memberships: 20}
  end

  defp build_deep_member_no_root do
    user = Factories.insert(:user)
    root = Factories.insert(:project)
    max_depth = Lightning.Config.max_sandbox_nesting_depth()

    leaf =
      Enum.reduce(1..max_depth, root, fn _, parent ->
        Factories.insert(:project, parent: parent)
      end)

    Factories.insert(:project_user, user: user, project: leaf, role: :viewer)

    %{user: user, memberships: 1}
  end

  defp build_editor_with_explicit_members do
    user = Factories.insert(:user)
    root = Factories.insert(:project, project_users: [%{user: user, role: :editor}])

    sandboxes = for _ <- 1..30, do: Factories.insert(:project, parent: root)

    for s <- Enum.take(sandboxes, 10) do
      Factories.insert(:project_user, user: user, project: s, role: :viewer)
    end

    %{user: user, memberships: 11}
  end

  defp attach_query_counter do
    :telemetry.attach(
      @telemetry_handler,
      [:lightning, :repo, :query],
      fn _event, _measurements, _metadata, _config -> increment_query_count() end,
      nil
    )
  end

  defp detach_query_counter, do: :telemetry.detach(@telemetry_handler)

  defp reset_query_count, do: Process.put(:picker_bench_query_count, 0)

  defp increment_query_count do
    Process.put(:picker_bench_query_count, get_query_count() + 1)
  end

  defp get_query_count, do: Process.get(:picker_bench_query_count, 0)
end

# Wrap the run in a sandboxed DB transaction so the seeded data is rolled back
# at the end. Lightning.DataCase uses Ecto.Adapters.SQL.Sandbox in tests; this
# script uses the same mechanism so it leaves no rows behind.
Ecto.Adapters.SQL.Sandbox.mode(Lightning.Repo, :manual)
:ok = Ecto.Adapters.SQL.Sandbox.checkout(Lightning.Repo)

try do
  PickerTreeBenchmark.run()
after
  Ecto.Adapters.SQL.Sandbox.checkin(Lightning.Repo)
end
