defmodule LightningWeb.ApiWorkflowsHelpers do
  @moduledoc false
  import ExUnit.Assertions

  alias Lightning.Workflows

  def encode_decode(item) do
    item
    |> Jason.encode!()
    |> Jason.decode!()
    |> drop_workflow_state()
  end

  defp drop_workflow_state(%{"state" => _} = workflow),
    do: Map.delete(workflow, "state")

  defp drop_workflow_state(other), do: other

  # Sorted, because the database returns a workflow's jobs, edges and triggers
  # in no particular order.
  def remove_timestamps(list) when is_list(list) do
    list
    |> Enum.map(&Map.drop(&1, ["inserted_at", "updated_at"]))
    |> Enum.sort_by(& &1["id"])
  end

  def remove_timestamps(workflow) do
    Map.merge(workflow, %{
      "inserted_at" => nil,
      "updated_at" => nil,
      "edges" => remove_timestamps(workflow["edges"]),
      "jobs" => remove_timestamps(workflow["jobs"]),
      "triggers" => remove_timestamps(workflow["triggers"])
    })
  end

  def get_saved_workflow(%{id: workflow_id}),
    do: get_saved_workflow(workflow_id)

  def get_saved_workflow(workflow_id),
    do: Workflows.get_workflow(workflow_id, include: [:edges, :jobs, :triggers])

  def assert_response(response_workflow) do
    response_workflow = encode_decode(response_workflow)

    saved_workflow =
      response_workflow["id"] |> get_saved_workflow() |> encode_decode()

    assert MapSet.new(response_workflow["jobs"]) ==
             MapSet.new(saved_workflow["jobs"])

    assert MapSet.new(response_workflow["edges"]) ==
             MapSet.new(saved_workflow["edges"])

    assert MapSet.new(response_workflow["triggers"]) ==
             MapSet.new(saved_workflow["triggers"])
  end

  def pluck_to_mapset(map, keys) do
    map
    |> Enum.into(MapSet.new(), fn e ->
      Map.take(e, keys)
    end)
  end

  def graph_body(project_id, edges, opts \\ []) do
    %{
      "name" => Keyword.get(opts, :name, "ordered"),
      "project_id" => project_id,
      "triggers" => [
        %{"id" => "t", "type" => "webhook", "enabled" => true}
      ],
      "jobs" =>
        for(
          id <- ["a", "b", "c"],
          do: %{"id" => id, "name" => "job #{id}", "body" => "fn(s => s)"}
        ),
      "edges" =>
        Enum.map(edges, fn
          {"t", to} ->
            %{
              "source_trigger_id" => "t",
              "target_job_id" => to,
              "condition_type" => "always"
            }

          {from, to} ->
            %{
              "source_job_id" => from,
              "target_job_id" => to,
              "condition_type" => "on_job_success"
            }
        end)
    }
  end
end
