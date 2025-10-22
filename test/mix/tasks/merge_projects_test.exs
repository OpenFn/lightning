defmodule Mix.Tasks.Lightning.MergeProjectsTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias Lightning.Projects.MergeProjects

  @moduletag :tmp_dir

  describe "atomize_keys behavior" do
    test "handles all key types from real state files including cron and kafka",
         %{
           tmp_dir: tmp_dir
         } do
      # Test with keys that include cron_expression and kafka_configuration
      source = %{
        "id" => "source-id",
        "name" => "Source",
        "workflows" => [
          %{
            "id" => "wf-1",
            "name" => "Test",
            "jobs" => [
              %{
                "id" => "j-1",
                "name" => "Job 1",
                "body" => "new",
                "adaptor" => "@openfn/language-common@latest",
                "project_credential_id" => "cred-1",
                "keychain_credential_id" => nil
              }
            ],
            "triggers" => [
              %{
                "id" => "t-1",
                "type" => "cron",
                "cron_expression" => "0 0 * * *",
                "comment" => "Daily trigger",
                "custom_path" => nil,
                "kafka_configuration" => %{"topic" => "test"}
              }
            ],
            "edges" => [
              %{
                "id" => "e-1",
                "source_job_id" => nil,
                "source_trigger_id" => "t-1",
                "target_job_id" => "j-1",
                "condition_type" => "js_expression",
                "condition_expression" => "true",
                "condition_label" => "Always",
                "enabled" => true
              }
            ]
          }
        ]
      }

      target = %{
        "id" => "target-id",
        "name" => "Target",
        "description" => "Test description",
        "env" => "production",
        "color" => "#FF0000",
        "workflows" => []
      }

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(source))
      File.write!(target_file, Jason.encode!(target))

      # This should work without errors if all keys are properly handled
      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end)

      json_output =
        output |> String.split("\n") |> Enum.drop(1) |> Enum.join("\n")

      {:ok, result} = Jason.decode(json_output)

      assert result["id"] == "target-id"
      # Verify the cron trigger with all its keys was preserved
      workflow = hd(result["workflows"])
      trigger = hd(workflow["triggers"])
      assert trigger["type"] == "cron"
      assert trigger["cron_expression"] == "0 0 * * *"
      assert trigger["comment"] == "Daily trigger"
    end

    test "handles unknown string keys without crashing", %{
      tmp_dir: tmp_dir
    } do
      # Test that atomize_keys safely handles unknown keys that don't exist as atoms
      # Note: The merge logic itself only preserves known fields via Map.take/2,
      # so unknown fields are dropped regardless of atomization
      source = %{
        "id" => "source-id",
        "name" => "Source",
        "unknown_custom_field" => "some value",
        "workflows" => []
      }

      target = %{
        "id" => "target-id",
        "name" => "Target",
        "workflows" => []
      }

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(source))
      File.write!(target_file, Jason.encode!(target))

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end)

      json_output =
        output |> String.split("\n") |> Enum.drop(1) |> Enum.join("\n")

      {:ok, result} = Jason.decode(json_output)

      # Should complete successfully without crashing on unknown keys
      assert result["id"] == "target-id"
      # Unknown field is not preserved (merge logic uses Map.take for known fields only)
      refute Map.has_key?(result, "unknown_custom_field")
    end

    test "handles deeply nested structures with all key types", %{
      tmp_dir: tmp_dir
    } do
      # Test that atomize_keys handles deeply nested JSON structures
      # with various field types (jobs, triggers, edges, credentials)
      source = %{
        "id" => "source-id",
        "name" => "Source",
        "workflows" => [
          %{
            "id" => "wf-1",
            "name" => "Test",
            "jobs" => [
              %{
                "id" => "job-1",
                "name" => "Job 1",
                "body" => "test",
                "adaptor" => "@openfn/language-common@latest"
              }
            ],
            "triggers" => [%{"id" => "t-1", "type" => "webhook"}],
            "edges" => [
              %{
                "id" => "e-1",
                "source_job_id" => nil,
                "source_trigger_id" => "t-1",
                "target_job_id" => "job-1",
                "condition_type" => "always",
                "enabled" => true
              }
            ]
          }
        ]
      }

      target = %{
        "id" => "target-id",
        "name" => "Target",
        "workflows" => []
      }

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(source))
      File.write!(target_file, Jason.encode!(target))

      # This should not crash even with deeply nested structures
      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end)

      json_output =
        output |> String.split("\n") |> Enum.drop(1) |> Enum.join("\n")

      {:ok, result} = Jason.decode(json_output)

      # Should complete successfully
      assert result["id"] == "target-id"
      assert length(result["workflows"]) == 1
    end

    test "MergeProjects.merge_project/2 works with atom keys" do
      # Test if merge_project can handle maps with atom keys
      source = %{
        id: "source-id",
        name: "Source",
        workflows: [
          %{
            id: "wf-1",
            name: "Test",
            jobs: [%{id: "j-1", name: "Job 1", body: "new"}],
            triggers: [%{id: "t-1", type: "webhook"}],
            edges: [
              %{
                id: "e-1",
                source_trigger_id: "t-1",
                target_job_id: "j-1",
                condition_type: "always"
              }
            ]
          }
        ]
      }

      target = %{
        id: "target-id",
        name: "Target",
        workflows: [
          %{
            id: "wf-t",
            name: "Test",
            jobs: [%{id: "j-t", name: "Job 1", body: "old"}],
            triggers: [%{id: "t-t", type: "webhook"}],
            edges: [
              %{
                id: "e-t",
                source_trigger_id: "t-t",
                target_job_id: "j-t",
                condition_type: "always"
              }
            ]
          }
        ]
      }

      result = MergeProjects.merge_project(source, target)

      # Should work fine with atom keys
      assert result["id"] == "target-id"
      assert result["name"] == "Target"
    end
  end

  describe "run/1" do
    test "merges two valid project state files and outputs to stdout", %{
      tmp_dir: tmp_dir
    } do
      # Create source project state
      source_state = %{
        "id" => "source-id",
        "name" => "Source",
        "workflows" => [
          %{
            "id" => "workflow-1",
            "name" => "Test Workflow",
            "jobs" => [
              %{
                "id" => "job-1",
                "name" => "Job 1",
                "body" => "console.log('updated')",
                "adaptor" => "@openfn/language-common@latest"
              }
            ],
            "triggers" => [
              %{"id" => "trigger-1", "type" => "webhook"}
            ],
            "edges" => [
              %{
                "id" => "edge-1",
                "source_trigger_id" => "trigger-1",
                "target_job_id" => "job-1",
                "condition_type" => "always",
                "enabled" => true
              }
            ]
          }
        ]
      }

      # Create target project state
      target_state = %{
        "id" => "target-id",
        "name" => "Target",
        "env" => "production",
        "workflows" => [
          %{
            "id" => "workflow-target",
            "name" => "Test Workflow",
            "jobs" => [
              %{
                "id" => "job-target",
                "name" => "Job 1",
                "body" => "console.log('old')",
                "adaptor" => "@openfn/language-common@latest"
              }
            ],
            "triggers" => [
              %{"id" => "trigger-target", "type" => "webhook"}
            ],
            "edges" => [
              %{
                "id" => "edge-target",
                "source_trigger_id" => "trigger-target",
                "target_job_id" => "job-target",
                "condition_type" => "always",
                "enabled" => true
              }
            ]
          }
        ]
      }

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(source_state))
      File.write!(target_file, Jason.encode!(target_state))

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end)

      json_output =
        output |> String.split("\n") |> Enum.drop(1) |> Enum.join("\n")

      {:ok, result} = Jason.decode(json_output)

      # Verify merge result
      assert result["id"] == "target-id"
      assert result["name"] == "Target"
      assert result["env"] == "production"
      assert length(result["workflows"]) == 1

      workflow = hd(result["workflows"])
      assert workflow["id"] == "workflow-target"
      assert workflow["name"] == "Test Workflow"

      # Verify the job body was updated from source
      job = hd(workflow["jobs"])
      assert job["body"] == "console.log('updated')"
    end

    test "writes merged output to file when --output flag is provided", %{
      tmp_dir: tmp_dir
    } do
      source_state = %{
        "id" => "source-id",
        "name" => "Source",
        "workflows" => []
      }

      target_state = %{
        "id" => "target-id",
        "name" => "Target",
        "workflows" => []
      }

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")
      output_file = Path.join(tmp_dir, "output.json")

      File.write!(source_file, Jason.encode!(source_state))
      File.write!(target_file, Jason.encode!(target_state))

      capture_io(fn ->
        Mix.Tasks.Lightning.MergeProjects.run([
          source_file,
          target_file,
          "--output",
          output_file
        ])
      end)

      assert File.exists?(output_file)
      {:ok, content} = File.read(output_file)
      {:ok, result} = Jason.decode(content)

      assert result["id"] == "target-id"
      assert result["name"] == "Target"
    end

    test "writes merged output to file when -o flag is provided", %{
      tmp_dir: tmp_dir
    } do
      source_state = %{
        "id" => "source-id",
        "name" => "Source",
        "workflows" => []
      }

      target_state = %{
        "id" => "target-id",
        "name" => "Target",
        "workflows" => []
      }

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")
      output_file = Path.join(tmp_dir, "output.json")

      File.write!(source_file, Jason.encode!(source_state))
      File.write!(target_file, Jason.encode!(target_state))

      capture_io(fn ->
        Mix.Tasks.Lightning.MergeProjects.run([
          source_file,
          target_file,
          "-o",
          output_file
        ])
      end)

      assert File.exists?(output_file)
      {:ok, content} = File.read(output_file)
      {:ok, result} = Jason.decode(content)

      assert result["id"] == "target-id"
    end

    test "raises error when source file does not exist", %{tmp_dir: tmp_dir} do
      target_file = Path.join(tmp_dir, "target.json")
      File.write!(target_file, Jason.encode!(%{}))

      assert_raise Mix.Error, ~r/Source file not found/, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([
          "/nonexistent/source.json",
          target_file
        ])
      end
    end

    test "raises error when target file does not exist", %{tmp_dir: tmp_dir} do
      source_file = Path.join(tmp_dir, "source.json")
      File.write!(source_file, Jason.encode!(%{}))

      assert_raise Mix.Error, ~r/Target file not found/, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([
          source_file,
          "/nonexistent/target.json"
        ])
      end
    end

    test "raises error when source file is invalid JSON", %{tmp_dir: tmp_dir} do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, "invalid json {")
      File.write!(target_file, Jason.encode!(%{}))

      assert_raise Mix.Error, ~r/Failed to parse source file as JSON/, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
      end
    end

    test "raises error when target file is invalid JSON", %{tmp_dir: tmp_dir} do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(%{}))
      File.write!(target_file, "invalid json {")

      assert_raise Mix.Error, ~r/Failed to parse target file as JSON/, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
      end
    end

    test "raises error when no arguments provided" do
      assert_raise Mix.Error,
                   ~r/Expected exactly 2 arguments: SOURCE_FILE and TARGET_FILE/,
                   fn ->
                     Mix.Tasks.Lightning.MergeProjects.run([])
                   end
    end

    test "raises error when only one argument provided", %{tmp_dir: tmp_dir} do
      source_file = Path.join(tmp_dir, "source.json")

      assert_raise Mix.Error,
                   ~r/Expected exactly 2 arguments: SOURCE_FILE and TARGET_FILE/,
                   fn ->
                     Mix.Tasks.Lightning.MergeProjects.run([source_file])
                   end
    end

    test "raises error when too many arguments provided" do
      assert_raise Mix.Error,
                   ~r/Expected exactly 2 arguments: SOURCE_FILE and TARGET_FILE/,
                   fn ->
                     Mix.Tasks.Lightning.MergeProjects.run([
                       "file1",
                       "file2",
                       "file3"
                     ])
                   end
    end

    test "raises error when invalid options provided", %{tmp_dir: tmp_dir} do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      assert_raise Mix.Error, ~r/Invalid options/, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([
          source_file,
          target_file,
          "--invalid-option",
          "value"
        ])
      end
    end
  end
end
