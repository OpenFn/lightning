defmodule Lightning.Workflows.GraphTest do
  use Lightning.DataCase, async: true

  import Lightning.JobsFixtures

  alias Lightning.Workflows.Graph

  describe "new/1" do
    setup :workflow_scenario

    test "can create a graph from a workflow with jobs and edges", %{
      workflow: workflow,
      jobs: jobs
    } do
      workflow = Lightning.Repo.preload(workflow, [:jobs, :edges])

      graph =
        Graph.new(workflow)
        |> Graph.remove(jobs.e.id)

      remaining_jobs = graph |> Graph.vertices() |> Enum.map(& &1.name)

      for j <- ["job_a", "job_b", "job_c", "job_d"] do
        assert j in remaining_jobs
      end

      for j <- ["job_e", "job_f", "job_g"] do
        refute j in remaining_jobs
      end

      graph =
        Graph.new(workflow)
        |> Graph.remove(jobs.d.id)

      remaining_jobs = graph |> Graph.vertices() |> Enum.map(& &1.name)

      for j <- ["job_a", "job_b", "job_c", "job_e", "job_f"] do
        assert j in remaining_jobs
      end

      refute jobs.d.id in remaining_jobs

      graph =
        Graph.new(workflow)
        |> Graph.remove(jobs.a.id)

      assert graph.jobs == []
    end
  end
end
