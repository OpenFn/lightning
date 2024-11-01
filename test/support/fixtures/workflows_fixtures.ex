defmodule Lightning.WorkflowsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Workflows` context.
  """

  import Lightning.ProjectsFixtures
  import Lightning.Factories

  @doc """
  Generate a workflow.
  """
  @spec workflow_fixture(attrs :: Keyword.t()) ::
          Lightning.Workflows.Workflow.t()
  def workflow_fixture(attrs \\ []) when is_list(attrs) do
    {:ok, workflow} =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn -> project_fixture().id end)
      |> Enum.into(%{
        name:
          Enum.take_random(
            ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ ",
            10
          )
          |> to_string()
      })
      |> Lightning.Workflows.save_workflow(insert(:user))

    workflow
  end

  def complex_workflow_with_runs(opts \\ []) do
    workflow_name = Keyword.get(opts, :name, "Workflow1")

    last_workorder_failed? =
      Keyword.get(opts, :last_workorder_failed, true)

    project = Keyword.get(opts, :project, insert(:project))

    %{jobs: [job0, job1, job2, job3, job4, job5, job6]} =
      workflow = insert(:complex_workflow, project: project, name: workflow_name)

    trigger = insert(:trigger, workflow: workflow)

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :pending,
      runs: [
        %{
          state: :available,
          dataclip: build(:dataclip),
          starting_trigger: trigger,
          steps: []
        }
      ]
    )

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :running,
      runs: [
        %{
          state: :claimed,
          dataclip: build(:dataclip),
          starting_trigger: trigger,
          steps: []
        }
      ]
    )

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :running,
      runs: [
        %{
          state: :started,
          dataclip: build(:dataclip),
          starting_trigger: trigger,
          steps: []
        }
      ]
    )

    runs_success = [
      %{
        state: :success,
        dataclip: build(:dataclip),
        starting_trigger: trigger,
        steps:
          Enum.map([job0, job4, job5, job6], fn job ->
            # job6 step started but not completed
            exit_reason = if job == job6, do: nil, else: "success"
            insert(:step, job: job, exit_reason: exit_reason)
          end)
      }
    ]

    runs_failed = [
      %{
        state: :failed,
        dataclip: build(:dataclip),
        starting_trigger: trigger,
        steps:
          Enum.map([job0, job1, job2, job3], fn job ->
            exit_reason =
              if job == job0 or job == job3, do: "fail", else: "success"

            insert(:step, job: job, exit_reason: exit_reason)
          end)
      }
    ]

    {wo_state1, wo_state2, runs1, runs2} =
      if last_workorder_failed? do
        {:success, :failed, runs_success, runs_failed}
      else
        {:failed, :success, runs_failed, runs_success}
      end

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: wo_state1,
      runs: runs1
    )

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: wo_state2,
      runs: runs2
    )

    workflow
  end
end
