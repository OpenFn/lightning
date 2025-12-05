defmodule Lightning.KafkaTriggers.MessageHandling do
  @moduledoc """
  Contains the logic to persist a Kafka messages as a WorkOrder, Run and
  Dataclip.
  """

  alias Lightning.Repo
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
    %{data: data, metadata: metadata} = message
    %{workflow: workflow} = trigger

    request = metadata |> convert_headers_for_serialisation()

    with {:ok, body} <- Jason.decode(data),
         true <- is_map(body),
         {:ok, without_run?} <- assess_workorder_creation(workflow.project_id),
         {:ok, work_order} <-
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
           ) do
      {:ok, work_order}
    else
      {:error, %Ecto.Changeset{} = error_changeset} ->
        {:error, error_changeset}

      {:error, %Jason.DecodeError{}} ->
        {:error, :data_is_not_json}

      false ->
        {:error, :data_is_not_json_object}

      {:error, message} ->
        {:error, :work_order_creation_blocked, message}
    end
  end

  defp assess_workorder_creation(project_id) do
    case WorkOrders.limit_run_creation(project_id) do
      :ok ->
        {:ok, false}

      {:error, :too_many_runs, _message} ->
        {:ok, true}

      {:error, :runs_hard_limit, %Lightning.Extensions.Message{text: message}} ->
        {:error, message}
    end
  end

  def convert_headers_for_serialisation(%{headers: headers} = metadata) do
    converted_headers =
      headers
      |> Enum.map(fn
        {key, value} ->
          [key, value]

        [key, value] ->
          [key, value]
      end)

    Map.put(metadata, :headers, converted_headers)
  end
end
