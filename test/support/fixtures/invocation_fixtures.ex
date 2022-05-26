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
      |> Enum.into(%{
        body: %{},
        type: :http_request
      })
      |> Lightning.Invocation.create_dataclip()

    dataclip
  end

  @doc """
  Generate a dataclip.
  """
  def event_fixture(attrs \\ []) when is_list(attrs) do
    {:ok, event} =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn ->
        Lightning.ProjectsFixtures.project_fixture().id
      end)
      |> Enum.into(%{
        type: :webhook,
        dataclip_id: dataclip_fixture().id,
        job_id: Lightning.JobsFixtures.job_fixture().id
      })
      |> Lightning.Invocation.create_event()

    event
  end

  @doc """
  Generate a run.
  """
  def run_fixture(attrs \\ []) when is_list(attrs) do
    {:ok, run} =
      attrs
      |> Keyword.put_new_lazy(:event_id, fn -> event_fixture().id end)
      |> Enum.into(%{
        exit_code: nil,
        finished_at: nil,
        log: [],
        event_id: nil,
        started_at: nil
      })
      |> Lightning.Invocation.create_run()

    run
  end
end
