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
      |> Lightning.Workflows.create_workflow()

    workflow
  end

  def build_workflow(attrs \\ []) do
    Ecto.Changeset.cast(
      %Lightning.Workflows.Workflow{},
      %{
        "project_id" => attrs[:project_id] || project_fixture().id,
        "id" => Ecto.UUID.generate()
      },
      [:project_id, :id]
    )
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
      attempts: [
        %{
          state: :available,
          dataclip: build(:dataclip),
          starting_trigger: trigger,
          runs: []
        }
      ]
    )

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :running,
      attempts: [
        %{
          state: :claimed,
          dataclip: build(:dataclip),
          starting_trigger: trigger,
          runs: []
        }
      ]
    )

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :running,
      attempts: [
        %{
          state: :started,
          dataclip: build(:dataclip),
          starting_trigger: trigger,
          runs: []
        }
      ]
    )

    attempts_success = [
      %{
        state: :success,
        dataclip: build(:dataclip),
        starting_trigger: trigger,
        runs:
          Enum.map([job0, job4, job5, job6], fn job ->
            # job6 run started but not completed
            exit_reason = if job == job6, do: nil, else: "success"
            insert(:step, job: job, exit_reason: exit_reason)
          end)
      }
    ]

    attempts_failed = [
      %{
        state: :failed,
        dataclip: build(:dataclip),
        starting_trigger: trigger,
        runs:
          Enum.map([job0, job1, job2, job3], fn job ->
            exit_reason =
              if job == job0 or job == job3, do: "fail", else: "success"

            insert(:step, job: job, exit_reason: exit_reason)
          end)
      }
    ]

    {wo_state1, wo_state2, attempts1, attempts2} =
      if last_workorder_failed? do
        {:success, :failed, attempts_success, attempts_failed}
      else
        {:failed, :success, attempts_failed, attempts_success}
      end

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: wo_state1,
      attempts: attempts1
    )

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: wo_state2,
      attempts: attempts2
    )

    workflow
  end
end
