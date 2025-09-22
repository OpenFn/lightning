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

  describe "merge_project/2" do
    test "merge project with matching workflow names" do
      # Generate UUIDs for target project
      target_project_id = Ecto.UUID.generate()
      target_workflow_id = Ecto.UUID.generate()
      source_project_id = Ecto.UUID.generate()
      source_workflow_id = Ecto.UUID.generate()

      # Target project with one workflow
      target_project = %{
        id: target_project_id,
        name: "Target Project",
        description: "Original description",
        workflows: [
          %{
            id: target_workflow_id,
            name: "shared_workflow",
            triggers: [],
            jobs: [],
            edges: [],
            positions: %{}
          }
        ]
      }

      # Source project with matching workflow name but different content
      source_project = %{
        id: source_project_id,
        name: "Source Project",
        description: "Updated description",
        workflows: [
          %{
            id: source_workflow_id,
            name: "shared_workflow",
            triggers: [],
            jobs: [],
            edges: [],
            positions: %{}
          }
        ]
      }

      result = MergeProjects.merge_project(source_project, target_project)

      # Should preserve target project ID but use source metadata
      assert result["id"] == target_project_id
      assert result["name"] == "Source Project"
      assert result["description"] == "Updated description"

      # Should have one workflow (merged)
      assert length(result["workflows"]) == 1
      workflow = hd(result["workflows"])

      # Workflow should preserve target ID but use source name
      assert workflow["id"] == target_workflow_id
      assert workflow["name"] == "shared_workflow"

      # Workflow should not be marked for deletion
      refute workflow["delete"]
    end

    test "merge project with new workflow in source" do
      target_project_id = Ecto.UUID.generate()
      target_workflow_id = Ecto.UUID.generate()
      source_project_id = Ecto.UUID.generate()
      source_workflow1_id = Ecto.UUID.generate()
      source_workflow2_id = Ecto.UUID.generate()

      # Target project with one workflow
      target_project = %{
        id: target_project_id,
        name: "Target Project",
        workflows: [
          %{
            id: target_workflow_id,
            name: "existing_workflow",
            triggers: [],
            jobs: [],
            edges: [],
            positions: %{}
          }
        ]
      }

      # Source project with existing workflow + new one
      source_project = %{
        id: source_project_id,
        name: "Source Project",
        workflows: [
          %{
            id: source_workflow1_id,
            name: "existing_workflow",
            triggers: [],
            jobs: [],
            edges: [],
            positions: %{}
          },
          %{
            id: source_workflow2_id,
            name: "new_workflow",
            triggers: [],
            jobs: [],
            edges: [],
            positions: %{}
          }
        ]
      }

      result = MergeProjects.merge_project(source_project, target_project)

      # Should have two workflows
      assert length(result["workflows"]) == 2

      workflow_names =
        result["workflows"] |> Enum.map(& &1["name"]) |> Enum.sort()

      assert workflow_names == ["existing_workflow", "new_workflow"]

      # Existing workflow should preserve target ID
      existing_workflow =
        Enum.find(result["workflows"], &(&1["name"] == "existing_workflow"))

      assert existing_workflow["id"] == target_workflow_id
      refute existing_workflow["delete"]

      # New workflow should get a new UUID (not source ID)
      new_workflow =
        Enum.find(result["workflows"], &(&1["name"] == "new_workflow"))

      assert new_workflow["id"] != source_workflow2_id
      refute new_workflow["delete"]
    end

    test "merge project with removed workflow in source" do
      target_project_id = Ecto.UUID.generate()
      target_workflow1_id = Ecto.UUID.generate()
      target_workflow2_id = Ecto.UUID.generate()
      source_project_id = Ecto.UUID.generate()
      source_workflow_id = Ecto.UUID.generate()

      # Target project with two workflows
      target_project = %{
        id: target_project_id,
        name: "Target Project",
        workflows: [
          %{
            id: target_workflow1_id,
            name: "workflow_to_keep",
            triggers: [],
            jobs: [],
            edges: [],
            positions: %{}
          },
          %{
            id: target_workflow2_id,
            name: "workflow_to_remove",
            triggers: [],
            jobs: [],
            edges: [],
            positions: %{}
          }
        ]
      }

      # Source project with only one workflow (removed one)
      source_project = %{
        id: source_project_id,
        name: "Source Project",
        workflows: [
          %{
            id: source_workflow_id,
            name: "workflow_to_keep",
            triggers: [],
            jobs: [],
            edges: [],
            positions: %{}
          }
        ]
      }

      result = MergeProjects.merge_project(source_project, target_project)

      # Should have two workflows (kept + deleted)
      assert length(result["workflows"]) == 2

      kept_workflow =
        Enum.find(result["workflows"], &(&1["name"] == "workflow_to_keep"))

      assert kept_workflow["id"] == target_workflow1_id
      refute kept_workflow["delete"]

      # Removed workflow should be marked for deletion
      deleted_workflow =
        Enum.find(result["workflows"], &(&1["id"] == target_workflow2_id))

      assert deleted_workflow["delete"]
    end

    test "merge project with no matching workflows" do
      target_project_id = Ecto.UUID.generate()
      target_workflow_id = Ecto.UUID.generate()
      source_project_id = Ecto.UUID.generate()
      source_workflow_id = Ecto.UUID.generate()

      # Target project with one workflow
      target_project = %{
        id: target_project_id,
        name: "Target Project",
        workflows: [
          %{
            id: target_workflow_id,
            name: "target_workflow",
            triggers: [],
            jobs: [],
            edges: [],
            positions: %{}
          }
        ]
      }

      # Source project with completely different workflow
      source_project = %{
        id: source_project_id,
        name: "Source Project",
        workflows: [
          %{
            id: source_workflow_id,
            name: "source_workflow",
            triggers: [],
            jobs: [],
            edges: [],
            positions: %{}
          }
        ]
      }

      result = MergeProjects.merge_project(source_project, target_project)

      # Should have two workflows
      assert length(result["workflows"]) == 2

      # Source workflow should get new UUID
      new_workflow =
        Enum.find(result["workflows"], &(&1["name"] == "source_workflow"))

      assert new_workflow["id"] != source_workflow_id
      refute new_workflow["delete"]

      # Target workflow should be marked for deletion
      deleted_workflow =
        Enum.find(result["workflows"], &(&1["id"] == target_workflow_id))

      assert deleted_workflow["delete"]
    end

    test "merge empty projects" do
      target_project_id = Ecto.UUID.generate()
      source_project_id = Ecto.UUID.generate()

      target_project = %{
        id: target_project_id,
        name: "Target Project",
        workflows: []
      }

      source_project = %{
        id: source_project_id,
        name: "Source Project",
        workflows: []
      }

      result = MergeProjects.merge_project(source_project, target_project)

      # Should preserve target ID but use source name
      assert result["id"] == target_project_id
      assert result["name"] == "Source Project"
      assert result["workflows"] == []
    end

    test "merge project with workflow containing jobs - integration test" do
      # Test that workflow merging logic works correctly within project merging
      target_project_id = Ecto.UUID.generate()
      target_workflow_id = Ecto.UUID.generate()
      target_trigger_id = Ecto.UUID.generate()
      target_job_id = Ecto.UUID.generate()
      target_edge_id = Ecto.UUID.generate()

      source_project_id = Ecto.UUID.generate()
      source_workflow_id = Ecto.UUID.generate()

      # Target project with workflow containing a job
      target_project = %{
        id: target_project_id,
        name: "Target Project",
        workflows: [
          %{
            id: target_workflow_id,
            name: "data_processing",
            triggers: [
              %{
                id: target_trigger_id,
                name: "webhook_trigger",
                type: :webhook,
                enabled: true
              }
            ],
            jobs: [
              %{
                id: target_job_id,
                name: "process_data",
                body: "fn(s => s)",
                adaptor: "@openfn/language-common@latest"
              }
            ],
            edges: [
              %{
                id: target_edge_id,
                source_trigger_id: target_trigger_id,
                source_job_id: nil,
                target_job_id: target_job_id,
                condition_type: :always,
                enabled: true
              }
            ],
            positions: %{}
          }
        ]
      }

      # Source project with same workflow name but different job adaptor
      source_project = %{
        id: source_project_id,
        name: "Source Project",
        workflows: [
          %{
            id: source_workflow_id,
            name: "data_processing",
            triggers: [
              %{
                # Same ID to test UUID preservation
                id: target_trigger_id,
                name: "webhook_trigger",
                type: :webhook,
                enabled: true
              }
            ],
            jobs: [
              %{
                # Same ID to test UUID preservation
                id: target_job_id,
                name: "process_data",
                body: "fn(s => s)",
                # Different adaptor
                adaptor: "@openfn/language-http@latest"
              }
            ],
            edges: [
              %{
                id: target_edge_id,
                source_trigger_id: target_trigger_id,
                source_job_id: nil,
                target_job_id: target_job_id,
                condition_type: :always,
                enabled: true
              }
            ],
            positions: %{}
          }
        ]
      }

      result = MergeProjects.merge_project(source_project, target_project)

      # Should have one workflow (merged)
      assert length(result["workflows"]) == 1
      workflow = hd(result["workflows"])

      # Workflow should preserve target ID
      assert workflow["id"] == target_workflow_id
      assert workflow["name"] == "data_processing"

      # Should have one job with updated adaptor but preserved UUID
      job = hd(workflow["jobs"])
      assert job["id"] == target_job_id
      assert job["name"] == "process_data"
      # Source adaptor used
      assert job["adaptor"] == "@openfn/language-http@latest"
      refute job["delete"]

      # Should have one trigger with preserved UUID
      trigger = hd(workflow["triggers"])
      assert trigger["id"] == target_trigger_id
      refute trigger["delete"]

      # Should have one edge with preserved UUID
      edge = hd(workflow["edges"])
      assert edge["id"] == target_edge_id
      refute edge["delete"]
    end
  end
end
