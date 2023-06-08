defmodule LightningWeb.WorkflowNewLive.WorkflowParamsTest do
  use ExUnit.Case, async: true

  alias LightningWeb.WorkflowNewLive.WorkflowParams
  alias Lightning.Workflows.Workflow

  setup do
    workflow = %Workflow{}
    job_1_id = Ecto.UUID.generate()
    job_2_id = Ecto.UUID.generate()
    trigger_1_id = Ecto.UUID.generate()

    params = %{
      "name" => nil,
      "project_id" => nil,
      "jobs" => [
        %{"id" => job_1_id, "name" => ""},
        %{"id" => job_2_id, "name" => "job-2"}
      ],
      "triggers" => [
        %{"id" => trigger_1_id, "type" => "webhook"}
      ],
      "edges" => [
        %{
          "id" => Ecto.UUID.generate(),
          "source_trigger_id" => trigger_1_id,
          "condition" => "on_job_failure",
          "target_job_id" => job_1_id
        },
        %{
          "id" => Ecto.UUID.generate(),
          "source_job_id" => job_1_id,
          "condition" => "on_job_success",
          "target_job_id" => job_2_id
        }
      ]
    }

    changeset = workflow |> Workflow.changeset(params)

    %{
      changeset: changeset,
      job_1_id: job_1_id,
      job_2_id: job_2_id,
      trigger_1_id: trigger_1_id
    }
  end

  describe "to_map/1" do
    test "creates a serializable map for a Workflow changeset", %{
      changeset: changeset,
      job_1_id: job_1_id,
      job_2_id: job_2_id,
      trigger_1_id: trigger_1_id
    } do
      assert %{
               "edges" => [
                 %{
                   "condition" => "on_job_failure",
                   "errors" => %{},
                   "id" => _,
                   "source_job_id" => nil,
                   "source_trigger_id" => ^trigger_1_id,
                   "target_job_id" => ^job_1_id
                 },
                 %{
                   "condition" => "on_job_success",
                   "errors" => %{},
                   "id" => _,
                   "source_job_id" => ^job_1_id,
                   "source_trigger_id" => nil,
                   "target_job_id" => ^job_2_id
                 }
               ],
               "jobs" => [
                 %{
                   "errors" => %{"name" => ["can't be blank"]},
                   "id" => ^job_1_id,
                   "name" => ""
                 },
                 %{
                   "errors" => %{},
                   "id" => ^job_2_id,
                   "name" => "job-2"
                 }
               ],
               "triggers" => [
                 %{
                   "errors" => %{},
                   "id" => ^trigger_1_id,
                   "type" => "webhook"
                 }
               ]
             } = changeset |> WorkflowParams.to_map()
    end
  end

  describe "to_patches/2" do
    setup %{changeset: changeset} do
      original_params = changeset |> WorkflowParams.to_map()

      params =
        changeset
        |> Ecto.Changeset.put_change(:jobs, [])
        |> WorkflowParams.to_map()

      %{
        original_params: original_params,
        params: params
      }
    end

    test "creates a list of patches for a Workflow changeset", %{
      original_params: original_params,
      params: params
    } do
      assert WorkflowParams.to_patches(original_params, params) ==
               [
                 # Remove when https://github.com/corka149/jsonpatch/issues/16
                 # is fixed and released.
                 %{op: "add", path: "/project_id", value: nil},
                 %{op: "remove", path: "/jobs/1"},
                 %{op: "remove", path: "/jobs/0"}
               ]
    end
  end
end
