defmodule Lightning.ObanPrunerTest do
  use Oban.Testing, repo: Lightning.Repo
  use Lightning.DataCase, async: true

  alias Lightning.Repo

  describe "ObanPruner" do
    test "/perform" do
      assert ObanPruner.perform(%Oban.Job{}) == {:ok, 0}

      # Should _NOT_ be pruned
      Repo.insert(%Oban.Job{
        worker: "Pipeline",
        state: "completed",
        completed_at: DateTime.utc_now() |> Timex.shift(minutes: -10)
      })

      long_ago = DateTime.utc_now() |> Timex.shift(days: -3)
      base = %Oban.Job{worker: "Pipeline", completed_at: long_ago}

      Repo.insert(Map.put(base, :state, "available"))
      Repo.insert(Map.put(base, :state, "cancelled"))
      Repo.insert(Map.put(base, :state, "discarded"))
      Repo.insert(Map.put(base, :state, "executing"))
      Repo.insert(Map.put(base, :state, "retryable"))
      Repo.insert(Map.put(base, :state, "scheduled"))

      # Should be pruned
      Repo.insert(%Oban.Job{
        worker: "Pipeline",
        state: "completed",
        completed_at: DateTime.utc_now() |> Timex.shift(minutes: -75)
      })

      assert Repo.all(Oban.Job) |> Enum.count() == 8

      assert ObanPruner.perform(%Oban.Job{}) == {:ok, 1}

      assert Repo.all(Oban.Job) |> Enum.count() == 7
    end
  end
end
