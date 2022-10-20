defmodule Lightning.AttemptService do
  @moduledoc """
  The Attempts context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo
  alias Lightning.Attempt
  alias Lightning.Invocation.{Event, Run}

  @doc """
  Creates a reason.

  ## Examples

      iex> create_attempt(%{field: value})
      {:ok, %Attempt{}}

      iex> create_attempt(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """

  def create_attempt(workorder, job, reason) do
    project_id = job.workflow.project_id
    dataclip_id = reason.dataclip_id

    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :event,
      Event.changeset(%Event{}, %{
        type: :webhook,
        job_id: job.id,
        project_id: project_id,
        dataclip_id: dataclip_id
      })
    )
    |> Ecto.Multi.insert(:run, fn %{event: %Event{id: event_id}} ->
      Run.changeset(%Run{}, %{
        event_id: event_id,
        project_id: project_id,
        job_id: job.id,
        input_dataclip_id: dataclip_id,
        # not sure why we need this !
        output_dataclip: nil
      })
    end)
    |> Ecto.Multi.insert(:attempt, fn %{run: run} ->
      Attempt.changeset(%Attempt{}, %{
        workorder_id: workorder.id,
        reason_id: reason.id,
        runs: [Map.from_struct(run)]
      })
    end)
    |> Repo.transaction()
  end
end
