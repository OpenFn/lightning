defmodule Lightning.InvocationFixtures do
  import Lightning.Factories

  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Invocation` context.
  """

  @doc """
  Generate a dataclip.
  """
  def dataclip_fixture(attrs \\ []) when is_list(attrs) do
    {:ok, dataclip} =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn ->
        Lightning.ProjectsFixtures.project_fixture().id
      end)
      |> Enum.into(%{
        body: %{},
        type: :http_request
      })
      |> Lightning.Invocation.create_dataclip()

    dataclip
  end

  @doc """
  Generate an work_order.
  """
  def work_order_fixture(attrs \\ []) when is_list(attrs) do
    attrs =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn ->
        Lightning.ProjectsFixtures.project_fixture().id
      end)

    {:ok, work_order} =
      attrs
      |> Keyword.put_new_lazy(:workflow_id, fn ->
        Lightning.WorkflowsFixtures.workflow_fixture(
          project_id: Keyword.get(attrs, :project_id)
        ).id
      end)
      |> Keyword.put_new_lazy(:reason_id, fn ->
        reason_fixture(project_id: Keyword.get(attrs, :project_id)).id
      end)
      |> Enum.into(%{})
      |> Lightning.WorkOrderService.create_work_order()

    work_order
  end

  @doc """
  Generate an reason.
  """
  def reason_fixture(attrs \\ []) when is_list(attrs) do
    attrs =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn ->
        Lightning.ProjectsFixtures.project_fixture().id
      end)

    {:ok, reason} =
      attrs
      |> Keyword.put_new_lazy(:dataclip_id, fn ->
        dataclip_fixture(project_id: Keyword.get(attrs, :project_id)).id
      end)
      |> Keyword.put_new_lazy(:trigger_id, fn ->
        # DEPRECATED: remove me
        insert(:trigger).id
      end)
      |> Enum.into(%{
        type: :webhook
      })
      |> Lightning.InvocationReasons.create_reason()

    reason
  end

  @doc """
  Generate a run.
  """
  def run_fixture(attrs \\ []) when is_list(attrs) do
    attrs =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn ->
        Lightning.ProjectsFixtures.project_fixture().id
      end)

    {:ok, run} =
      attrs
      |> Keyword.put_new_lazy(:job_id, fn ->
        Lightning.JobsFixtures.job_fixture(project_id: attrs[:project_id]).id
      end)
      |> Keyword.put_new_lazy(:input_dataclip_id, fn ->
        dataclip_fixture(project_id: attrs[:project_id]).id
      end)
      |> Enum.into(%{
        exit_reason: nil,
        finished_at: nil,
        log: [],
        event_id: nil,
        started_at: nil
      })
      |> Lightning.Invocation.create_run()

    run
  end
end
