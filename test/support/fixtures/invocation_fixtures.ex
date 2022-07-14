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
  Generate an event.
  """
  def event_fixture(attrs \\ []) when is_list(attrs) do
    attrs =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn ->
        Lightning.ProjectsFixtures.project_fixture().id
      end)

    {:ok, event} =
      attrs
      |> Keyword.put_new_lazy(:dataclip_id, fn ->
        dataclip_fixture(project_id: Keyword.get(attrs, :project_id)).id
      end)
      |> Keyword.put_new_lazy(:job_id, fn ->
        Lightning.JobsFixtures.job_fixture().id
      end)
      |> Enum.into(%{
        type: :webhook
      })
      |> Lightning.Invocation.create_event()

    event
  end

  @doc """
  Generate a run.
  """
  def run_fixture(attrs \\ []) when is_list(attrs) do
    {event_attrs, attrs} = Keyword.pop(attrs, :event_attrs, [])

    {:ok, run} =
      attrs
      |> Keyword.put_new_lazy(:event_id, fn -> event_fixture(event_attrs).id end)
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
