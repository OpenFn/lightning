defmodule Lightning.InvocationFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Invocation` context.
  """

  @doc """
  Generate a dataclip.
  """
  def dataclip_fixture(attrs \\ %{}) do
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
  def event_fixture(attrs \\ %{}) do
    {:ok, event} =
      attrs
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
  def run_fixture(attrs \\ %{}) do
    {:ok, run} =
      attrs
      |> Enum.into(%{
        exit_code: nil,
        finished_at: nil,
        log: [],
        event_id: nil,
        started_at: nil
      })
      |> Map.update!(:event_id, fn event_id ->
        if event_id do
          event_id
        else
          event_fixture().id
        end
      end)
      |> Lightning.Invocation.create_run()

    run
  end
end
