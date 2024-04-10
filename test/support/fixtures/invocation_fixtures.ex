defmodule Lightning.InvocationFixtures do
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
  Generate a step.
  """
  def step_fixture(attrs \\ []) when is_list(attrs) do
    attrs =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn ->
        Lightning.ProjectsFixtures.project_fixture().id
      end)

    {:ok, step} =
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
      |> Lightning.Invocation.create_step()

    step
  end
end
