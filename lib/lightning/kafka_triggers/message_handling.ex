defmodule Lightning.KafkaTriggers.MessageHandling do
  @moduledoc """
  Contains the logic for ensuring that messages are processed in the order
  they are received (within the guarantees provided by Kafka for messages with
  the same key and topic).
  """
  import Ecto.Query

  alias Lightning.Extensions.Message
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.KafkaTriggers.MessageCandidateSet
  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.Repo
  alias Lightning.Services.UsageLimiter
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders

  @doc """
  This method finds all unique MessageCandidateSets present in the
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
      %MessageCandidateSet{trigger_id: trigger_id, topic: topic, key: key}
    end)
  end

  def find_nil_key_message_ids do
    query = from t in TriggerKafkaMessage, where: is_nil(t.key), select: t.id

    query |> Repo.all()
  end

  def process_candidate_for(%MessageCandidateSet{} = candidate_set) do
    Repo.transaction(fn ->
      candidate_set
      |> find_candidate_for()
      |> lock("FOR UPDATE SKIP LOCKED")
      |> Repo.one()
      |> case do
        nil ->
          nil

        %{processing_data: %{"errors" => _errors}} ->
          nil

        candidate = %{work_order: nil} ->
          create_work_order(candidate)

        candidate ->
          maybe_delete_candidate(candidate)
      end
    end)

    :ok
  end

  def process_message_for(message_id) do
    Repo.transaction(fn ->
      query =
        from t in TriggerKafkaMessage,
          where: t.id == ^message_id,
          preload: [:work_order, trigger: [:workflow]]

      query
      |> lock("FOR UPDATE SKIP LOCKED")
      |> Repo.one()
      |> case do
        nil ->
          nil

        %{processing_data: %{"errors" => _errors}} ->
          nil

        message = %{work_order: nil} ->
          create_work_order(message)

        candidate ->
          maybe_delete_candidate(candidate)
      end
    end)

    :ok
  end

  defp create_work_order(candidate) do
    %{
      data: data,
      metadata: metadata,
      trigger: %{workflow: workflow} = trigger
    } = candidate

    data
    |> Jason.decode()
    |> case do
      {:ok, body} when is_map(body) ->
        assess_workorder_creation(workflow.project_id)
        |> case do
          {:ok, without_run?} ->
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

          {:error, message} ->
            candidate |> update_with_error(message)
        end

      {:ok, _something_other_than_json} ->
        candidate |> update_with_error("Data is not a JSON object")

      {:error, _decode_error} ->
        candidate |> update_with_error("Data is not a JSON object")
    end
  end

  defp update_with_error(candidate, message) do
    processing_data =
      candidate.processing_data
      |> Map.merge(%{"errors" => [message]})

    candidate
    |> TriggerKafkaMessage.changeset(%{processing_data: processing_data})
    |> Repo.update!()
  end

  defp maybe_delete_candidate(candidate) do
    if successful?(candidate.work_order), do: Repo.delete(candidate)
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
  def find_candidate_for(%MessageCandidateSet{
        trigger_id: trigger_id,
        topic: topic,
        key: nil
      }) do
    from t in TriggerKafkaMessage,
      where: t.trigger_id == ^trigger_id and t.topic == ^topic and is_nil(t.key),
      order_by: t.offset,
      limit: 1,
      preload: [:work_order, trigger: [:workflow]]
  end

  def find_candidate_for(%MessageCandidateSet{
        trigger_id: trigger_id,
        topic: topic,
        key: key
      }) do
    from t in TriggerKafkaMessage,
      where: t.trigger_id == ^trigger_id and t.topic == ^topic and t.key == ^key,
      order_by: t.offset,
      limit: 1,
      preload: [:work_order, trigger: [:workflow]]
  end

  defp assess_workorder_creation(project_id) do
    case UsageLimiter.limit_action(
           %Action{type: :new_run},
           %Context{project_id: project_id}
         ) do
      :ok ->
        {:ok, false}

      {:error, :too_many_runs, _message} ->
        {:ok, true}

      {:error, :runs_hard_limit, %Message{text: message}} ->
        {:error, message}
    end
  end
end
