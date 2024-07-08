defmodule Lightning.KafkaTriggers.MessageHandling do
  import Ecto.Query

  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.Repo
  alias Lightning.Services.UsageLimiter
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders

  @doc """
  This method finds all unique MessageCandidateSetIDs present in the
  `TriggerKafkaMessage` table.
  """
  def find_message_candidate_sets do
    query =
      from t in TriggerKafkaMessage,
        select: [t.trigger_id, t.topic, t.key],
        distinct: [t.trigger_id, t.topic, t.key]

    query
    |> Repo.all()
    |> Enum.map(fn [trigger_id, topic, key] ->
      %{trigger_id: trigger_id, topic: topic, key: key}
    end)
  end

  def process_candidate_for(candidate_set) do
    Repo.transaction(fn ->
      candidate_set
      |> find_candidate_for()
      |> lock("FOR UPDATE SKIP LOCKED")
      |> Repo.one()
      |> case do
        nil ->
          nil

        candidate ->
          handle_candidate(candidate)
      end
    end)

    :ok
  end

  # Take the appropriate action based on the state of the candidate.
  # TODO If this method was public, it may make simpler tests possible.
  defp handle_candidate(%{work_order: nil} = candidate) do
    %{
      data: data,
      metadata: metadata,
      trigger: %{workflow: workflow} = trigger
    } = candidate

    data
    |> Jason.decode()
    |> case do
      {:ok, body} ->
        {:ok, without_run?} = check_skip_run_creation(workflow.project_id)

        {:ok, %WorkOrder{id: work_order_id}} =
          WorkOrders.create_for(trigger,
            workflow: workflow,
            dataclip: %{
              body: body,
              request: metadata,
              type: :kafka,
              project_id: workflow.project_id
            },
            without_run: without_run?
          )

        candidate
        |> TriggerKafkaMessage.changeset(%{work_order_id: work_order_id})
        |> Repo.update!()

      {:error, _decode_error} ->
        # TODO Add details from _decode_error?

        processing_data =
          candidate.processing_data
          |> Map.merge(%{"errors" => ["Data is not a JSON object"]})

        candidate
        |> TriggerKafkaMessage.changeset(%{processing_data: processing_data})
        |> Repo.update!()
    end
  end

  defp handle_candidate(%{work_order: work_order} = candidate) do
    if successful?(work_order), do: candidate |> Repo.delete()
  end

  def successful?(%{state: state}) do
    state == :success
  end

  @doc """
  Find the MessageCandidateSetCandidate for the MessageCandidateSet identified
  by the MessageCanididateSetID (i.e. trigger_id, topic, key).

  Within the current implementation, this no longer needs to be a public method,
  but having it as a public method allows for easier testing.
  """
  def find_candidate_for(%{trigger_id: trigger_id, topic: topic, key: nil}) do
    from t in TriggerKafkaMessage,
      where: t.trigger_id == ^trigger_id and t.topic == ^topic and is_nil(t.key),
      order_by: t.offset,
      limit: 1,
      preload: [:work_order, trigger: [:workflow]]
  end

  def find_candidate_for(%{trigger_id: trigger_id, topic: topic, key: key}) do
    from t in TriggerKafkaMessage,
      where: t.trigger_id == ^trigger_id and t.topic == ^topic and t.key == ^key,
      order_by: t.offset,
      limit: 1,
      preload: [:work_order, trigger: [:workflow]]
  end

  # Stolen from the `webhooks_controller.ex` file and simplified until
  # I understand the details (ask Roger).
  defp check_skip_run_creation(project_id) do
    case UsageLimiter.limit_action(
           %Action{type: :new_run},
           %Context{project_id: project_id}
         ) do
      :ok ->
        {:ok, false}

      {:error, :too_many_runs, _message} ->
        {:ok, true}

      error ->
        error
    end
  end
end
