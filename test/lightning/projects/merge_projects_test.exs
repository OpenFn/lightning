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

    test "merge name change in single job" do
      job_id = "job_x_id"
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
            id: job_id,
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
            target_job_id: job_id,
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
      # Job id mantains
      assert job["id"] == job_id
    end

    test "merge with no changes" do
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
      assert length(result["edges"]) == 2
      assert result["name"] == "test_wf"
    end

    test "merge with change to edge condition" do
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
        target
        | edges: [
            %{hd(target.edges) | condition_expression: "state.success"}
          ]
      }

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

  describe "merge_workflow/2 - new algorithm" do
    test "direct name matching takes precedence over signature matching" do
      target = %{
        id: "workflow_id",
        name: "test_wf",
        triggers: [%{id: "trigger_id", type: :webhook, enabled: true}],
        jobs: [
          %{
            id: "job_a_id",
            name: "extract_data",
            body: "console.log('extracting')",
            adaptor: "@openfn/language-http@latest"
          },
          %{
            id: "job_b_id",
            name: "transform_data",
            body: "console.log('transforming')",
            adaptor: "@openfn/language-common@latest"
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

      # Source has exact name matches - should use direct matching regardless of signatures
      source = %{
        target
        | jobs: [
            %{
              id: "source_job_x",
              # Exact match
              name: "extract_data",
              body: "console.log('updated extracting')",
              adaptor: "@openfn/language-http@latest"
            },
            %{
              id: "source_job_y",
              # Exact match
              name: "transform_data",
              body: "console.log('updated transforming')",
              adaptor: "@openfn/language-common@latest"
            }
          ],
          edges: [
            %{
              id: "edge_t_a",
              source_trigger_id: "trigger_id",
              source_job_id: nil,
              # Reference source job ID
              target_job_id: "source_job_x",
              condition_type: :always,
              enabled: true
            },
            %{
              id: "edge_a_b",
              source_trigger_id: nil,
              # Reference source job ID
              source_job_id: "source_job_x",
              # Reference source job ID
              target_job_id: "source_job_y",
              condition_type: :on_job_success,
              enabled: true
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      jobs = result["jobs"]
      assert length(jobs) == 2

      # Jobs should be matched by name and preserve target IDs
      extract_job = Enum.find(jobs, &(&1["name"] == "extract_data"))
      assert extract_job["id"] == "job_a_id"
      assert extract_job["body"] == "console.log('updated extracting')"

      transform_job = Enum.find(jobs, &(&1["name"] == "transform_data"))
      assert transform_job["id"] == "job_b_id"
      assert transform_job["body"] == "console.log('updated transforming')"
    end

    test "parent signature matching works when names don't match" do
      target = %{
        id: "workflow_id",
        name: "signature_test",
        triggers: [%{id: "trigger_id", type: :webhook, enabled: true}],
        jobs: [
          %{
            id: "job_parent_id",
            name: "parent_job",
            body: "console.log('parent')",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "job_child_id",
            name: "child_job",
            body: "console.log('child')",
            adaptor: "@openfn/language-http@latest"
          }
        ],
        edges: [
          %{
            id: "edge_t_p",
            source_trigger_id: "trigger_id",
            source_job_id: nil,
            target_job_id: "job_parent_id",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "edge_p_c",
            source_trigger_id: nil,
            source_job_id: "job_parent_id",
            target_job_id: "job_child_id",
            condition_type: :on_job_success,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source has same structure but different names
      source = %{
        target
        | jobs: [
            %{
              id: "source_parent_id",
              # Same name - will be matched directly
              name: "parent_job",
              body: "console.log('updated parent')",
              adaptor: "@openfn/language-common@latest"
            },
            %{
              id: "source_child_id",
              # Different name but same parent
              name: "different_child_name",
              body: "console.log('updated child')",
              adaptor: "@openfn/language-http@latest"
            }
          ],
          edges: [
            %{
              id: "source_edge_t_p",
              source_trigger_id: "trigger_id",
              source_job_id: nil,
              target_job_id: "source_parent_id",
              condition_type: :always,
              enabled: true
            },
            %{
              id: "source_edge_p_c",
              source_trigger_id: nil,
              source_job_id: "source_parent_id",
              target_job_id: "source_child_id",
              condition_type: :on_job_success,
              enabled: true
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      jobs = result["jobs"]
      assert length(jobs) == 2

      # Parent should match by name
      parent_job = Enum.find(jobs, &(&1["name"] == "parent_job"))
      assert parent_job["id"] == "job_parent_id"

      # Child should match by parent signature (after parent is mapped)
      child_job = Enum.find(jobs, &(&1["name"] == "different_child_name"))
      assert child_job["id"] == "job_child_id"
      assert child_job["body"] == "console.log('updated child')"
    end

    test "children signature matching works when names don't match" do
      target = %{
        id: "workflow_id",
        name: "children_signature_test",
        triggers: [%{id: "trigger_id", type: :webhook, enabled: true}],
        jobs: [
          %{
            id: "job_parent_id",
            name: "parent_job",
            body: "console.log('parent')",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "job_child1_id",
            name: "child1_job",
            body: "console.log('child1')",
            adaptor: "@openfn/language-http@latest"
          },
          %{
            id: "job_child2_id",
            name: "child2_job",
            body: "console.log('child2')",
            adaptor: "@openfn/language-postgresql@latest"
          }
        ],
        edges: [
          %{
            id: "edge_t_p",
            source_trigger_id: "trigger_id",
            source_job_id: nil,
            target_job_id: "job_parent_id",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "edge_p_c1",
            source_trigger_id: nil,
            source_job_id: "job_parent_id",
            target_job_id: "job_child1_id",
            condition_type: :on_job_success,
            enabled: true
          },
          %{
            id: "edge_p_c2",
            source_trigger_id: nil,
            source_job_id: "job_parent_id",
            target_job_id: "job_child2_id",
            condition_type: :on_job_failure,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source has same children but different parent name
      source = %{
        target
        | jobs: [
            %{
              id: "source_parent_id",
              # Different name
              name: "different_parent_name",
              body: "console.log('updated parent')",
              adaptor: "@openfn/language-common@latest"
            },
            %{
              id: "source_child1_id",
              # Same name - will be matched directly
              name: "child1_job",
              body: "console.log('updated child1')",
              adaptor: "@openfn/language-http@latest"
            },
            %{
              id: "source_child2_id",
              # Same name - will be matched directly
              name: "child2_job",
              body: "console.log('updated child2')",
              adaptor: "@openfn/language-postgresql@latest"
            }
          ],
          edges: [
            %{
              id: "edge_t_p",
              source_trigger_id: "trigger_id",
              source_job_id: nil,
              target_job_id: "source_parent_id",
              condition_type: :always,
              enabled: true
            },
            %{
              id: "edge_p_c1",
              source_trigger_id: nil,
              source_job_id: "source_parent_id",
              target_job_id: "source_child1_id",
              condition_type: :on_job_success,
              enabled: true
            },
            %{
              id: "edge_p_c2",
              source_trigger_id: nil,
              source_job_id: "source_parent_id",
              target_job_id: "source_child2_id",
              condition_type: :on_job_failure,
              enabled: true
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      jobs = result["jobs"]
      assert length(jobs) == 3

      # Children should match by name first
      child1_job = Enum.find(jobs, &(&1["name"] == "child1_job"))
      assert child1_job["id"] == "job_child1_id"

      child2_job = Enum.find(jobs, &(&1["name"] == "child2_job"))
      assert child2_job["id"] == "job_child2_id"

      # Parent should match by children signature (after children are mapped)
      parent_job = Enum.find(jobs, &(&1["name"] == "different_parent_name"))
      assert parent_job["id"] == "job_parent_id"
      assert parent_job["body"] == "console.log('updated parent')"
    end

    test "iterative matching resolves complex dependency chains" do
      # Complex chain: A -> B -> C -> D where only A and D have matching names
      target = %{
        id: "workflow_id",
        name: "chain_test",
        triggers: [%{id: "trigger_id", type: :webhook, enabled: true}],
        jobs: [
          %{
            id: "job_a_id",
            name: "step_a",
            body: "console.log('a')",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "job_b_id",
            name: "step_b",
            body: "console.log('b')",
            adaptor: "@openfn/language-http@latest"
          },
          %{
            id: "job_c_id",
            name: "step_c",
            body: "console.log('c')",
            adaptor: "@openfn/language-postgresql@latest"
          },
          %{
            id: "job_d_id",
            name: "step_d",
            body: "console.log('d')",
            adaptor: "@openfn/language-common@latest"
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
          },
          %{
            id: "edge_b_c",
            source_trigger_id: nil,
            source_job_id: "job_b_id",
            target_job_id: "job_c_id",
            condition_type: :on_job_success,
            enabled: true
          },
          %{
            id: "edge_c_d",
            source_trigger_id: nil,
            source_job_id: "job_c_id",
            target_job_id: "job_d_id",
            condition_type: :on_job_success,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source has matching names for A and D, but different names for B and C
      source = %{
        target
        | jobs: [
            # Name match
            %{
              id: "src_a",
              name: "step_a",
              body: "console.log('updated a')",
              adaptor: "@openfn/language-common@latest"
            },
            # No name match
            %{
              id: "src_b",
              name: "process_step",
              body: "console.log('updated b')",
              adaptor: "@openfn/language-http@latest"
            },
            # No name match
            %{
              id: "src_c",
              name: "transform_step",
              body: "console.log('updated c')",
              adaptor: "@openfn/language-postgresql@latest"
            },
            # Name match
            %{
              id: "src_d",
              name: "step_d",
              body: "console.log('updated d')",
              adaptor: "@openfn/language-common@latest"
            }
          ],
          edges: [
            %{
              id: "edge_t_a",
              source_trigger_id: "trigger_id",
              source_job_id: nil,
              target_job_id: "src_a",
              condition_type: :always,
              enabled: true
            },
            %{
              id: "edge_a_b",
              source_trigger_id: nil,
              source_job_id: "src_a",
              target_job_id: "src_b",
              condition_type: :on_job_success,
              enabled: true
            },
            %{
              id: "edge_b_c",
              source_trigger_id: nil,
              source_job_id: "src_b",
              target_job_id: "src_c",
              condition_type: :on_job_success,
              enabled: true
            },
            %{
              id: "edge_c_d",
              source_trigger_id: nil,
              source_job_id: "src_c",
              target_job_id: "src_d",
              condition_type: :on_job_success,
              enabled: true
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      jobs = result["jobs"]
      assert length(jobs) == 4

      # A and D should match by name immediately
      step_a = Enum.find(jobs, &(&1["name"] == "step_a"))
      assert step_a["id"] == "job_a_id"
      assert step_a["body"] == "console.log('updated a')"

      step_d = Enum.find(jobs, &(&1["name"] == "step_d"))
      assert step_d["id"] == "job_d_id"
      assert step_d["body"] == "console.log('updated d')"

      # B should match by parent signature (A is already mapped)
      process_step = Enum.find(jobs, &(&1["name"] == "process_step"))
      assert process_step["id"] == "job_b_id"
      assert process_step["body"] == "console.log('updated b')"

      # C should match by parent signature (B is mapped) and children signature (D is mapped)
      transform_step = Enum.find(jobs, &(&1["name"] == "transform_step"))
      assert transform_step["id"] == "job_c_id"
      assert transform_step["body"] == "console.log('updated c')"
    end

    test "job body matching used as tiebreaker for multiple signature candidates" do
      target = %{
        id: "workflow_id",
        name: "tiebreaker_test",
        triggers: [%{id: "trigger_id", type: :webhook, enabled: true}],
        jobs: [
          %{
            id: "parent_id",
            name: "parent_job",
            body: "console.log('parent')",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "child1_id",
            name: "child_job_1",
            body: "processData(state)",
            adaptor: "@openfn/language-http@latest"
          },
          %{
            id: "child2_id",
            name: "child_job_2",
            body: "sendEmail(state)",
            adaptor: "@openfn/language-http@latest"
          }
        ],
        edges: [
          %{
            id: "edge_p_c1",
            source_trigger_id: nil,
            source_job_id: "parent_id",
            target_job_id: "child1_id",
            condition_type: :on_job_success,
            enabled: true
          },
          %{
            id: "edge_p_c2",
            source_trigger_id: nil,
            source_job_id: "parent_id",
            target_job_id: "child2_id",
            condition_type: :on_job_failure,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source has similar structure but both children have same parent (will create conflict)
      source = %{
        target
        | jobs: [
            %{
              id: "src_parent",
              name: "parent_job",
              body: "console.log('updated parent')",
              adaptor: "@openfn/language-common@latest"
            },
            # Similar to child1
            %{
              id: "src_child1",
              name: "different_name_1",
              body: "processData(updatedState)",
              adaptor: "@openfn/language-http@latest"
            },
            # Different from both
            %{
              id: "src_child2",
              name: "different_name_2",
              body: "sendSMS(state)",
              adaptor: "@openfn/language-http@latest"
            }
          ],
          edges: [
            %{
              id: "edge_p_c1",
              source_trigger_id: nil,
              source_job_id: "src_parent",
              target_job_id: "src_child1",
              condition_type: :on_job_success,
              enabled: true
            },
            %{
              id: "edge_p_c2",
              source_trigger_id: nil,
              source_job_id: "src_parent",
              target_job_id: "src_child2",
              condition_type: :on_job_failure,
              enabled: true
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      jobs = result["jobs"]
      assert length(jobs) == 3

      # Parent matches by name
      parent_job = Enum.find(jobs, &(&1["name"] == "parent_job"))
      assert parent_job["id"] == "parent_id"

      # Child with similar body should match child1 due to higher Jaro distance
      child_with_processdata =
        Enum.find(jobs, &(&1["name"] == "different_name_1"))

      assert child_with_processdata["id"] == "child1_id"
      assert child_with_processdata["body"] == "processData(updatedState)"

      # Other child should match child2
      child_with_sendsms = Enum.find(jobs, &(&1["name"] == "different_name_2"))
      assert child_with_sendsms["id"] == "child2_id"
      assert child_with_sendsms["body"] == "sendSMS(state)"
    end

    test "no signature match leaves job unmapped for creation as new job" do
      target = %{
        id: "workflow_id",
        name: "unmapped_test",
        triggers: [%{id: "trigger_id", type: :webhook, enabled: true}],
        jobs: [
          %{
            id: "existing_job_id",
            name: "existing_job",
            body: "console.log('existing')",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        edges: [
          %{
            id: "edge_t_e",
            source_trigger_id: "trigger_id",
            source_job_id: nil,
            target_job_id: "existing_job_id",
            condition_type: :always,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source adds a completely new job with no name match and no signature match
      source = %{
        target
        | jobs:
            target.jobs ++
              [
                %{
                  id: "new_job_id",
                  name: "completely_new_job",
                  body: "console.log('new')",
                  adaptor: "@openfn/language-http@latest"
                }
              ]
      }

      result = MergeProjects.merge_workflow(source, target)

      jobs = result["jobs"]
      assert length(jobs) == 2

      # Existing job should be preserved
      existing_job = Enum.find(jobs, &(&1["name"] == "existing_job"))
      assert existing_job["id"] == "existing_job_id"

      # New job should get a generated UUID (not the source ID)
      new_job = Enum.find(jobs, &(&1["name"] == "completely_new_job"))
      # Should be generated UUID
      assert new_job["id"] != "new_job_id"
      assert new_job["body"] == "console.log('new')"
      refute new_job["delete"]
    end

    test "jobs with no signature information are not matched by signatures" do
      # Both source and target have isolated jobs (no parents/children)
      target = %{
        id: "workflow_id",
        name: "isolated_test",
        triggers: [
          %{id: "trigger1_id", type: :webhook, enabled: true},
          %{
            id: "trigger2_id",
            type: :cron,
            cron_expression: "0 * * * *",
            enabled: true
          }
        ],
        jobs: [
          %{
            id: "isolated1_id",
            name: "isolated_job_1",
            body: "console.log('isolated1')",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "isolated2_id",
            name: "isolated_job_2",
            body: "console.log('isolated2')",
            adaptor: "@openfn/language-http@latest"
          }
        ],
        edges: [
          %{
            id: "edge_t1_i1",
            source_trigger_id: "trigger1_id",
            source_job_id: nil,
            target_job_id: "isolated1_id",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "edge_t2_i2",
            source_trigger_id: "trigger2_id",
            source_job_id: nil,
            target_job_id: "isolated2_id",
            condition_type: :always,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source has different names for isolated jobs
      source = %{
        target
        | jobs: [
            %{
              id: "src_iso1",
              name: "different_isolated_1",
              body: "console.log('updated isolated1')",
              adaptor: "@openfn/language-common@latest"
            },
            %{
              id: "src_iso2",
              name: "different_isolated_2",
              body: "console.log('updated isolated2')",
              adaptor: "@openfn/language-http@latest"
            }
          ],
          edges: [
            %{
              id: "edge_t1_i1",
              source_trigger_id: "trigger1_id",
              source_job_id: nil,
              target_job_id: "src_iso1",
              condition_type: :always,
              enabled: true
            },
            %{
              id: "edge_t2_i2",
              source_trigger_id: "trigger2_id",
              source_job_id: nil,
              target_job_id: "src_iso2",
              condition_type: :always,
              enabled: true
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      jobs = result["jobs"]
      assert length(jobs) == 2

      # Since there are no signatures and no name matches, the algorithm should still
      # create a mapping but it will be arbitrary. The important thing is that
      # isolated jobs (with no parent/child relationships) don't use signature matching
      non_deleted_jobs = Enum.reject(jobs, & &1["delete"])
      assert length(non_deleted_jobs) == 2

      # Jobs should have updated bodies from source
      job_bodies = non_deleted_jobs |> Enum.map(& &1["body"]) |> Enum.sort()

      assert job_bodies == [
               "console.log('updated isolated1')",
               "console.log('updated isolated2')"
             ]
    end

    test "handles single unmapped source and target by mapping them together" do
      target = %{
        id: "workflow_id",
        name: "single_remaining_test",
        triggers: [%{id: "trigger_id", type: :webhook, enabled: true}],
        jobs: [
          %{
            id: "matched_job_id",
            name: "matched_job",
            body: "console.log('matched')",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "orphan_target_id",
            name: "orphan_target",
            body: "console.log('orphan target')",
            adaptor: "@openfn/language-http@latest"
          }
        ],
        edges: [
          %{
            id: "edge_t_m",
            source_trigger_id: "trigger_id",
            source_job_id: nil,
            target_job_id: "matched_job_id",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "edge_m_o",
            source_trigger_id: nil,
            source_job_id: "matched_job_id",
            target_job_id: "orphan_target_id",
            condition_type: :on_job_success,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source has one matching job and one orphan (different name, no signature match)
      source = %{
        target
        | jobs: [
            %{
              id: "src_matched",
              name: "matched_job",
              body: "console.log('updated matched')",
              adaptor: "@openfn/language-common@latest"
            },
            %{
              id: "src_orphan",
              name: "orphan_source",
              body: "console.log('orphan source')",
              adaptor: "@openfn/language-postgresql@latest"
            }
          ],
          edges: [
            %{
              id: "edge_t_m",
              source_trigger_id: "trigger_id",
              source_job_id: nil,
              target_job_id: "src_matched",
              condition_type: :always,
              enabled: true
            },
            %{
              id: "edge_m_o",
              source_trigger_id: nil,
              source_job_id: "src_matched",
              target_job_id: "src_orphan",
              condition_type: :on_job_success,
              enabled: true
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      jobs = result["jobs"]
      assert length(jobs) == 2

      # Matched job should preserve target ID
      matched_job = Enum.find(jobs, &(&1["name"] == "matched_job"))
      assert matched_job["id"] == "matched_job_id"
      assert matched_job["body"] == "console.log('updated matched')"
      refute matched_job["delete"]

      # Single orphan source should be mapped to single orphan target (special case)
      orphan_job = Enum.find(jobs, &(&1["name"] == "orphan_source"))
      # Target ID preserved
      assert orphan_job["id"] == "orphan_target_id"
      # Source content used
      assert orphan_job["body"] == "console.log('orphan source')"
      refute orphan_job["delete"]
    end

    test "unmapped source jobs become new and unmapped target jobs are deleted" do
      target = %{
        id: "workflow_id",
        name: "deletion_creation_test",
        triggers: [%{id: "trigger_id", type: :webhook, enabled: true}],
        jobs: [
          %{
            id: "matched_job_id",
            name: "shared_job",
            body: "console.log('shared')",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "target_only_id",
            name: "target_only",
            body: "console.log('target only')",
            adaptor: "@openfn/language-http@latest"
          },
          %{
            id: "another_target_id",
            name: "another_target",
            body: "console.log('another target')",
            adaptor: "@openfn/language-postgresql@latest"
          }
        ],
        edges: [
          %{
            id: "edge_t_s",
            source_trigger_id: "trigger_id",
            source_job_id: nil,
            target_job_id: "matched_job_id",
            condition_type: :always,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source has the shared job plus two new jobs, but missing the target-only jobs
      source = %{
        target
        | jobs: [
            %{
              id: "src_shared",
              name: "shared_job",
              body: "console.log('updated shared')",
              adaptor: "@openfn/language-common@latest"
            },
            %{
              id: "src_new1",
              name: "source_new1",
              body: "console.log('new 1')",
              adaptor: "@openfn/language-http@latest"
            },
            %{
              id: "src_new2",
              name: "source_new2",
              body: "console.log('new 2')",
              adaptor: "@openfn/language-salesforce@latest"
            }
          ],
          edges: [
            %{
              id: "edge_t_s",
              source_trigger_id: "trigger_id",
              source_job_id: nil,
              target_job_id: "src_shared",
              condition_type: :always,
              enabled: true
            }
          ]
      }

      result = MergeProjects.merge_workflow(source, target)

      jobs = result["jobs"]

      # Should have: 1 shared + 2 new source jobs + 2 deleted target jobs = 5 total
      assert length(jobs) == 5

      # Shared job should preserve target ID but use source content
      shared_job = Enum.find(jobs, &(&1["name"] == "shared_job"))
      assert shared_job["id"] == "matched_job_id"
      assert shared_job["body"] == "console.log('updated shared')"
      refute shared_job["delete"]

      # Source-only jobs should get new UUIDs (not their original source IDs)
      new_jobs =
        Enum.filter(jobs, &(&1["name"] in ["source_new1", "source_new2"]))

      assert length(new_jobs) == 2

      for new_job <- new_jobs do
        # Should have generated UUIDs
        refute new_job["id"] in ["src_new1", "src_new2"]
        refute new_job["delete"]
      end

      # Target-only jobs should be marked for deletion
      deleted_jobs = Enum.filter(jobs, & &1["delete"])
      assert length(deleted_jobs) == 2
      deleted_ids = deleted_jobs |> Enum.map(& &1["id"]) |> Enum.sort()
      assert deleted_ids == ["another_target_id", "target_only_id"]
    end

    test "maximum iterations prevents infinite loops in complex scenarios" do
      # Create a scenario that could potentially cause issues with iteration
      target = %{
        id: "workflow_id",
        name: "complex_test",
        triggers: [%{id: "trigger_id", type: :webhook, enabled: true}],
        jobs: [
          %{
            id: "job1_id",
            name: "job1",
            body: "console.log('1')",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "job2_id",
            name: "job2",
            body: "console.log('2')",
            adaptor: "@openfn/language-http@latest"
          },
          %{
            id: "job3_id",
            name: "job3",
            body: "console.log('3')",
            adaptor: "@openfn/language-postgresql@latest"
          },
          %{
            id: "job4_id",
            name: "job4",
            body: "console.log('4')",
            adaptor: "@openfn/language-common@latest"
          },
          %{
            id: "job5_id",
            name: "job5",
            body: "console.log('5')",
            adaptor: "@openfn/language-http@latest"
          }
        ],
        edges: [
          %{
            id: "e1",
            source_trigger_id: "trigger_id",
            source_job_id: nil,
            target_job_id: "job1_id",
            condition_type: :always,
            enabled: true
          },
          %{
            id: "e2",
            source_trigger_id: nil,
            source_job_id: "job1_id",
            target_job_id: "job2_id",
            condition_type: :on_job_success,
            enabled: true
          },
          %{
            id: "e3",
            source_trigger_id: nil,
            source_job_id: "job2_id",
            target_job_id: "job3_id",
            condition_type: :on_job_success,
            enabled: true
          },
          %{
            id: "e4",
            source_trigger_id: nil,
            source_job_id: "job3_id",
            target_job_id: "job4_id",
            condition_type: :on_job_success,
            enabled: true
          },
          %{
            id: "e5",
            source_trigger_id: nil,
            source_job_id: "job4_id",
            target_job_id: "job5_id",
            condition_type: :on_job_success,
            enabled: true
          }
        ],
        positions: %{}
      }

      # Source has completely different names
      source = %{
        target
        | jobs: [
            %{
              id: "src1",
              name: "step_one",
              body: "console.log('updated 1')",
              adaptor: "@openfn/language-common@latest"
            },
            %{
              id: "src2",
              name: "step_two",
              body: "console.log('updated 2')",
              adaptor: "@openfn/language-http@latest"
            },
            %{
              id: "src3",
              name: "step_three",
              body: "console.log('updated 3')",
              adaptor: "@openfn/language-postgresql@latest"
            },
            %{
              id: "src4",
              name: "step_four",
              body: "console.log('updated 4')",
              adaptor: "@openfn/language-common@latest"
            },
            %{
              id: "src5",
              name: "step_five",
              body: "console.log('updated 5')",
              adaptor: "@openfn/language-http@latest"
            }
          ],
          edges: [
            %{
              id: "e1",
              source_trigger_id: "trigger_id",
              source_job_id: nil,
              target_job_id: "src1",
              condition_type: :always,
              enabled: true
            },
            %{
              id: "e2",
              source_trigger_id: nil,
              source_job_id: "src1",
              target_job_id: "src2",
              condition_type: :on_job_success,
              enabled: true
            },
            %{
              id: "e3",
              source_trigger_id: nil,
              source_job_id: "src2",
              target_job_id: "src3",
              condition_type: :on_job_success,
              enabled: true
            },
            %{
              id: "e4",
              source_trigger_id: nil,
              source_job_id: "src3",
              target_job_id: "src4",
              condition_type: :on_job_success,
              enabled: true
            },
            %{
              id: "e5",
              source_trigger_id: nil,
              source_job_id: "src4",
              target_job_id: "src5",
              condition_type: :on_job_success,
              enabled: true
            }
          ]
      }

      # This should complete without hanging, even though there are no name matches
      # The signature matching should eventually map all jobs through iterative matching
      result = MergeProjects.merge_workflow(source, target)

      jobs = result["jobs"]
      assert length(jobs) == 5

      # All jobs should be preserved (no deletions in this case)
      non_deleted_jobs = Enum.reject(jobs, & &1["delete"])
      assert length(non_deleted_jobs) == 5
    end
  end

  describe "merge_workflow/2 - ported" do
    test "no changes: single node workflow" do
      # Both source and target have identical single trigger
      source =
        build(:workflow, jobs: [], edges: [])
        |> with_trigger(build(:trigger, type: :webhook))
        |> insert()

      target =
        build(:workflow, jobs: [], edges: [])
        |> with_trigger(build(:trigger, type: :webhook))
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Should map source trigger to target trigger
      target_trigger = hd(target.triggers)

      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      assert result_trigger["type"] == :webhook
      refute result_trigger["delete"]
    end

    test "no changes: multi node workflow" do
      # Both source and target have identical trigger-job structure
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_edge({source_trigger, source_job_a})
        |> insert()

      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "a")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_edge({target_trigger, target_job_a})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Should map both trigger and job correctly
      target_edge = hd(target.edges)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      assert result_trigger["type"] == :webhook
      refute result_trigger["delete"]

      # Check job mapping
      result_job = hd(result["jobs"])
      assert result_job["id"] == target_job_a.id
      assert result_job["name"] == "a"
      refute result_job["delete"]

      # Check edge mapping
      result_edge = hd(result["edges"])
      assert result_edge["id"] == target_edge.id
      assert result_edge["source_trigger_id"] == target_trigger.id
      assert result_edge["target_job_id"] == target_job_a.id
      refute result_edge["delete"]
    end

    test "no changes: huge workflow" do
      # Create a complex workflow structure with multiple triggers and jobs
      # Structure: trigger->a, trigger->b, a->c, a->d, b->d, b->e, c->f, e->g

      # Source workflow
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")
      source_job_b = build(:job, name: "b")
      source_job_c = build(:job, name: "c")
      source_job_d = build(:job, name: "d")
      source_job_e = build(:job, name: "e")
      source_job_f = build(:job, name: "f")
      source_job_g = build(:job, name: "g")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_job(source_job_b)
        |> with_job(source_job_c)
        |> with_job(source_job_d)
        |> with_job(source_job_e)
        |> with_job(source_job_f)
        |> with_job(source_job_g)
        # trigger->a
        |> with_edge({source_trigger, source_job_a})
        # trigger->b
        |> with_edge({source_trigger, source_job_b})
        # a->c
        |> with_edge({source_job_a, source_job_c})
        # a->d
        |> with_edge({source_job_a, source_job_d})
        # b->d
        |> with_edge({source_job_b, source_job_d})
        # b->e
        |> with_edge({source_job_b, source_job_e})
        # c->f
        |> with_edge({source_job_c, source_job_f})
        # e->g
        |> with_edge({source_job_e, source_job_g})
        |> insert()

      # Target workflow with identical structure
      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "a")
      target_job_b = build(:job, name: "b")
      target_job_c = build(:job, name: "c")
      target_job_d = build(:job, name: "d")
      target_job_e = build(:job, name: "e")
      target_job_f = build(:job, name: "f")
      target_job_g = build(:job, name: "g")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_job(target_job_b)
        |> with_job(target_job_c)
        |> with_job(target_job_d)
        |> with_job(target_job_e)
        |> with_job(target_job_f)
        |> with_job(target_job_g)
        # trigger->a
        |> with_edge({target_trigger, target_job_a})
        # trigger->b
        |> with_edge({target_trigger, target_job_b})
        # a->c
        |> with_edge({target_job_a, target_job_c})
        # a->d
        |> with_edge({target_job_a, target_job_d})
        # b->d
        |> with_edge({target_job_b, target_job_d})
        # b->e
        |> with_edge({target_job_b, target_job_e})
        # c->f
        |> with_edge({target_job_c, target_job_f})
        # e->g
        |> with_edge({target_job_e, target_job_g})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Should map all nodes correctly
      expected_job_mappings = %{
        "a" => target_job_a.id,
        "b" => target_job_b.id,
        "c" => target_job_c.id,
        "d" => target_job_d.id,
        "e" => target_job_e.id,
        "f" => target_job_f.id,
        "g" => target_job_g.id
      }

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Check job mappings
      assert length(result["jobs"]) == 7

      for result_job <- result["jobs"] do
        expected_id = expected_job_mappings[result_job["name"]]
        assert result_job["id"] == expected_id
        refute result_job["delete"]
      end

      # Check edge mappings - should have 8 edges
      assert length(result["edges"]) == 8

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end

      # Verify specific edge mappings exist
      assert find_edge_by_names(result, "webhook", "a")
      assert find_edge_by_names(result, "webhook", "b")
      assert find_edge_by_names(result, "a", "c")
      assert find_edge_by_names(result, "a", "d")
      assert find_edge_by_names(result, "b", "d")
      assert find_edge_by_names(result, "b", "e")
      assert find_edge_by_names(result, "c", "f")
      assert find_edge_by_names(result, "e", "g")
    end

    test "id change: single node" do
      # Source has trigger only, target has trigger only but different trigger type
      # This tests the case where triggers are mapped by type
      source =
        build(:workflow)
        |> with_trigger(build(:trigger, type: :webhook))
        |> insert()

      target =
        build(:workflow)
        |> with_trigger(
          build(:trigger, type: :cron, cron_expression: "0 * * * *")
        )
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Source trigger (webhook) should map to target trigger (cron) - preserving target ID
      # but using source data
      target_trigger = hd(target.triggers)

      result_trigger = hd(result["triggers"])
      # Target ID preserved
      assert result_trigger["id"] == target_trigger.id
      # Source type used
      assert result_trigger["type"] == :webhook
      refute result_trigger["delete"]
    end

    test "id change: leaf nodes" do
      # Source: trigger->a, trigger->b
      # Target: trigger->x, trigger->y
      # Should map a->x, b->y based on structural similarity

      # Source workflow
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")
      source_job_b = build(:job, name: "b")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_job(source_job_b)
        # trigger->a
        |> with_edge({source_trigger, source_job_a})
        # trigger->b
        |> with_edge({source_trigger, source_job_b})
        |> insert()

      # Target workflow
      target_trigger = build(:trigger, type: :webhook)
      target_job_x = build(:job, name: "x")
      target_job_y = build(:job, name: "y")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_x)
        |> with_job(target_job_y)
        # trigger->x
        |> with_edge({target_trigger, target_job_x})
        # trigger->y
        |> with_edge({target_trigger, target_job_y})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Check job mappings - jobs should be mapped to preserve structure
      assert length(result["jobs"]) == 2

      # Find jobs by their source names (since source names are used in result)
      result_job_a = Enum.find(result["jobs"], &(&1["name"] == "a"))
      result_job_b = Enum.find(result["jobs"], &(&1["name"] == "b"))

      # Both jobs should exist and not be deleted
      assert result_job_a
      assert result_job_b
      refute result_job_a["delete"]
      refute result_job_b["delete"]

      # Check edge mappings - should have 2 edges from trigger to jobs
      assert length(result["edges"]) == 2
      assert find_edge_by_names(result, "webhook", "a")
      assert find_edge_by_names(result, "webhook", "b")

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end
    end

    test "id change: internal node" do
      # Source: trigger->a, a->b
      # Target: trigger->x, x->b
      # Should map a->x based on structural similarity (same parent and child)

      # Source workflow
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")
      source_job_b = build(:job, name: "b")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_job(source_job_b)
        # trigger->a
        |> with_edge({source_trigger, source_job_a})
        # a->b
        |> with_edge({source_job_a, source_job_b})
        |> insert()

      # Target workflow
      target_trigger = build(:trigger, type: :webhook)
      target_job_x = build(:job, name: "x")
      target_job_b = build(:job, name: "b")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_x)
        |> with_job(target_job_b)
        # trigger->x
        |> with_edge({target_trigger, target_job_x})
        # x->b
        |> with_edge({target_job_x, target_job_b})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Check job mappings
      assert length(result["jobs"]) == 2

      # Job 'a' should be mapped to target's 'x' job (internal node mapping)
      result_job_a = Enum.find(result["jobs"], &(&1["name"] == "a"))
      assert result_job_a
      # Mapped to target's 'x' job
      assert result_job_a["id"] == target_job_x.id
      refute result_job_a["delete"]

      # Job 'b' should be mapped to target's 'b' job (exact name match)
      result_job_b = Enum.find(result["jobs"], &(&1["name"] == "b"))
      assert result_job_b
      # Mapped to target's 'b' job
      assert result_job_b["id"] == target_job_b.id
      refute result_job_b["delete"]

      # Check edge mappings - should have 2 edges
      assert length(result["edges"]) == 2
      # trigger->a
      assert find_edge_by_names(result, "webhook", "a")
      # a->b
      assert find_edge_by_names(result, "a", "b")

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end
    end

    test "id change: internal nodes(same parent and child)" do
      # Source: trigger->a, trigger->b, a->c, b->c
      # Target: trigger->x, trigger->y, x->c, y->c
      # Should map a->x, b->y based on structural similarity

      # Source workflow
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")
      source_job_b = build(:job, name: "b")
      source_job_c = build(:job, name: "c")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_job(source_job_b)
        |> with_job(source_job_c)
        # trigger->a
        |> with_edge({source_trigger, source_job_a})
        # trigger->b
        |> with_edge({source_trigger, source_job_b})
        # a->c
        |> with_edge({source_job_a, source_job_c})
        # b->c
        |> with_edge({source_job_b, source_job_c})
        |> insert()

      # Target workflow
      target_trigger = build(:trigger, type: :webhook)
      target_job_x = build(:job, name: "x")
      target_job_y = build(:job, name: "y")
      target_job_c = build(:job, name: "c")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_x)
        |> with_job(target_job_y)
        |> with_job(target_job_c)
        # trigger->x
        |> with_edge({target_trigger, target_job_x})
        # trigger->y
        |> with_edge({target_trigger, target_job_y})
        # x->c
        |> with_edge({target_job_x, target_job_c})
        # y->c
        |> with_edge({target_job_y, target_job_c})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Check job mappings
      assert length(result["jobs"]) == 3

      # Job 'c' should be mapped to target's 'c' job (exact name match)
      result_job_c = Enum.find(result["jobs"], &(&1["name"] == "c"))
      assert result_job_c
      assert result_job_c["id"] == target_job_c.id
      refute result_job_c["delete"]

      # Jobs 'a' and 'b' should be mapped to target's 'x' and 'y' jobs
      # The exact mapping depends on the algorithm's internal logic, but both should be mapped
      result_job_a = Enum.find(result["jobs"], &(&1["name"] == "a"))
      result_job_b = Enum.find(result["jobs"], &(&1["name"] == "b"))

      assert result_job_a
      assert result_job_b
      refute result_job_a["delete"]
      refute result_job_b["delete"]

      # Check that the mapped IDs are from the target jobs
      mapped_ids = [result_job_a["id"], result_job_b["id"]]
      target_ids = [target_job_x.id, target_job_y.id]
      assert Enum.sort(mapped_ids) == Enum.sort(target_ids)

      # Check edge mappings - should have 4 edges
      assert length(result["edges"]) == 4
      # trigger->a
      assert find_edge_by_names(result, "webhook", "a")
      # trigger->b
      assert find_edge_by_names(result, "webhook", "b")
      # a->c
      assert find_edge_by_names(result, "a", "c")
      # b->c
      assert find_edge_by_names(result, "b", "c")

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end
    end

    test "id change: several internal nodes (mid-size workflow)" do
      # Source: trigger->a, trigger->b, a->c, b->d, c->e, d->f, e->g, f->g
      # Target: trigger->a1, trigger->b1, a1->x, b1->y, x->e, y->f, e->z, f->z
      # Should map: a->a1, b->b1, c->x, d->y, e->e, f->f, g->z

      # Source workflow
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")
      source_job_b = build(:job, name: "b")
      source_job_c = build(:job, name: "c")
      source_job_d = build(:job, name: "d")
      source_job_e = build(:job, name: "e")
      source_job_f = build(:job, name: "f")
      source_job_g = build(:job, name: "g")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_job(source_job_b)
        |> with_job(source_job_c)
        |> with_job(source_job_d)
        |> with_job(source_job_e)
        |> with_job(source_job_f)
        |> with_job(source_job_g)
        # trigger->a
        |> with_edge({source_trigger, source_job_a})
        # trigger->b
        |> with_edge({source_trigger, source_job_b})
        # a->c
        |> with_edge({source_job_a, source_job_c})
        # b->d
        |> with_edge({source_job_b, source_job_d})
        # c->e
        |> with_edge({source_job_c, source_job_e})
        # d->f
        |> with_edge({source_job_d, source_job_f})
        # e->g
        |> with_edge({source_job_e, source_job_g})
        # f->g
        |> with_edge({source_job_f, source_job_g})
        |> insert()

      # Target workflow
      target_trigger = build(:trigger, type: :webhook)
      target_job_a1 = build(:job, name: "a1")
      target_job_b1 = build(:job, name: "b1")
      target_job_x = build(:job, name: "x")
      target_job_y = build(:job, name: "y")
      target_job_e = build(:job, name: "e")
      target_job_f = build(:job, name: "f")
      target_job_z = build(:job, name: "z")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a1)
        |> with_job(target_job_b1)
        |> with_job(target_job_x)
        |> with_job(target_job_y)
        |> with_job(target_job_e)
        |> with_job(target_job_f)
        |> with_job(target_job_z)
        # trigger->a1
        |> with_edge({target_trigger, target_job_a1})
        # trigger->b1
        |> with_edge({target_trigger, target_job_b1})
        # a1->x
        |> with_edge({target_job_a1, target_job_x})
        # b1->y
        |> with_edge({target_job_b1, target_job_y})
        # x->e
        |> with_edge({target_job_x, target_job_e})
        # y->f
        |> with_edge({target_job_y, target_job_f})
        # e->z
        |> with_edge({target_job_e, target_job_z})
        # f->z
        |> with_edge({target_job_f, target_job_z})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Check job mappings
      assert length(result["jobs"]) == 7

      # Jobs 'e' and 'f' should match by exact name
      result_job_e = Enum.find(result["jobs"], &(&1["name"] == "e"))
      result_job_f = Enum.find(result["jobs"], &(&1["name"] == "f"))

      assert result_job_e
      assert result_job_f
      assert result_job_e["id"] == target_job_e.id
      assert result_job_f["id"] == target_job_f.id
      refute result_job_e["delete"]
      refute result_job_f["delete"]

      # All other jobs should be mapped to target jobs
      expected_mappings = %{
        "a" => target_job_a1.id,
        "b" => target_job_b1.id,
        "c" => target_job_x.id,
        "d" => target_job_y.id,
        "g" => target_job_z.id
      }

      for {job_name, expected_target_id} <- expected_mappings do
        result_job = Enum.find(result["jobs"], &(&1["name"] == job_name))
        assert result_job, "Job #{job_name} should exist in result"

        assert result_job["id"] == expected_target_id,
               "Job #{job_name} should map to correct target ID"

        refute result_job["delete"]
      end

      # Check edge mappings - should have 8 edges
      assert length(result["edges"]) == 8
      # trigger->a
      assert find_edge_by_names(result, "webhook", "a")
      # trigger->b
      assert find_edge_by_names(result, "webhook", "b")
      # a->c
      assert find_edge_by_names(result, "a", "c")
      # b->d
      assert find_edge_by_names(result, "b", "d")
      # c->e
      assert find_edge_by_names(result, "c", "e")
      # d->f
      assert find_edge_by_names(result, "d", "f")
      # e->g
      assert find_edge_by_names(result, "e", "g")
      # f->g
      assert find_edge_by_names(result, "f", "g")

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end
    end

    test "id change: several internal nodes (mid-size workflow) 2" do
      # Source: trigger->a, trigger->b, a->c, a->d, b->e, b->f, d->g, e->g
      # Target: trigger->x, trigger->y, x->c, x->m, y->n, y->f, m->g, n->g
      # Should map: a->x, b->y, c->c, d->m, e->n, f->f, g->g

      # Source workflow
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")
      source_job_b = build(:job, name: "b")
      source_job_c = build(:job, name: "c")
      source_job_d = build(:job, name: "d")
      source_job_e = build(:job, name: "e")
      source_job_f = build(:job, name: "f")
      source_job_g = build(:job, name: "g")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_job(source_job_b)
        |> with_job(source_job_c)
        |> with_job(source_job_d)
        |> with_job(source_job_e)
        |> with_job(source_job_f)
        |> with_job(source_job_g)
        # trigger->a
        |> with_edge({source_trigger, source_job_a})
        # trigger->b
        |> with_edge({source_trigger, source_job_b})
        # a->c
        |> with_edge({source_job_a, source_job_c})
        # a->d
        |> with_edge({source_job_a, source_job_d})
        # b->e
        |> with_edge({source_job_b, source_job_e})
        # b->f
        |> with_edge({source_job_b, source_job_f})
        # d->g
        |> with_edge({source_job_d, source_job_g})
        # e->g
        |> with_edge({source_job_e, source_job_g})
        |> insert()

      # Target workflow
      target_trigger = build(:trigger, type: :webhook)
      target_job_x = build(:job, name: "x")
      target_job_y = build(:job, name: "y")
      target_job_c = build(:job, name: "c")
      target_job_m = build(:job, name: "m")
      target_job_n = build(:job, name: "n")
      target_job_f = build(:job, name: "f")
      target_job_g = build(:job, name: "g")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_x)
        |> with_job(target_job_y)
        |> with_job(target_job_c)
        |> with_job(target_job_m)
        |> with_job(target_job_n)
        |> with_job(target_job_f)
        |> with_job(target_job_g)
        # trigger->x
        |> with_edge({target_trigger, target_job_x})
        # trigger->y
        |> with_edge({target_trigger, target_job_y})
        # x->c
        |> with_edge({target_job_x, target_job_c})
        # x->m
        |> with_edge({target_job_x, target_job_m})
        # y->n
        |> with_edge({target_job_y, target_job_n})
        # y->f
        |> with_edge({target_job_y, target_job_f})
        # m->g
        |> with_edge({target_job_m, target_job_g})
        # n->g
        |> with_edge({target_job_n, target_job_g})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Check job mappings
      assert length(result["jobs"]) == 7

      # Jobs 'c', 'f', and 'g' should match by exact name
      exact_matches = %{
        "c" => target_job_c.id,
        "f" => target_job_f.id,
        "g" => target_job_g.id
      }

      for {job_name, expected_target_id} <- exact_matches do
        result_job = Enum.find(result["jobs"], &(&1["name"] == job_name))
        assert result_job, "Job #{job_name} should exist in result"

        assert result_job["id"] == expected_target_id,
               "Job #{job_name} should match by exact name"

        refute result_job["delete"]
      end

      # Other jobs should be mapped based on structural similarity
      # a->x, b->y, d->m, e->n (the algorithm should determine these mappings)
      expected_structural_mappings = %{
        "a" => target_job_x.id,
        "b" => target_job_y.id,
        "d" => target_job_m.id,
        "e" => target_job_n.id
      }

      for {job_name, expected_target_id} <- expected_structural_mappings do
        result_job = Enum.find(result["jobs"], &(&1["name"] == job_name))
        assert result_job, "Job #{job_name} should exist in result"

        assert result_job["id"] == expected_target_id,
               "Job #{job_name} should map based on structure"

        refute result_job["delete"]
      end

      # Check edge mappings - should have 8 edges
      assert length(result["edges"]) == 8
      # trigger->a
      assert find_edge_by_names(result, "webhook", "a")
      # trigger->b
      assert find_edge_by_names(result, "webhook", "b")
      # a->c
      assert find_edge_by_names(result, "a", "c")
      # a->d
      assert find_edge_by_names(result, "a", "d")
      # b->e
      assert find_edge_by_names(result, "b", "e")
      # b->f
      assert find_edge_by_names(result, "b", "f")
      # d->g
      assert find_edge_by_names(result, "d", "g")
      # e->g
      assert find_edge_by_names(result, "e", "g")

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end
    end

    test "id change: chained internal nodes" do
      # Source: trigger->a, a->b, b->c, b->d
      # Target: trigger->x, x->y, y->z, y->q
      # Special case: node 'b' has both parent and children changed
      # Should map: a->x, b->y, c->z, d->q

      # Source workflow
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")
      source_job_b = build(:job, name: "b")
      source_job_c = build(:job, name: "c")
      source_job_d = build(:job, name: "d")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_job(source_job_b)
        |> with_job(source_job_c)
        |> with_job(source_job_d)
        # trigger->a
        |> with_edge({source_trigger, source_job_a})
        # a->b
        |> with_edge({source_job_a, source_job_b})
        # b->c
        |> with_edge({source_job_b, source_job_c})
        # b->d
        |> with_edge({source_job_b, source_job_d})
        |> insert()

      # Target workflow
      target_trigger = build(:trigger, type: :webhook)
      target_job_x = build(:job, name: "x")
      target_job_y = build(:job, name: "y")
      target_job_z = build(:job, name: "z")
      target_job_q = build(:job, name: "q")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_x)
        |> with_job(target_job_y)
        |> with_job(target_job_z)
        |> with_job(target_job_q)
        # trigger->x
        |> with_edge({target_trigger, target_job_x})
        # x->y
        |> with_edge({target_job_x, target_job_y})
        # y->z
        |> with_edge({target_job_y, target_job_z})
        # y->q
        |> with_edge({target_job_y, target_job_q})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Check job mappings
      assert length(result["jobs"]) == 4

      # Expected mappings based on structural similarity
      expected_mappings = %{
        "a" => target_job_x.id,
        "b" => target_job_y.id,
        "c" => target_job_z.id,
        "d" => target_job_q.id
      }

      for {job_name, expected_target_id} <- expected_mappings do
        result_job = Enum.find(result["jobs"], &(&1["name"] == job_name))
        assert result_job, "Job #{job_name} should exist in result"

        assert result_job["id"] == expected_target_id,
               "Job #{job_name} should map to correct target"

        refute result_job["delete"]
      end

      # Check edge mappings - should have 4 edges
      assert length(result["edges"]) == 4
      # trigger->a
      assert find_edge_by_names(result, "webhook", "a")
      # a->b
      assert find_edge_by_names(result, "a", "b")
      # b->c
      assert find_edge_by_names(result, "b", "c")
      # b->d
      assert find_edge_by_names(result, "b", "d")

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end
    end

    test "node removal: single node" do
      # Source: empty workflow (just trigger)
      # Target: trigger with one job
      # Should result in empty mapping, target job should be marked for deletion

      # Source workflow - just a trigger
      source =
        build(:workflow)
        |> with_trigger(build(:trigger, type: :webhook))
        |> insert()

      # Target workflow - trigger with a job
      target_trigger = build(:trigger, type: :webhook)
      target_job = build(:job, name: "removed_job")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job)
        |> with_edge({target_trigger, target_job})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Should have one job marked for deletion
      assert length(result["jobs"]) == 1
      result_job = hd(result["jobs"])
      assert result_job["id"] == target_job.id
      assert result_job["delete"]

      # Should have one edge marked for deletion
      assert length(result["edges"]) == 1
      result_edge = hd(result["edges"])
      assert result_edge["delete"]
    end

    test "node removal: leaf node" do
      # Source: trigger only
      # Target: trigger->a
      # The leaf job 'a' should be marked for deletion

      # Source workflow - just trigger
      source =
        build(:workflow)
        |> with_trigger(build(:trigger, type: :webhook))
        |> insert()

      # Target workflow - trigger with leaf job
      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "a")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_edge({target_trigger, target_job_a})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Should have one job marked for deletion
      assert length(result["jobs"]) == 1
      result_job = hd(result["jobs"])
      assert result_job["id"] == target_job_a.id
      assert result_job["delete"]

      # Should have one edge marked for deletion
      assert length(result["edges"]) == 1
      result_edge = hd(result["edges"])
      assert result_edge["delete"]
    end

    test "node removal: multi leaf nodes (same parent)" do
      # Source: trigger only
      # Target: trigger->a, trigger->b
      # Both leaf jobs should be marked for deletion

      # Source workflow - just trigger
      source =
        build(:workflow)
        |> with_trigger(build(:trigger, type: :webhook))
        |> insert()

      # Target workflow - trigger with two leaf jobs
      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "a")
      target_job_b = build(:job, name: "b")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_job(target_job_b)
        |> with_edge({target_trigger, target_job_a})
        |> with_edge({target_trigger, target_job_b})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Should have two jobs marked for deletion
      assert length(result["jobs"]) == 2

      for result_job <- result["jobs"] do
        assert result_job["delete"]
      end

      # Should have two edges marked for deletion
      assert length(result["edges"]) == 2

      for result_edge <- result["edges"] do
        assert result_edge["delete"]
      end
    end

    test "node removal: multi leaf nodes (different parents)" do
      # Source: trigger->a, trigger->b (keeps the parent jobs)
      # Target: trigger->a, trigger->b, a->c, b->d (has additional leaf jobs)
      # Leaf jobs 'c' and 'd' should be marked for deletion

      # Source workflow - trigger with two jobs
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")
      source_job_b = build(:job, name: "b")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_job(source_job_b)
        |> with_edge({source_trigger, source_job_a})
        |> with_edge({source_trigger, source_job_b})
        |> insert()

      # Target workflow - same structure plus additional leaf jobs
      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "a")
      target_job_b = build(:job, name: "b")
      target_job_c = build(:job, name: "c")
      target_job_d = build(:job, name: "d")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_job(target_job_b)
        |> with_job(target_job_c)
        |> with_job(target_job_d)
        |> with_edge({target_trigger, target_job_a})
        |> with_edge({target_trigger, target_job_b})
        |> with_edge({target_job_a, target_job_c})
        |> with_edge({target_job_b, target_job_d})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Should have four jobs: two preserved, two deleted
      assert length(result["jobs"]) == 4

      # Jobs 'a' and 'b' should be preserved (exact name match)
      result_job_a = Enum.find(result["jobs"], &(&1["name"] == "a"))
      result_job_b = Enum.find(result["jobs"], &(&1["name"] == "b"))

      assert result_job_a
      assert result_job_b
      assert result_job_a["id"] == target_job_a.id
      assert result_job_b["id"] == target_job_b.id
      refute result_job_a["delete"]
      refute result_job_b["delete"]

      # Jobs 'c' and 'd' should be marked for deletion
      result_job_c = Enum.find(result["jobs"], &(&1["id"] == target_job_c.id))
      result_job_d = Enum.find(result["jobs"], &(&1["id"] == target_job_d.id))

      assert result_job_c
      assert result_job_d
      assert result_job_c["delete"]
      assert result_job_d["delete"]

      # Should have four edges: two preserved, two deleted
      assert length(result["edges"]) == 4

      # Edges trigger->a and trigger->b should be preserved
      assert find_edge_by_names(result, "webhook", "a")
      assert find_edge_by_names(result, "webhook", "b")

      # Edges a->c and b->d should be marked for deletion
      deleted_edges = Enum.filter(result["edges"], & &1["delete"])
      assert length(deleted_edges) == 2
    end

    test "node removal: single node (different parents)" do
      # Source: trigger->a, trigger->b (two separate jobs from trigger)
      # Target: trigger->a, trigger->b, a->c, b->c (job 'c' has two different parents: 'a' and 'b')
      # Job 'c' should be marked for deletion along with its edges

      # Source workflow - trigger with two separate jobs
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")
      source_job_b = build(:job, name: "b")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_job(source_job_b)
        |> with_edge({source_trigger, source_job_a})
        |> with_edge({source_trigger, source_job_b})
        |> insert()

      # Target workflow - same base structure plus job 'c' with edges from both 'a' and 'b'
      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "a")
      target_job_b = build(:job, name: "b")
      target_job_c = build(:job, name: "c")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_job(target_job_b)
        |> with_job(target_job_c)
        |> with_edge({target_trigger, target_job_a})
        |> with_edge({target_trigger, target_job_b})
        |> with_edge({target_job_a, target_job_c})
        |> with_edge({target_job_b, target_job_c})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Should have three jobs: two preserved, one deleted
      assert length(result["jobs"]) == 3

      # Jobs 'a' and 'b' should be preserved (exact name match)
      result_job_a = Enum.find(result["jobs"], &(&1["name"] == "a"))
      result_job_b = Enum.find(result["jobs"], &(&1["name"] == "b"))

      assert result_job_a
      assert result_job_b
      assert result_job_a["id"] == target_job_a.id
      assert result_job_b["id"] == target_job_b.id
      refute result_job_a["delete"]
      refute result_job_b["delete"]

      # Job 'c' should be marked for deletion
      result_job_c = Enum.find(result["jobs"], &(&1["id"] == target_job_c.id))
      assert result_job_c
      assert result_job_c["delete"]

      # Should have four edges: two preserved, two deleted
      assert length(result["edges"]) == 4

      # Edges trigger->a and trigger->b should be preserved (not deleted)
      preserved_edge_a = find_edge_by_names(result, "webhook", "a")
      preserved_edge_b = find_edge_by_names(result, "webhook", "b")
      assert preserved_edge_a
      assert preserved_edge_b
      refute preserved_edge_a["delete"]
      refute preserved_edge_b["delete"]

      # Edges a->c and b->c should be marked for deletion
      deleted_edges = Enum.filter(result["edges"], & &1["delete"])
      assert length(deleted_edges) == 2
    end

    test "node removal: internal node" do
      # Source: trigger->b (direct connection)
      # Target: trigger->a, a->b (internal node 'a' between trigger and b)
      # Internal node 'a' should be marked for deletion along with its edges
      # A new edge trigger->b should be added to match the source

      # Source workflow - direct trigger to b
      source_trigger = build(:trigger, type: :webhook)
      source_job_b = build(:job, name: "b")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_b)
        |> with_edge({source_trigger, source_job_b})
        |> insert()

      # Target workflow - trigger to a, a to b (a is internal node)
      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "a")
      target_job_b = build(:job, name: "b")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_job(target_job_b)
        |> with_edge({target_trigger, target_job_a})
        |> with_edge({target_job_a, target_job_b})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Should have two jobs: one preserved, one deleted
      assert length(result["jobs"]) == 2

      # Job 'b' should be preserved (exact name match)
      result_job_b = Enum.find(result["jobs"], &(&1["name"] == "b"))
      assert result_job_b
      assert result_job_b["id"] == target_job_b.id
      refute result_job_b["delete"]

      # Job 'a' (internal node) should be marked for deletion
      result_job_a = Enum.find(result["jobs"], &(&1["id"] == target_job_a.id))
      assert result_job_a
      assert result_job_a["delete"]

      # Should have three edges: two deleted (from target), one added (new trigger->b)
      assert length(result["edges"]) == 3

      # Two edges should be marked for deletion (trigger->a, a->b from target)
      deleted_edges = Enum.filter(result["edges"], & &1["delete"])
      assert length(deleted_edges) == 2

      # Get the new edge by subtracting deleted edges from all edges
      [new_edge] = result["edges"] -- deleted_edges

      # The new edge should connect trigger to job b
      assert new_edge["source_trigger_id"] == target_trigger.id
      assert new_edge["target_job_id"] == target_job_b.id
    end

    test "node addition: single leaf node" do
      # Source: trigger->a (ends at a)
      # Target: trigger->a, a->b (has additional leaf node b)
      # Leaf node 'b' should be marked for deletion along with edge a->b

      # Source workflow - trigger to a only
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_edge({source_trigger, source_job_a})
        |> insert()

      # Target workflow - trigger to a, a to b (b is additional leaf)
      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "a")
      target_job_b = build(:job, name: "b")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_job(target_job_b)
        |> with_edge({target_trigger, target_job_a})
        |> with_edge({target_job_a, target_job_b})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Should have two jobs: one preserved, one deleted
      assert length(result["jobs"]) == 2

      # Job 'a' should be preserved (exact name match)
      result_job_a = Enum.find(result["jobs"], &(&1["name"] == "a"))
      assert result_job_a
      assert result_job_a["id"] == target_job_a.id
      refute result_job_a["delete"]

      # Job 'b' (leaf node) should be marked for deletion
      result_job_b = Enum.find(result["jobs"], &(&1["id"] == target_job_b.id))
      assert result_job_b
      assert result_job_b["delete"]

      # Should have two edges: one preserved, one deleted
      assert length(result["edges"]) == 2

      # Edge trigger->a should be preserved
      preserved_edge = find_edge_by_names(result, "webhook", "a")
      assert preserved_edge
      refute preserved_edge["delete"]

      # Edge a->b should be marked for deletion
      deleted_edges = Enum.filter(result["edges"], & &1["delete"])
      assert length(deleted_edges) == 1
    end

    test "node addition: branching internal node" do
      # Source: trigger->a, a->b (linear chain)
      # Target: trigger->a, a->b, a->c, c->d (has additional branch from a)
      # Branch nodes 'c' and 'd' should be marked for deletion along with their edges

      # Source workflow - linear trigger->a->b
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")
      source_job_b = build(:job, name: "b")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_job(source_job_b)
        |> with_edge({source_trigger, source_job_a})
        |> with_edge({source_job_a, source_job_b})
        |> insert()

      # Target workflow - same chain plus branching from a to c to d
      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "a")
      target_job_b = build(:job, name: "b")
      target_job_c = build(:job, name: "c")
      target_job_d = build(:job, name: "d")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_job(target_job_b)
        |> with_job(target_job_c)
        |> with_job(target_job_d)
        |> with_edge({target_trigger, target_job_a})
        |> with_edge({target_job_a, target_job_b})
        |> with_edge({target_job_a, target_job_c})
        |> with_edge({target_job_c, target_job_d})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Should have four jobs: two preserved, two deleted
      assert length(result["jobs"]) == 4

      # Jobs 'a' and 'b' should be preserved (exact name matches)
      result_job_a = Enum.find(result["jobs"], &(&1["name"] == "a"))
      result_job_b = Enum.find(result["jobs"], &(&1["name"] == "b"))

      assert result_job_a
      assert result_job_b
      assert result_job_a["id"] == target_job_a.id
      assert result_job_b["id"] == target_job_b.id
      refute result_job_a["delete"]
      refute result_job_b["delete"]

      # Jobs 'c' and 'd' (branch nodes) should be marked for deletion
      result_job_c = Enum.find(result["jobs"], &(&1["id"] == target_job_c.id))
      result_job_d = Enum.find(result["jobs"], &(&1["id"] == target_job_d.id))

      assert result_job_c
      assert result_job_d
      assert result_job_c["delete"]
      assert result_job_d["delete"]

      # Should have four edges: two preserved, two deleted
      assert length(result["edges"]) == 4

      # Edges trigger->a and a->b should be preserved
      preserved_edge_trigger_a = find_edge_by_names(result, "webhook", "a")
      preserved_edge_a_b = find_edge_by_names(result, "a", "b")
      assert preserved_edge_trigger_a
      assert preserved_edge_a_b
      refute preserved_edge_trigger_a["delete"]
      refute preserved_edge_a_b["delete"]

      # Edges a->c and c->d should be marked for deletion
      deleted_edges = Enum.filter(result["edges"], & &1["delete"])
      assert length(deleted_edges) == 2
    end

    test "edge change: rewire to different parent" do
      # Source: trigger->a, a->b (b connected to a)
      # Target: trigger->a, trigger->b (b connected to trigger)
      # Job b should be rewired from trigger back to a, matching source structure

      # Source workflow - a->b chain
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")
      source_job_b = build(:job, name: "b")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_job(source_job_b)
        |> with_edge({source_trigger, source_job_a})
        |> with_edge({source_job_a, source_job_b})
        |> insert()

      # Target workflow - both a and b connected to trigger
      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "a")
      target_job_b = build(:job, name: "b")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_job(target_job_b)
        |> with_edge({target_trigger, target_job_a})
        |> with_edge({target_trigger, target_job_b})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Should have two jobs: both preserved
      assert length(result["jobs"]) == 2

      # Jobs 'a' and 'b' should be preserved (exact name matches)
      result_job_a = Enum.find(result["jobs"], &(&1["name"] == "a"))
      result_job_b = Enum.find(result["jobs"], &(&1["name"] == "b"))

      assert result_job_a
      assert result_job_b
      assert result_job_a["id"] == target_job_a.id
      assert result_job_b["id"] == target_job_b.id
      refute result_job_a["delete"]
      refute result_job_b["delete"]

      # Should have three edges: one preserved, one deleted, one added
      assert length(result["edges"]) == 3

      # Edge trigger->a should be preserved (exists in both)
      preserved_edge = find_edge_by_names(result, "webhook", "a")
      assert preserved_edge
      refute preserved_edge["delete"]

      # One edge should be marked for deletion (trigger->b from target)
      deleted_edges = Enum.filter(result["edges"], & &1["delete"])
      assert length(deleted_edges) == 1

      # Get the new edge (a->b to match source)
      [new_edge] = result["edges"] -- [preserved_edge | deleted_edges]
      assert new_edge["source_job_id"] == target_job_a.id
      assert new_edge["target_job_id"] == target_job_b.id
    end

    test "mixed change: rename + add new leaf" do
      # Source: trigger->a (simple trigger to job)
      # Target: trigger->x, x->b (job 'a' renamed to 'x', plus additional leaf 'b')
      # Job 'a' should map to 'x', leaf 'b' should be deleted

      # Source workflow - trigger->a
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "a")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_edge({source_trigger, source_job_a})
        |> insert()

      # Target workflow - trigger->x, x->b (a renamed to x, plus leaf b)
      target_trigger = build(:trigger, type: :webhook)
      target_job_x = build(:job, name: "x")
      target_job_b = build(:job, name: "b")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_x)
        |> with_job(target_job_b)
        |> with_edge({target_trigger, target_job_x})
        |> with_edge({target_job_x, target_job_b})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Should have two jobs: one preserved (x mapped from a), one deleted (b)
      assert length(result["jobs"]) == 2

      # Job 'x' should be preserved (mapped from source job 'a')
      assert result_job_a = Enum.find(result["jobs"], &(&1["name"] == "a"))
      assert result_job_a["id"] == target_job_x.id
      refute result_job_a["delete"]

      # Job 'b' (additional leaf) should be marked for deletion
      result_job_b = Enum.find(result["jobs"], &(&1["id"] == target_job_b.id))
      assert result_job_b
      assert result_job_b["delete"]

      # Should have two edges: one preserved, one deleted
      assert length(result["edges"]) == 2

      # Edge trigger->x should be preserved (mapped from trigger->a)
      preserved_edge = find_edge_by_names(result, "webhook", "a")
      assert preserved_edge
      refute preserved_edge["delete"]

      # Edge x->b should be marked for deletion
      deleted_edges = Enum.filter(result["edges"], & &1["delete"])
      assert length(deleted_edges) == 1
    end

    test "move: children move to a sibling" do
      # Source: trigger->m, m->n, m->o, o->d, o->e (children d,e under o)
      # Target: trigger->a, a->b, a->c, b->d, b->e (children d,e under b)
      # Jobs should map: m->a, o->b, n->c, d->d, e->e
      # Result preserves source names but uses target UUIDs

      # Source workflow - m has children n,o; o has children d,e
      source_trigger = build(:trigger, type: :webhook)
      source_job_m = build(:job, name: "m")
      source_job_n = build(:job, name: "n")
      source_job_o = build(:job, name: "o")
      source_job_d = build(:job, name: "d")
      source_job_e = build(:job, name: "e")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_m)
        |> with_job(source_job_n)
        |> with_job(source_job_o)
        |> with_job(source_job_d)
        |> with_job(source_job_e)
        |> with_edge({source_trigger, source_job_m})
        |> with_edge({source_job_m, source_job_n})
        |> with_edge({source_job_m, source_job_o})
        |> with_edge({source_job_o, source_job_d})
        |> with_edge({source_job_o, source_job_e})
        |> insert()

      # Target workflow - a has children b,c; b has children d,e
      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "a")
      target_job_b = build(:job, name: "b")
      target_job_c = build(:job, name: "c")
      target_job_d = build(:job, name: "d")
      target_job_e = build(:job, name: "e")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_job(target_job_b)
        |> with_job(target_job_c)
        |> with_job(target_job_d)
        |> with_job(target_job_e)
        |> with_edge({target_trigger, target_job_a})
        |> with_edge({target_job_a, target_job_b})
        |> with_edge({target_job_a, target_job_c})
        |> with_edge({target_job_b, target_job_d})
        |> with_edge({target_job_b, target_job_e})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Should have five jobs: all preserved with source names but target UUIDs
      assert length(result["jobs"]) == 5

      # Check job mappings: source names with target UUIDs, none deleted
      assert Enum.find(result["jobs"], fn job ->
               job["name"] == "m" and job["id"] == target_job_a.id and
                 is_nil(job["delete"])
             end)

      assert Enum.find(result["jobs"], fn job ->
               job["name"] == "n" and job["id"] == target_job_c.id and
                 is_nil(job["delete"])
             end)

      assert Enum.find(result["jobs"], fn job ->
               job["name"] == "o" and job["id"] == target_job_b.id and
                 is_nil(job["delete"])
             end)

      assert Enum.find(result["jobs"], fn job ->
               job["name"] == "d" and job["id"] == target_job_d.id and
                 is_nil(job["delete"])
             end)

      assert Enum.find(result["jobs"], fn job ->
               job["name"] == "e" and job["id"] == target_job_e.id and
                 is_nil(job["delete"])
             end)

      # Should have five edges: all preserved
      assert length(result["edges"]) == 5

      # All edges should be preserved (none deleted)
      assert Enum.all?(result["edges"], fn edge -> is_nil(edge["delete"]) end)

      # Check edge mappings - source structure with target UUIDs
      assert find_edge_by_names(result, "webhook", "m")["id"] ==
               find_edge_by_names(target, "webhook", "a")["id"]

      assert find_edge_by_names(result, "m", "n")["id"] ==
               find_edge_by_names(target, "a", "c")["id"]

      assert find_edge_by_names(result, "m", "o")["id"] ==
               find_edge_by_names(target, "a", "b")["id"]

      assert find_edge_by_names(result, "o", "d")["id"] ==
               find_edge_by_names(target, "b", "d")["id"]

      assert find_edge_by_names(result, "o", "e")["id"] ==
               find_edge_by_names(target, "b", "e")["id"]
    end

    test "expression-based mapping: nodes only distinguishable by expression" do
      # Source: trigger->x, trigger->y (both siblings with different expressions)
      # Target: trigger->a, trigger->b (both siblings with different expressions)
      # Jobs should map based on matching expressions: x('foo')->a('foo'), y('bar')->b('bar')

      # Source workflow - two jobs with different expressions
      source_trigger = build(:trigger, type: :webhook)
      source_job_x = build(:job, name: "x", body: "foo")
      source_job_y = build(:job, name: "y", body: "bar")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job_x)
        |> with_job(source_job_y)
        |> with_edge({source_trigger, source_job_x})
        |> with_edge({source_trigger, source_job_y})
        |> insert()

      # Target workflow - two jobs with matching expressions
      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "a", body: "foo")
      target_job_b = build(:job, name: "b", body: "bar")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_job(target_job_b)
        |> with_edge({target_trigger, target_job_a})
        |> with_edge({target_trigger, target_job_b})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      # Should have two jobs: both preserved with source names but target UUIDs
      assert length(result["jobs"]) == 2

      # Check job mappings based on expression matching: x->a, y->b
      assert Enum.find(result["jobs"], fn job ->
               job["name"] == "x" and job["id"] == target_job_a.id and
                 is_nil(job["delete"])
             end)

      assert Enum.find(result["jobs"], fn job ->
               job["name"] == "y" and job["id"] == target_job_b.id and
                 is_nil(job["delete"])
             end)

      # Should have two edges: both preserved
      assert length(result["edges"]) == 2

      # All edges should be preserved (none deleted)
      assert Enum.all?(result["edges"], fn edge -> is_nil(edge["delete"]) end)

      # Check edge mappings - source structure with target UUIDs
      assert find_edge_by_names(result, "webhook", "x")["id"] ==
               find_edge_by_names(target, "webhook", "a")["id"]

      assert find_edge_by_names(result, "webhook", "y")["id"] ==
               find_edge_by_names(target, "webhook", "b")["id"]
    end
  end

  defp find_edge_by_names(workflow, source_name, target_name) do
    workflow = stringify_keys(workflow)

    source_job = Enum.find(workflow["jobs"] || [], &(&1["name"] == source_name))
    target_job = Enum.find(workflow["jobs"] || [], &(&1["name"] == target_name))

    # For triggers, we'll match by type converted to string
    source_trigger =
      case source_name do
        "webhook" ->
          Enum.find(workflow["triggers"] || [], &(&1["type"] == :webhook))

        "cron" ->
          Enum.find(workflow["triggers"] || [], &(&1["type"] == :cron))

        _ ->
          nil
      end

    cond do
      source_trigger && target_job ->
        Enum.find(workflow["edges"] || [], fn edge ->
          edge["source_trigger_id"] == source_trigger["id"] &&
            edge["target_job_id"] == target_job["id"]
        end)

      source_job && target_job ->
        Enum.find(workflow["edges"] || [], fn edge ->
          edge["source_job_id"] == source_job["id"] &&
            edge["target_job_id"] == target_job["id"]
        end)

      true ->
        nil
    end
  end

  def stringify_keys(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> stringify_keys()
  end

  def stringify_keys(map = %{}) do
    map
    |> Enum.map(fn
      {k, v} when is_binary(k) -> {k, stringify_keys(v)}
      {k, v} -> {to_string(k), stringify_keys(v)}
    end)
    |> Enum.into(%{})
  end

  # Walk the list and stringify the keys of
  # of any map members
  def stringify_keys([head | rest]) do
    [stringify_keys(head) | stringify_keys(rest)]
  end

  def stringify_keys(not_a_map) do
    not_a_map
  end
end
