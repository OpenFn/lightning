defmodule PickerTreeBenchmark do
  @moduledoc """
  Latency benchmark for `Lightning.Projects.get_project_tree_for_user/1`,
  the function the global project picker calls on every LiveView
  navigation. Benchee runs each scenario in a single process for a few
  seconds and reports the percentile distribution (median, p95, p99) plus
  operations per second.

  The script does not run a parallel pass. `Ecto.Adapters.SQL.Sandbox`
  forces all spawned workers to share a single DB connection, so
  `parallel: N` numbers describe serialized contention rather than real
  concurrent pool behaviour and mislead more than they inform. End-to-end
  concurrent latency belongs in a k6 run against a running Lightning
  instance, not here.

  Run from the lightning project root:

      MIX_ENV=test mix ecto.create
      MIX_ENV=test mix ecto.migrate
      MIX_ENV=test mix run benchmarking/picker_tree_benchmark.exs

  Read the Benchee table; the relevant columns are `average`, `median`,
  `99th percentile`, and `ips` (iterations per second).
  """

  alias Lightning.Factories
  alias Lightning.Projects

  @bench_time 3
  @warmup 1

  def run do
    Benchee.run(
      Map.new(build_scenarios(), &to_benchee_pair/1),
      time: @bench_time,
      warmup: @warmup,
      memory_time: 0,
      print: [fast_warning: false, configuration: false],
      formatters: [Benchee.Formatters.Console]
    )
  end

  defp to_benchee_pair({name, user}) do
    {Atom.to_string(name), fn -> Projects.get_project_tree_for_user(user) end}
  end

  defp build_scenarios do
    [
      {:small_owner, build_small_owner()},
      {:big_workspace_owner, build_big_workspace_owner()},
      {:scattered_memberships, build_scattered_memberships()},
      {:deep_member_no_root, build_deep_member_no_root()},
      {:editor_with_explicit_members, build_editor_with_explicit_members()}
    ]
  end

  defp build_small_owner do
    user = Factories.insert(:user)
    root = Factories.insert(:project, project_users: [%{user: user, role: :owner}])
    for _ <- 1..5, do: Factories.insert(:project, parent: root)
    user
  end

  defp build_big_workspace_owner do
    user = Factories.insert(:user)
    root = Factories.insert(:project, project_users: [%{user: user, role: :owner}])
    max_depth = Lightning.Config.max_sandbox_nesting_depth()

    Enum.reduce(1..max_depth, [root], fn _, parents ->
      Enum.flat_map(parents, fn p ->
        for _ <- 1..3, do: Factories.insert(:project, parent: p)
      end)
    end)

    user
  end

  defp build_scattered_memberships do
    user = Factories.insert(:user)

    for _ <- 1..20 do
      Factories.insert(:project, project_users: [%{user: user, role: :viewer}])
    end

    user
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
    user
  end

  defp build_editor_with_explicit_members do
    user = Factories.insert(:user)
    root = Factories.insert(:project, project_users: [%{user: user, role: :editor}])

    sandboxes = for _ <- 1..30, do: Factories.insert(:project, parent: root)

    for s <- Enum.take(sandboxes, 10) do
      Factories.insert(:project_user, user: user, project: s, role: :viewer)
    end

    user
  end
end

# The sandbox needs to allow the spawned Benchee workers to share the same
# DB connection so they can see the seeded data; :shared mode is the way.
Ecto.Adapters.SQL.Sandbox.mode(Lightning.Repo, :manual)
:ok = Ecto.Adapters.SQL.Sandbox.checkout(Lightning.Repo)
Ecto.Adapters.SQL.Sandbox.mode(Lightning.Repo, {:shared, self()})

try do
  PickerTreeBenchmark.run()
after
  Ecto.Adapters.SQL.Sandbox.checkin(Lightning.Repo)
end
