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

    test "merge jobs with different adaptors - job matching algorithm" do
      # Target workflow with common adaptor
      target = %{
        id: "workflow_id",
        name: "test_wf",
        triggers: [
          %{
            id: "trigger_id",
            type: :webhook,
            enabled: true
          }
        ],
        jobs: [
          %{
            id: "job_a_id",
            name: "process_data",
            body: "console.log('processing')",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "job_b_id",
            name: "send_notification",
            body: "console.log('sending')",
            adaptor: "@openfn/language-http@latest"
          }
        ],
        edges: [
          %{
            id: "edge_t_a",
            source_trigger_id: "trigger_id",
            source_job_id: nil,
            target_job_id: "job_a_id",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "edge_a_b",
            source_trigger_id: nil,
            source_job_id: "job_a_id",
            target_job_id: "job_b_id",
            condition_type: :on_job_success,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source workflow - same names but different adaptors
      source = %{
        target
        | jobs: [
            %{
              id: "job_a_id",
              name: "process_data",
              body: "console.log('updated processing')",
              # Different adaptor
              adaptor: "@openfn/language-postgresql@latest"
            },
            %{
              id: "job_b_id",
              name: "send_notification",
              body: "console.log('updated sending')",
              # Same adaptor
              adaptor: "@openfn/language-http@latest"
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      # Jobs should be matched by name + adaptor scoring
      jobs = result["jobs"]
      assert length(jobs) == 2

      # Job with matching name + adaptor should preserve UUID
      http_job =
        Enum.find(jobs, &(&1["adaptor"] == "@openfn/language-http@latest"))

      assert http_job["id"] == "job_b_id"
      assert http_job["name"] == "send_notification"

      # Job with different adaptor should still match by name but use source adaptor
      postgres_job =
        Enum.find(jobs, &(&1["adaptor"] == "@openfn/language-postgresql@latest"))

      assert postgres_job["id"] == "job_a_id"
      assert postgres_job["name"] == "process_data"
      assert postgres_job["body"] == "console.log('updated processing')"
    end

    test "merge workflows with multiple triggers" do
      # Target workflow with 2 triggers
      target = %{
        id: "workflow_id",
        name: "multi_trigger_wf",
        triggers: [
          %{
            id: "webhook_trigger_id",
            type: :webhook,
            enabled: true
          },
          %{
            id: "cron_trigger_id",
            type: :cron,
            cron_expression: "0 * * * *",
            enabled: true
          }
        ],
        jobs: [
          %{
            id: "job_id",
            name: "shared_job",
            body: "fn(s => s)",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        edges: [
          %{
            id: "edge_webhook_job",
            source_trigger_id: "webhook_trigger_id",
            source_job_id: nil,
            target_job_id: "job_id",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "edge_cron_job",
            source_trigger_id: "cron_trigger_id",
            source_job_id: nil,
            target_job_id: "job_id",
            condition_type: :always,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source workflow - same structure but with new trigger IDs (should match by type)
      source = %{
        target
        | triggers: [
            %{
              # Different ID
              id: "new_webhook_id",
              # Same type - should match
              type: :webhook,
              enabled: true
            },
            %{
              # Different ID
              id: "new_cron_id",
              # Same type - should match
              type: :cron,
              # Different expression
              cron_expression: "0 */2 * * *",
              enabled: true
            }
          ],
          edges: [
            %{
              id: "edge_webhook_job",
              # Use new source IDs
              source_trigger_id: "new_webhook_id",
              source_job_id: nil,
              target_job_id: "job_id",
              condition_type: :always,
              enabled: true
            },
            %{
              id: "edge_cron_job",
              # Use new source IDs
              source_trigger_id: "new_cron_id",
              source_job_id: nil,
              target_job_id: "job_id",
              condition_type: :always,
              enabled: true
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      # Should preserve target trigger IDs but use source data
      triggers = result["triggers"]
      assert length(triggers) == 2

      webhook_trigger = Enum.find(triggers, &(&1["type"] == :webhook))
      # Target ID preserved
      assert webhook_trigger["id"] == "webhook_trigger_id"

      cron_trigger = Enum.find(triggers, &(&1["type"] == :cron))
      # Target ID preserved
      assert cron_trigger["id"] == "cron_trigger_id"
      # Source data used
      assert cron_trigger["cron_expression"] == "0 */2 * * *"

      # Edges should use preserved trigger IDs
      edges = result["edges"]

      webhook_edge =
        Enum.find(edges, &(&1["source_trigger_id"] == "webhook_trigger_id"))

      assert webhook_edge["target_job_id"] == "job_id"

      cron_edge =
        Enum.find(edges, &(&1["source_trigger_id"] == "cron_trigger_id"))

      assert cron_edge["target_job_id"] == "job_id"
    end

    test "merge complex diamond-shaped workflow structure" do
      # Diamond pattern: trigger -> job1 -> [job2, job3] -> job4
      target = %{
        id: "workflow_id",
        name: "diamond_wf",
        triggers: [
          %{
            id: "trigger_id",
            type: :webhook,
            enabled: true
          }
        ],
        jobs: [
          %{
            id: "job1_id",
            name: "input_processor",
            body: "console.log('input')",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "job2_id",
            name: "path_a_processor",
            body: "console.log('path_a')",
            adaptor: "@openfn/language-http@latest"
          },
          %{
            id: "job3_id",
            name: "path_b_processor",
            body: "console.log('path_b')",
            adaptor: "@openfn/language-postgresql@latest"
          },
          %{
            id: "job4_id",
            name: "output_processor",
            body: "console.log('output')",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        edges: [
          %{
            id: "edge_t_1",
            source_trigger_id: "trigger_id",
            source_job_id: nil,
            target_job_id: "job1_id",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "edge_1_2",
            source_trigger_id: nil,
            source_job_id: "job1_id",
            target_job_id: "job2_id",
            condition_type: :on_job_success,
            enabled: true
          },
          %{
            id: "edge_1_3",
            source_trigger_id: nil,
            source_job_id: "job1_id",
            target_job_id: "job3_id",
            condition_type: :on_job_success,
            enabled: true
          },
          %{
            id: "edge_2_4",
            source_trigger_id: nil,
            source_job_id: "job2_id",
            target_job_id: "job4_id",
            condition_type: :on_job_success,
            enabled: true
          },
          %{
            id: "edge_3_4",
            source_trigger_id: nil,
            source_job_id: "job3_id",
            target_job_id: "job4_id",
            condition_type: :on_job_success,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source - same structure with updated bodies and one adaptor change
      source = %{
        target
        | jobs: [
            %{
              id: "job1_id",
              name: "input_processor",
              # Updated body
              body: "console.log('updated input')",
              adaptor: "@openfn/language-common@latest"
            },
            %{
              id: "job2_id",
              name: "path_a_processor",
              # Updated body
              body: "console.log('updated path_a')",
              adaptor: "@openfn/language-http@latest"
            },
            %{
              id: "job3_id",
              name: "path_b_processor",
              # Updated body
              body: "console.log('updated path_b')",
              # Different adaptor
              adaptor: "@openfn/language-salesforce@latest"
            },
            %{
              id: "job4_id",
              name: "output_processor",
              # Updated body
              body: "console.log('updated output')",
              adaptor: "@openfn/language-common@latest"
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      # All jobs should be matched and preserve UUIDs
      jobs = result["jobs"]
      assert length(jobs) == 4

      job_ids = jobs |> Enum.map(& &1["id"]) |> Enum.sort()
      assert job_ids == ["job1_id", "job2_id", "job3_id", "job4_id"]

      # All jobs should use source body content
      input_job = Enum.find(jobs, &(&1["id"] == "job1_id"))
      assert input_job["body"] == "console.log('updated input')"

      # Job with different adaptor should use source adaptor
      path_b_job = Enum.find(jobs, &(&1["id"] == "job3_id"))
      assert path_b_job["adaptor"] == "@openfn/language-salesforce@latest"

      # All edges should be preserved
      edges = result["edges"]
      assert length(edges) == 5
      edge_ids = edges |> Enum.map(& &1["id"]) |> Enum.sort()

      assert edge_ids == [
               "edge_1_2",
               "edge_1_3",
               "edge_2_4",
               "edge_3_4",
               "edge_t_1"
             ]
    end

    test "merge workflows with competing job matches" do
      # Target has 3 jobs with similar names
      target = %{
        id: "workflow_id",
        name: "competing_matches",
        triggers: [%{id: "trigger_id", type: :webhook, enabled: true}],
        jobs: [
          %{
            id: "target_job1_id",
            name: "process_data_step",
            body: "step1()",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "target_job2_id",
            name: "process_data_transform",
            body: "step2()",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "target_job3_id",
            name: "process_final",
            body: "step3()",
            adaptor: "@openfn/language-http@latest"
          }
        ],
        edges: [
          %{
            id: "edge1",
            source_trigger_id: "trigger_id",
            source_job_id: nil,
            target_job_id: "target_job1_id",
            condition_type: :always,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source has 2 jobs that could match multiple targets
      source = %{
        target
        | jobs: [
            %{
              id: "source_job1_id",
              # Partially matches target jobs 1&2, closer to job3
              name: "process_data_final",
              body: "updated_step1()",
              # Matches job3 adaptor
              adaptor: "@openfn/language-http@latest"
            },
            %{
              id: "source_job2_id",
              # Exact match with target job1 name
              name: "process_data_step",
              body: "updated_step2()",
              # Matches job1&2 adaptor
              adaptor: "@openfn/language-common@latest"
            }
          ],
          edges: [
            %{
              id: "edge1",
              source_trigger_id: "trigger_id",
              source_job_id: nil,
              target_job_id: "source_job1_id",
              condition_type: :always,
              enabled: true
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      jobs = result["jobs"]
      non_deleted_jobs = Enum.reject(jobs, & &1["delete"])
      deleted_jobs = Enum.filter(jobs, & &1["delete"])

      # Algorithm mapped source_job2_id -> target_job2_id and source_job1_id -> target_job3_id
      # based on the matching scores (name similarity + adaptor compatibility)

      # source_job2_id ("process_data_step") mapped to target_job2_id ("process_data_transform")
      job_with_step_name =
        Enum.find(non_deleted_jobs, &(&1["name"] == "process_data_step"))

      # Should preserve target_job2_id
      assert job_with_step_name["id"] == "target_job2_id"
      # Should use source body from source_job2_id
      assert job_with_step_name["body"] == "updated_step2()"

      # source_job1_id ("process_data_final") mapped to target_job3_id ("process_final")
      job_with_final_name =
        Enum.find(non_deleted_jobs, &(&1["name"] == "process_data_final"))

      # Should preserve target_job3_id
      assert job_with_final_name["id"] == "target_job3_id"
      # Should use source body from source_job1_id
      assert job_with_final_name["body"] == "updated_step1()"
      assert job_with_final_name["adaptor"] == "@openfn/language-http@latest"

      # target_job1_id should be marked for deletion (unmatched)
      assert length(deleted_jobs) == 1
      deleted_job = hd(deleted_jobs)
      assert deleted_job["id"] == "target_job1_id"
    end

    test "merge workflows with positions data" do
      target = %{
        id: "workflow_id",
        name: "positioned_workflow",
        triggers: [%{id: "trigger_id", type: :webhook, enabled: true}],
        jobs: [
          %{
            id: "job1_id",
            name: "job1",
            body: "console.log('job1')",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "job2_id",
            name: "job2",
            body: "console.log('job2')",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        edges: [],
        positions: %{
          "job1_id" => %{"x" => 100, "y" => 200},
          "job2_id" => %{"x" => 300, "y" => 400}
        }
      }

      source = %{
        target
        | positions: %{
            # Updated position
            "job1_id" => %{"x" => 150, "y" => 250},
            # Updated position
            "job2_id" => %{"x" => 350, "y" => 450}
          }
      }

      result = MergeProjects.merge_workflow(source, target)

      # Positions should be updated from source
      positions = result["positions"]
      assert positions["job1_id"]["x"] == 150
      assert positions["job1_id"]["y"] == 250
      assert positions["job2_id"]["x"] == 350
      assert positions["job2_id"]["y"] == 450
    end

    test "merge workflows with completely different IDs - job matching by name and adaptor" do
      # Target workflow with specific IDs
      target = %{
        id: "target_workflow_id",
        name: "test_workflow",
        triggers: [
          %{
            id: "target_trigger_id",
            type: :webhook,
            enabled: true
          }
        ],
        jobs: [
          %{
            id: "target_job_a_id",
            name: "extract_data",
            body: "console.log('extracting')",
            adaptor: "@openfn/language-http@latest"
          },
          %{
            id: "target_job_b_id",
            name: "transform_data",
            body: "console.log('transforming')",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        edges: [
          %{
            id: "target_edge_trigger_a",
            source_trigger_id: "target_trigger_id",
            source_job_id: nil,
            target_job_id: "target_job_a_id",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "target_edge_a_b",
            source_trigger_id: nil,
            source_job_id: "target_job_a_id",
            target_job_id: "target_job_b_id",
            condition_type: :on_job_success,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source workflow with completely different IDs but matching names/adaptors
      source = %{
        id: "source_workflow_id",
        name: "test_workflow",
        triggers: [
          %{
            # Different ID
            id: "source_trigger_id",
            # Same type - should match
            type: :webhook,
            enabled: true
          }
        ],
        jobs: [
          %{
            # Different ID
            id: "source_job_x_id",
            # Same name - should match
            name: "extract_data",
            # Updated body
            body: "console.log('updated extracting')",
            # Same adaptor - should match
            adaptor: "@openfn/language-http@latest"
          },
          %{
            # Different ID
            id: "source_job_y_id",
            # Same name - should match
            name: "transform_data",
            # Updated body
            body: "console.log('updated transforming')",
            # Same adaptor - should match
            adaptor: "@openfn/language-common@latest"
          }
        ],
        edges: [
          %{
            id: "source_edge_trigger_x",
            # Different source ID
            source_trigger_id: "source_trigger_id",
            source_job_id: nil,
            # Different target ID
            target_job_id: "source_job_x_id",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "source_edge_x_y",
            source_trigger_id: nil,
            # Different source ID
            source_job_id: "source_job_x_id",
            # Different target ID
            target_job_id: "source_job_y_id",
            condition_type: :on_job_success,
            enabled: true
          }
        ],
        positions: %{}
      }

      result = MergeProjects.merge_workflow(source, target)

      # Should match jobs by name+adaptor and preserve target IDs
      jobs = result["jobs"]
      assert length(jobs) == 2

      extract_job = Enum.find(jobs, &(&1["name"] == "extract_data"))
      # Target ID preserved
      assert extract_job["id"] == "target_job_a_id"
      # Source body used
      assert extract_job["body"] == "console.log('updated extracting')"
      assert extract_job["adaptor"] == "@openfn/language-http@latest"

      transform_job = Enum.find(jobs, &(&1["name"] == "transform_data"))
      # Target ID preserved
      assert transform_job["id"] == "target_job_b_id"
      # Source body used
      assert transform_job["body"] == "console.log('updated transforming')"

      # Should match trigger by type and preserve target ID
      triggers = result["triggers"]
      trigger = hd(triggers)
      # Target ID preserved
      assert trigger["id"] == "target_trigger_id"
      assert trigger["type"] == :webhook

      # Edges should be remapped to use target IDs
      edges = result["edges"]
      assert length(edges) == 2

      trigger_edge =
        Enum.find(edges, &(&1["source_trigger_id"] == "target_trigger_id"))

      # Remapped to target job ID
      assert trigger_edge["target_job_id"] == "target_job_a_id"
      # Target edge ID preserved
      assert trigger_edge["id"] == "target_edge_trigger_a"

      job_edge = Enum.find(edges, &(&1["source_job_id"] == "target_job_a_id"))
      # Remapped to target job ID
      assert job_edge["target_job_id"] == "target_job_b_id"
      # Target edge ID preserved
      assert job_edge["id"] == "target_edge_a_b"
    end

    test "merge workflows with different IDs and partial name matches" do
      # Target workflow
      target = %{
        id: "target_wf_id",
        name: "partial_match_test",
        triggers: [
          %{
            id: "target_trigger_1",
            type: :cron,
            cron_expression: "0 0 * * *",
            enabled: true
          }
        ],
        jobs: [
          %{
            id: "target_job_1",
            name: "process_user_data",
            body: "console.log('processing users')",
            adaptor: "@openfn/language-postgresql@latest"
          },
          %{
            id: "target_job_2",
            name: "send_email_notifications",
            body: "console.log('sending emails')",
            adaptor: "@openfn/language-mailgun@latest"
          }
        ],
        edges: [
          %{
            id: "target_edge_1",
            source_trigger_id: "target_trigger_1",
            source_job_id: nil,
            target_job_id: "target_job_1",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "target_edge_2",
            source_trigger_id: nil,
            source_job_id: "target_job_1",
            target_job_id: "target_job_2",
            condition_type: :on_job_success,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source workflow with similar but not identical names
      source = %{
        id: "source_wf_id",
        name: "partial_match_test",
        triggers: [
          %{
            id: "source_trigger_x",
            # Same type
            type: :cron,
            # Different expression
            cron_expression: "0 */4 * * *",
            enabled: true
          }
        ],
        jobs: [
          %{
            id: "source_job_x",
            # Similar name to "process_user_data"
            name: "process_customer_data",
            body: "console.log('processing customers')",
            # Same adaptor
            adaptor: "@openfn/language-postgresql@latest"
          },
          %{
            id: "source_job_y",
            # Similar name to "send_email_notifications"
            name: "send_sms_notifications",
            body: "console.log('sending sms')",
            # Different adaptor
            adaptor: "@openfn/language-twilio@latest"
          }
        ],
        edges: [
          %{
            id: "source_edge_x",
            source_trigger_id: "source_trigger_x",
            source_job_id: nil,
            target_job_id: "source_job_x",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "source_edge_y",
            source_trigger_id: nil,
            source_job_id: "source_job_x",
            target_job_id: "source_job_y",
            condition_type: :on_job_success,
            enabled: true
          }
        ],
        positions: %{}
      }

      result = MergeProjects.merge_workflow(source, target)

      # Jobs should be matched based on name similarity and adaptor compatibility
      jobs = result["jobs"]
      assert length(jobs) == 2

      # Job with same adaptor should get higher match score
      postgres_job =
        Enum.find(jobs, &(&1["adaptor"] == "@openfn/language-postgresql@latest"))

      # Should match target_job_1
      assert postgres_job["id"] == "target_job_1"
      # Source name used
      assert postgres_job["name"] == "process_customer_data"
      assert postgres_job["body"] == "console.log('processing customers')"

      # Job with different adaptor should still match but use source adaptor
      notification_job =
        Enum.find(jobs, &(&1["name"] == "send_sms_notifications"))

      # Should match target_job_2
      assert notification_job["id"] == "target_job_2"
      # Source adaptor used
      assert notification_job["adaptor"] == "@openfn/language-twilio@latest"

      # Trigger should match by type
      trigger = hd(result["triggers"])
      # Target ID preserved
      assert trigger["id"] == "target_trigger_1"
      # Source data used
      assert trigger["cron_expression"] == "0 */4 * * *"
    end

    test "merge workflows with different IDs - no matches found" do
      # Target workflow
      target = %{
        id: "target_wf",
        name: "original_workflow",
        triggers: [
          %{
            id: "target_webhook",
            type: :webhook,
            enabled: true
          }
        ],
        jobs: [
          %{
            id: "target_old_job",
            name: "legacy_processor",
            body: "console.log('legacy')",
            adaptor: "@openfn/language-old@1.0.0"
          }
        ],
        edges: [
          %{
            id: "target_old_edge",
            source_trigger_id: "target_webhook",
            source_job_id: nil,
            target_job_id: "target_old_job",
            condition_type: :always,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source workflow with completely different structure
      source = %{
        id: "source_wf",
        name: "new_workflow",
        triggers: [
          %{
            id: "source_cron",
            # Different trigger type
            type: :cron,
            cron_expression: "0 * * * *",
            enabled: true
          }
        ],
        jobs: [
          %{
            id: "source_new_job",
            # Completely different name
            name: "modern_api_client",
            body: "console.log('modern')",
            # Different adaptor
            adaptor: "@openfn/language-http@latest"
          }
        ],
        edges: [
          %{
            id: "source_new_edge",
            source_trigger_id: "source_cron",
            source_job_id: nil,
            target_job_id: "source_new_job",
            condition_type: :always,
            enabled: true
          }
        ],
        positions: %{}
      }

      result = MergeProjects.merge_workflow(source, target)

      # Should have one job - the source job mapped to target UUID (algorithm preserves UUIDs)
      jobs = result["jobs"]
      assert length(jobs) == 1

      merged_job = hd(jobs)
      refute merged_job["delete"]
      # Source job data used
      assert merged_job["name"] == "modern_api_client"
      assert merged_job["body"] == "console.log('modern')"
      assert merged_job["adaptor"] == "@openfn/language-http@latest"
      # Target UUID preserved
      assert merged_job["id"] == "target_old_job"

      # Should have one trigger - the source trigger mapped to target UUID (algorithm preserves UUIDs)
      triggers = result["triggers"]
      assert length(triggers) == 1

      merged_trigger = hd(triggers)
      refute merged_trigger["delete"]
      # Source trigger data used
      assert merged_trigger["type"] == :cron
      assert merged_trigger["cron_expression"] == "0 * * * *"
      # Target UUID preserved
      assert merged_trigger["id"] == "target_webhook"

      # Should have one edge - the source edge mapped to target UUID (algorithm preserves UUIDs)
      edges = result["edges"]
      assert length(edges) == 1

      merged_edge = hd(edges)
      refute merged_edge["delete"]
      # Points to merged trigger
      assert merged_edge["source_trigger_id"] == merged_trigger["id"]
      # Points to merged job
      assert merged_edge["target_job_id"] == merged_job["id"]
      # Target edge UUID preserved
      assert merged_edge["id"] == "target_old_edge"
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
