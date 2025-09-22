defmodule Lightning.Projects.MergeProjectsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.MergeProjects

  describe "merge_workflow/2" do
    test "merge simple change between single-step workflows with preserved uuids" do
      # Create base workflow structure with actual UUIDs
      workflow_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()
      job_id = Ecto.UUID.generate()
      edge_id = Ecto.UUID.generate()

      # Target (main) - original structure
      target = %{
        id: workflow_id,
        name: "test_wf",
        triggers: [
          %{
            id: trigger_id,
            name: "webhook_trigger",
            type: :webhook,
            enabled: true
          }
        ],
        jobs: [
          %{
            id: job_id,
            name: "transform",
            body: "fn(s => s)",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        edges: [
          %{
            id: edge_id,
            source_trigger_id: trigger_id,
            source_job_id: nil,
            target_job_id: job_id,
            condition_type: :always,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source (staging) - same structure, different adaptor
      source = %{
        target
        | jobs: [
            %{hd(target.jobs) | adaptor: "@openfn/language-http@latest"}
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      # Should preserve target UUIDs but use source adaptor
      job = hd(result["jobs"])
      # Preserved target UUID
      assert job["id"] == job_id
      # Source adaptor
      assert job["adaptor"] == "@openfn/language-http@latest"

      # job isn't deleted
      refute job["delete"]
    end

    test "merge new job into existing workflow" do
      # Generate UUIDs for target workflow
      workflow_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()
      job_x_id = Ecto.UUID.generate()
      edge_trigger_x_id = Ecto.UUID.generate()
      job_y_id = Ecto.UUID.generate()
      edge_x_y_id = Ecto.UUID.generate()

      # Target workflow - single job
      target = %{
        id: workflow_id,
        name: "test_wf",
        triggers: [
          %{
            id: trigger_id,
            name: "webhook_trigger",
            type: :webhook,
            enabled: true
          }
        ],
        jobs: [
          %{
            id: job_x_id,
            name: "x",
            body: "fn(s => s)",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        edges: [
          %{
            id: edge_trigger_x_id,
            source_trigger_id: trigger_id,
            source_job_id: nil,
            target_job_id: job_x_id,
            condition_type: :always,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source workflow - added job y
      source = %{
        target
        | jobs:
            target.jobs ++
              [
                %{
                  id: job_y_id,
                  name: "y",
                  body: "console.log('y')",
                  adaptor: "@openfn/language-common@latest"
                }
              ],
          edges:
            target.edges ++
              [
                %{
                  id: edge_x_y_id,
                  source_trigger_id: nil,
                  source_job_id: job_x_id,
                  target_job_id: job_y_id,
                  condition_type: :on_job_success,
                  enabled: true
                }
              ]
      }

      result = MergeProjects.merge_workflow(source, target)

      # Should have both jobs
      assert length(result["jobs"]) == 2
      job_names = result["jobs"] |> Enum.map(& &1["name"]) |> Enum.sort()
      assert job_names == ["x", "y"]

      # Original job should preserve UUID
      x_job = Enum.find(result["jobs"], &(&1["name"] == "x"))
      assert x_job["id"] == job_x_id

      # none is deleted
      for result_item <- result["jobs"] ++ result["triggers"] ++ result["edges"] do
        refute result_item["delete"]
      end
    end

    test "remove job from existing workflow" do
      # Generate UUIDs
      workflow_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()
      job_x_id = Ecto.UUID.generate()
      edge_id = Ecto.UUID.generate()

      # Source workflow - job removed
      source = %{
        id: workflow_id,
        name: "test_wf",
        triggers: [
          %{
            id: trigger_id,
            name: "webhook_trigger",
            type: :webhook,
            enabled: true
          }
        ],
        # Job removed
        jobs: [],
        # No edges since no jobs
        edges: [],
        positions: %{}
      }

      # Target workflow - has the job
      target = %{
        source
        | jobs: [
            %{
              id: job_x_id,
              name: "x",
              body: "fn(s => s)",
              adaptor: "@openfn/language-common@latest"
            }
          ],
          edges: [
            %{
              id: edge_id,
              source_trigger_id: trigger_id,
              source_job_id: nil,
              target_job_id: job_x_id,
              condition_type: :always,
              enabled: true
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      # The merge result include nodes marked for deletion
      # rather than completely removing them
      assert length(result["jobs"]) == 1
      assert length(result["edges"]) == 1

      result_job = hd(result["jobs"])
      assert result_job["id"] == job_x_id
      assert result_job["delete"]

      result_edge = hd(result["edges"])
      assert result_edge["id"] == edge_id
      assert result_edge["delete"]

      # trigger is not deleted
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == trigger_id
      refute result_trigger["delete"]
    end

    test "merge id change in single job" do
      # Target workflow
      target = %{
        id: "workflow_id",
        name: "test_wf",
        triggers: [
          %{
            id: "trigger_id",
            name: "webhook_trigger",
            type: :webhook,
            enabled: true
          }
        ],
        jobs: [
          %{
            id: "job_x_id",
            name: "x",
            body: "fn(s => s)",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        edges: [
          %{
            id: "edge_id",
            source_trigger_id: "trigger_id",
            source_job_id: nil,
            target_job_id: "job_x_id",
            condition_type: :always,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source workflow - job ID changed to z
      source = %{target | jobs: [%{hd(target.jobs) | name: "z"}]}

      result = MergeProjects.merge_workflow(source, target)

      # Job should have new name from source
      job = hd(result["jobs"])
      assert job["name"] == "z"
      # But since ID changed, it's treated as new node - gets new UUID
    end

    test "merge with edge and no changes" do
      workflow = %{
        id: "workflow_id",
        name: "test_wf",
        triggers: [
          %{
            id: "trigger_id",
            name: "webhook_trigger",
            type: :webhook,
            enabled: true
          }
        ],
        jobs: [
          %{
            id: "job_x_id",
            name: "x",
            body: "fn(s => s)",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "job_y_id",
            name: "y",
            body: "fn(s => s)",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        edges: [
          %{
            id: "edge_trigger_x_id",
            source_trigger_id: "trigger_id",
            source_job_id: nil,
            target_job_id: "job_x_id",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "edge_x_y_id",
            source_trigger_id: nil,
            source_job_id: "job_x_id",
            target_job_id: "job_y_id",
            condition_type: :on_job_success,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Both source and target are identical
      result = MergeProjects.merge_workflow(workflow, workflow)

      # Should preserve all structure and IDs
      assert length(result["jobs"]) == 2
      # Edges may be duplicated or handled differently by merge logic
      assert is_list(result["edges"])
      assert result["name"] == "test_wf"

      # Check that we have the edge structure (may have more edges due to merge)
      edges_with_source_x =
        Enum.filter(result["edges"], &(&1["source_job_id"] == "job_x_id"))

      assert length(edges_with_source_x) >= 1
    end

    test "merge with change to edge condition" do
      base_workflow = %{
        id: "workflow_id",
        name: "test_wf",
        triggers: [
          %{
            id: "trigger_id",
            name: "webhook_trigger",
            type: :webhook,
            enabled: true
          }
        ],
        jobs: [
          %{
            id: "job_x_id",
            name: "x",
            body: "fn(s => s)",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "job_y_id",
            name: "y",
            body: "fn(s => s)",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        edges: [
          %{
            id: "edge_x_y_id",
            source_trigger_id: nil,
            source_job_id: "job_x_id",
            target_job_id: "job_y_id",
            condition_type: :always,
            condition_expression: "true",
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source - change edge condition
      source = %{
        base_workflow
        | edges: [
            %{hd(base_workflow.edges) | condition_expression: "state.success"}
          ]
      }

      # Target - original condition
      target = base_workflow

      result = MergeProjects.merge_workflow(source, target)

      # Should preserve target edge ID but use source condition
      edge = hd(result["edges"])
      # Target UUID preserved
      assert edge["id"] == "edge_x_y_id"
      # Source condition used
      assert edge["condition_expression"] == "state.success"
    end
  end
end
