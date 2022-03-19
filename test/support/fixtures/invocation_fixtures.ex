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
        dataclip: dataclip_fixture()
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
        exit_code: 42,
        finished_at: ~U[2022-02-02 11:49:00.000000Z],
        log: [],
        event_id: nil,
        started_at: ~U[2022-02-02 11:49:00.000000Z]
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
