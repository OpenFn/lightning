defmodule Lightning.KafkaTriggers.MessageHandling do
  @moduledoc """
  Contains the logic for ensuring that messages are processed in the order
  they are received (within the guarantees provided by Kafka for messages with
  the same key and topic).
  """

  alias Lightning.Extensions.Message
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Repo
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows.Trigger
  alias Lightning.WorkOrders

  def persist_message(multi, trigger_id, message) do
    trigger =
      Trigger
      |> Repo.get(trigger_id)
      |> Repo.preload(:workflow)

    create_work_order(message, trigger, multi)
  end

  defp create_work_order(%Broadway.Message{} = message, trigger, multi) do
    %{data: data, metadata: request} = message
    %{workflow: workflow} = trigger

    data
    |> Jason.decode()
    |> case do
      {:ok, body} when is_map(body) ->
        assess_workorder_creation(workflow.project_id)
        |> case do
          {:ok, without_run?} ->
            WorkOrders.create_for(
              trigger,
              multi,
              workflow: workflow,
              dataclip: %{
                body: body,
                request: request,
                type: :kafka,
                project_id: workflow.project_id
              },
              without_run: without_run?
            )

          {:error, message} ->
            {:error, :work_order_creation_blocked, message}
        end

      {:ok, _something_other_than_map} ->
        {:error, :data_is_not_json_object}

      {:error, _decode_error} ->
        {:error, :data_is_not_json_object}
    end
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
