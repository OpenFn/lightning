defmodule Lightning.Workflows.GraphTest do
  use Lightning.DataCase, async: true

  import Lightning.JobsFixtures

  alias Lightning.Workflows.Graph

  describe "new/1" do
    setup do
      workflow_scenario()
    end

    test "can create a graph from a workflow with jobs and edges", workflow do
      jobs = Map.values(workflow.jobs)
      edges = Map.values(workflow.edges)

      assert_raise KeyError, fn ->
        Graph.new(jobs)
      end

      loaded_edges =
        Enum.map(edges, fn e -> Repo.preload(e, [:source_job, :target_job]) end)

      # # find all the attempt runs for a given attempt
      # runs_query =
      #   from(r in Run,
      #     join: a in assoc(r, :attempts),
      #     where: a.id == ^attempt.id,
      #     select: r
      #   )

      # runs_for_attempt = runs_query |> preload(job: :trigger) |> Repo.all()

      # create a graph of the runs using their triggers
      # remove the run

      # Attempt Run id, run_id, job_id, upstream_job_id

      # jobs_used =
      #   from(j in Job,
      #     join: r in subquery(runs_query),
      #     on: r.job_id == j.id,
      #     preload: [trigger: :upstream_job]
      #   )
      #   |> Repo.all()
      job_e = Enum.find(jobs, &match?(%{name: "job_e"}, &1))

      loaded_workflow = %{jobs: jobs, edges: loaded_edges}

      graph =
        Graph.new(loaded_workflow)
        |> Graph.remove(job_e.id)

      remaining_jobs = graph |> Graph.vertices() |> Enum.map(& &1.name)

      for j <- ["job_a", "job_b", "job_c", "job_d"] do
        assert j in remaining_jobs
      end

      for j <- ["job_e", "job_f", "job_g"] do
        refute j in remaining_jobs
      end

      job_d = Enum.find(jobs, &match?(%{name: "job_d"}, &1))

      graph =
        Graph.new(loaded_workflow)
        |> Graph.remove(job_d.id)

      remaining_jobs = graph |> Graph.vertices() |> Enum.map(& &1.name)

      for j <- ["job_a", "job_b", "job_c", "job_e", "job_f"] do
        assert j in remaining_jobs
      end

      refute job_d.id in remaining_jobs

      job_a = Enum.find(jobs, &match?(%{name: "job_a"}, &1))

      graph =
        Graph.new(loaded_workflow)
        |> Graph.remove(job_a.id)

      assert graph.jobs == []
    end
  end
end
