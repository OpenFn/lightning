defmodule Lightning.Runs.PromExPlugin.ImpededProjectHelperTest do
  use Lightning.DataCase, async: false

  alias Lightning.Runs.PromExPlugin.ImpededProjectHelper

  describe "workflows_with_available_runs_older_than" do
    setup do
      threshold = Lightning.current_time()

      _no_runs_project = insert(:project)

      _no_available_runs_project =
        insert(:project)
        |> setup_runs(
          threshold,
          [
            %{
              workflow_name: "Does not matter 1",
              workflow_concurrency: 2,
              runs: [
                %{time_shift: 0, state: :claimed},
                %{time_shift: -1, state: :started}
              ]
            }
          ]
        )

      _available_run_within_threshold_project =
        insert(:project)
        |> setup_runs(
          threshold,
          [
            %{
              workflow_name: "Does not matter 2",
              workflow_concurrency: 2,
              runs: [
                %{time_shift: 1, state: :available},
                %{time_shift: 2, state: :available}
              ]
            }
          ]
        )

      eligible_project_1 =
        insert(:project, name: "A", concurrency: 10)
        |> setup_runs(
          threshold,
          [
            %{
              workflow_name: "Workflow A-1",
              workflow_concurrency: 2,
              runs: [
                %{time_shift: 0, state: :available},
                %{time_shift: 0, state: :claimed},
                %{time_shift: 0, state: :started},
                %{time_shift: 0, state: :claimed}
              ]
            },
            %{
              workflow_name: "Workflow A-2",
              workflow_concurrency: 2,
              runs: [
                %{time_shift: -1, state: :started}
              ]
            }
          ]
        )

      eligible_project_2 =
        insert(:project, name: "B", concurrency: 20)
        |> setup_runs(
          threshold,
          [
            %{
              workflow_name: "Workflow B-1",
              workflow_concurrency: 5,
              runs: [
                %{time_shift: -1, state: :available},
                %{time_shift: -2, state: :available}
              ]
            },
            %{
              workflow_name: "Workflow B-2",
              workflow_concurrency: 3,
              runs: [
                %{time_shift: -1, state: :available},
                %{time_shift: -2, state: :started},
                %{time_shift: -3, state: :available}
              ]
            }
          ]
        )

      %{
        eligible_project_1: eligible_project_1,
        eligible_project_2: eligible_project_2,
        threshold: threshold,
        workflow_a_1: find_workflow("Workflow A-1"),
        workflow_a_2: find_workflow("Workflow A-2"),
        workflow_b_1: find_workflow("Workflow B-1"),
        workflow_b_2: find_workflow("Workflow B-2")
      }
    end

    test "returns projects with available runs older than the threshold", %{
      eligible_project_1: project_1,
      eligible_project_2: project_2,
      threshold: threshold,
      workflow_a_1: workflow_a_1,
      workflow_a_2: workflow_a_2,
      workflow_b_1: workflow_b_1,
      workflow_b_2: workflow_b_2
    } do
      workflow_records =
        ImpededProjectHelper.workflows_with_available_runs_older_than(threshold)

      assert Enum.count(workflow_records) == 3

      workflow_records
      |> assert_record_present?(project_1, workflow_a_1, 3)
      |> assert_record_absent?(project_1, workflow_a_2)
      |> assert_record_present?(project_2, workflow_b_1, 0)
      |> assert_record_present?(project_2, workflow_b_2, 1)
    end

    test "returns empty list if no available runs older than the threshold", %{
      threshold: threshold
    } do
      new_threshold = DateTime.add(threshold, -4)

      workflow_records =
        new_threshold
        |> ImpededProjectHelper.workflows_with_available_runs_older_than()

      assert workflow_records == []
    end

    defp assert_record_present?(records, project, workflow, runs_count) do
      record =
        Enum.find(records, fn record ->
          %{project_id: project_id, workflow_id: workflow_id} = record

          project_id == project.id && workflow_id == workflow.id
        end)

      assert record

      %{
        project_concurrency: project_concurrency,
        workflow_concurrency: workflow_concurrency,
        inprogress_runs_count: inprogress_runs_count
      } = record

      assert project_concurrency == project.concurrency
      assert workflow_concurrency == workflow.concurrency
      assert inprogress_runs_count == runs_count

      records
    end

    defp assert_record_absent?(records, project, workflow) do
      record =
        Enum.find(records, fn record ->
          %{project_id: project_id, workflow_id: workflow_id} = record

          project_id == project.id && workflow_id == workflow.id
        end)

      assert is_nil(record)

      records
    end

    defp find_workflow(workflow_name) do
      Lightning.Repo.get_by(Lightning.Workflows.Workflow, name: workflow_name)
    end
  end

  describe "find_projects_with_unused_concurrency/1" do
    test "returns list of projects that can process additional runs" do
      project_stats = [
        workflow_stats_map("p-spare-1", "w-spare-1-1", 4),
        workflow_stats_map("p-spare-1", "w-spare-1-2", 5),
        workflow_stats_map("p-nospare-1", "w-nospare-1-1", 5),
        workflow_stats_map("p-nospare-1", "w-nospare-1-2", 5),
        workflow_stats_map("p-spare-2", "w-spare-2-1", 1)
      ]

      expected_projects = ["p-spare-1", "p-spare-2"]

      assert ImpededProjectHelper.find_projects_with_unused_concurrency(
               project_stats
             ) ==
               expected_projects
    end

    defp workflow_stats_map(project_id, workflow_id, inprogress_runs) do
      %{
        project_id: project_id,
        workflow_id: workflow_id,
        inprogress_runs_count: inprogress_runs,
        project_concurrency: 10,
        workflow_concurrency: 6
      }
    end
  end

  describe "project_has_unused_concurrency?/1 project concurrency constrained" do
    test "false if sum of runs == proj concurrency - ignores workflows" do
      stats = [
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-1",
          inprogress_runs_count: 5,
          project_concurrency: 10,
          workflow_concurrency: 6
        },
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-2",
          inprogress_runs_count: 5,
          project_concurrency: 10,
          workflow_concurrency: 6
        }
      ]

      refute ImpededProjectHelper.project_has_unused_concurrency?(stats)
    end

    test "false if sum of runs > proj concurrency - ignores workflows" do
      stats = [
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-1",
          inprogress_runs_count: 6,
          project_concurrency: 10,
          workflow_concurrency: 6
        },
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-2",
          inprogress_runs_count: 5,
          project_concurrency: 10,
          workflow_concurrency: 6
        }
      ]

      refute ImpededProjectHelper.project_has_unused_concurrency?(stats)
    end

    test "true if runs < proj concurrency & workflow with capacity == 1" do
      stats = [
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-1",
          inprogress_runs_count: 6,
          project_concurrency: 10,
          workflow_concurrency: 6
        },
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-2",
          inprogress_runs_count: 3,
          project_concurrency: 10,
          workflow_concurrency: 6
        }
      ]

      assert ImpededProjectHelper.project_has_unused_concurrency?(stats)
    end

    test "true if runs < proj concurrency & workflows with capacity > 1" do
      stats = [
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-1",
          inprogress_runs_count: 5,
          project_concurrency: 20,
          workflow_concurrency: 6
        },
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-2",
          inprogress_runs_count: 6,
          project_concurrency: 20,
          workflow_concurrency: 6
        },
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-1",
          inprogress_runs_count: 1,
          project_concurrency: 20,
          workflow_concurrency: 6
        }
      ]

      assert ImpededProjectHelper.project_has_unused_concurrency?(stats)
    end

    test "false if sum of runs < p concurrency workflows with capacity == 0" do
      stats = [
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-1",
          inprogress_runs_count: 4,
          project_concurrency: 10,
          workflow_concurrency: 4
        },
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-2",
          inprogress_runs_count: 4,
          project_concurrency: 10,
          workflow_concurrency: 4
        }
      ]

      refute ImpededProjectHelper.project_has_unused_concurrency?(stats)
    end
  end

  describe "project_has_unused_concurrency?/1 - project concurrency is nil" do
    test "true if workflow with capacity == 1" do
      stats = [
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-1",
          inprogress_runs_count: 6,
          project_concurrency: nil,
          workflow_concurrency: 6
        },
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-2",
          inprogress_runs_count: 3,
          project_concurrency: nil,
          workflow_concurrency: 6
        }
      ]

      assert ImpededProjectHelper.project_has_unused_concurrency?(stats)
    end

    test "true if workflows with capacity > 1" do
      stats = [
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-1",
          inprogress_runs_count: 5,
          project_concurrency: nil,
          workflow_concurrency: 6
        },
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-2",
          inprogress_runs_count: 6,
          project_concurrency: nil,
          workflow_concurrency: 6
        },
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-1",
          inprogress_runs_count: 1,
          project_concurrency: nil,
          workflow_concurrency: 6
        }
      ]

      assert ImpededProjectHelper.project_has_unused_concurrency?(stats)
    end

    test "false if workflows with capacity == 0" do
      stats = [
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-1",
          inprogress_runs_count: 4,
          project_concurrency: nil,
          workflow_concurrency: 4
        },
        %{
          project_id: "project-id",
          workflow_id: "workflow-id-2",
          inprogress_runs_count: 4,
          project_concurrency: nil,
          workflow_concurrency: 4
        }
      ]

      refute ImpededProjectHelper.project_has_unused_concurrency?(stats)
    end
  end

  describe "workflow_has_unused_concurrency?/1" do
    test "returns false if inprogress runs equals workflow_concurrency" do
      stats = %{
        project_id: "project-id",
        workflow_id: "workflow-id",
        inprogress_runs_count: 5,
        project_concurrency: 10,
        workflow_concurrency: 5
      }

      refute ImpededProjectHelper.workflow_has_unused_concurrency?(stats)
    end

    test "returns false if inprogress runs exceeds workflow_concurrency" do
      stats = %{
        project_id: "project-id",
        workflow_id: "workflow-id",
        inprogress_runs_count: 6,
        project_concurrency: 10,
        workflow_concurrency: 5
      }

      refute ImpededProjectHelper.workflow_has_unused_concurrency?(stats)
    end

    test "returns true if inprogress runs less than workflow_concurrency" do
      stats = %{
        project_id: "project-id",
        workflow_id: "workflow-id",
        inprogress_runs_count: 4,
        project_concurrency: 10,
        workflow_concurrency: 5
      }

      assert ImpededProjectHelper.workflow_has_unused_concurrency?(stats)
    end

    test "always return true if workflow concurrency is nil" do
      stats = %{
        project_id: "project-id",
        workflow_id: "workflow-id",
        inprogress_runs_count: 1_000_000,
        project_concurrency: 10,
        workflow_concurrency: nil
      }

      assert ImpededProjectHelper.workflow_has_unused_concurrency?(stats)
    end
  end

  defp insert_runs_for_work_order(work_order, attributes, threshold) do
    attributes
    |> Enum.each(fn %{time_shift: time_shift, state: state} ->
      inserted_at = DateTime.add(threshold, time_shift)

      with_run(
        work_order,
        %{
          inserted_at: inserted_at,
          state: state,
          dataclip: build(:dataclip),
          starting_job: build(:job)
        }
      )
    end)
  end

  defp setup_runs(project, threshold, workflows) do
    workflows
    |> Enum.each(fn workflow_data ->
      %{
        workflow_name: workflow_name,
        workflow_concurrency: workflow_concurrency,
        runs: runs
      } = workflow_data

      workflow =
        insert(
          :workflow,
          name: workflow_name,
          project: project,
          concurrency: workflow_concurrency
        )

      work_order = insert(:workorder, workflow: workflow)

      insert_runs_for_work_order(work_order, runs, threshold)
    end)

    project
  end
end
