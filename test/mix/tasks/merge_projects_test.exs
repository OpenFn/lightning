defmodule Mix.Tasks.Lightning.MergeProjectsTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias Lightning.Projects.MergeProjects

  @moduletag :tmp_dir

  describe "complex project structures" do
    test "handles all key types from real state files including cron and kafka",
         %{
           tmp_dir: tmp_dir
         } do
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

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end)

      json_output =
        output |> String.split("\n") |> Enum.drop(1) |> Enum.join("\n")

      {:ok, result} = Jason.decode(json_output)

      assert result["id"] == "target-id"

      workflow = hd(result["workflows"])
      trigger = hd(workflow["triggers"])
      assert trigger["type"] == "cron"
      assert trigger["cron_expression"] == "0 0 * * *"
      assert trigger["comment"] == "Daily trigger"
      assert trigger["kafka_configuration"] == %{"topic" => "test"}
    end

    test "handles unknown string keys without crashing", %{
      tmp_dir: tmp_dir
    } do
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

      assert result["id"] == "target-id"

      # Unknown field is not preserved (merge logic uses Map.take for known fields only)
      refute Map.has_key?(result, "unknown_custom_field")
    end

    test "handles deeply nested structures with all key types", %{
      tmp_dir: tmp_dir
    } do
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

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end)

      json_output =
        output |> String.split("\n") |> Enum.drop(1) |> Enum.join("\n")

      {:ok, result} = Jason.decode(json_output)

      assert result["id"] == "target-id"
      assert length(result["workflows"]) == 1
    end

    test "MergeProjects.merge_project/2 works with atom keys" do
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

      assert result["id"] == "target-id"
      assert result["name"] == "Target"
    end
  end

  describe "run/1" do
    test "merges two valid project state files and outputs to stdout", %{
      tmp_dir: tmp_dir
    } do
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

      assert result["id"] == "target-id"
      assert result["name"] == "Target"
      assert result["env"] == "production"
      assert length(result["workflows"]) == 1

      workflow = hd(result["workflows"])
      assert workflow["id"] == "workflow-target"
      assert workflow["name"] == "Test Workflow"

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

      assert_raise Mix.Error, ~r/Unknown option/, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([
          source_file,
          target_file,
          "--invalid-option",
          "value"
        ])
      end
    end
  end

  describe "file permission errors" do
    test "raises clear error when source file is not readable", %{
      tmp_dir: tmp_dir
    } do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(%{}))
      File.write!(target_file, Jason.encode!(%{}))

      File.chmod!(source_file, 0o000)

      try do
        assert_raise Mix.Error, ~r/Permission denied reading source file/, fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end
      after
        File.chmod!(source_file, 0o644)
      end
    end

    test "raises clear error when target file is not readable", %{
      tmp_dir: tmp_dir
    } do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(%{}))
      File.write!(target_file, Jason.encode!(%{}))

      File.chmod!(target_file, 0o000)

      try do
        assert_raise Mix.Error, ~r/Permission denied reading target file/, fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end
      after
        File.chmod!(target_file, 0o644)
      end
    end
  end

  describe "output path validation" do
    test "raises clear error when File.stat fails on output directory", %{
      tmp_dir: tmp_dir
    } do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(
        source_file,
        Jason.encode!(%{"id" => "s", "name" => "S", "workflows" => []})
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      output_dir = Path.join(tmp_dir, "output_dir")
      File.mkdir_p!(output_dir)
      output_file = Path.join(output_dir, "output.json")

      :meck.new(File, [:passthrough, :unstick])

      try do
        # Mock File.stat to return an error for the specific directory
        :meck.expect(File, :stat, fn path ->
          if String.ends_with?(path, "output_dir") do
            {:error, :eacces}
          else
            :meck.passthrough([path])
          end
        end)

        assert_raise Mix.Error, ~r/Cannot access output directory/, fn ->
          Mix.Tasks.Lightning.MergeProjects.run([
            source_file,
            target_file,
            "-o",
            output_file
          ])
        end
      after
        :meck.unload(File)
      end
    end

    test "raises clear error when output directory does not exist", %{
      tmp_dir: tmp_dir
    } do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(
        source_file,
        Jason.encode!(%{"id" => "s", "name" => "S", "workflows" => []})
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      nonexistent_dir = Path.join(tmp_dir, "nonexistent/deeply/nested")
      output_file = Path.join(nonexistent_dir, "output.json")

      assert_raise Mix.Error, ~r/Output directory does not exist/, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([
          source_file,
          target_file,
          "-o",
          output_file
        ])
      end
    end

    test "raises clear error when output directory is not writable", %{
      tmp_dir: tmp_dir
    } do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(
        source_file,
        Jason.encode!(%{"id" => "s", "name" => "S", "workflows" => []})
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      readonly_dir = Path.join(tmp_dir, "readonly")
      File.mkdir_p!(readonly_dir)
      output_file = Path.join(readonly_dir, "output.json")

      File.chmod!(readonly_dir, 0o555)

      try do
        assert_raise Mix.Error, ~r/No write permission for directory/, fn ->
          Mix.Tasks.Lightning.MergeProjects.run([
            source_file,
            target_file,
            "-o",
            output_file
          ])
        end
      after
        File.chmod!(readonly_dir, 0o755)
      end
    end
  end

  describe "output write errors" do
    test "raises clear error when output file cannot be written due to permissions",
         %{
           tmp_dir: tmp_dir
         } do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(
        source_file,
        Jason.encode!(%{"id" => "s", "name" => "S", "workflows" => []})
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      output_file = Path.join(tmp_dir, "readonly_output.json")
      File.write!(output_file, "")
      File.chmod!(output_file, 0o444)

      try do
        assert_raise Mix.Error, ~r/Permission denied writing to/, fn ->
          Mix.Tasks.Lightning.MergeProjects.run([
            source_file,
            target_file,
            "-o",
            output_file
          ])
        end
      after
        # Cleanup
        File.chmod!(output_file, 0o644)
      end
    end

    test "raises clear error when parent directory becomes unwritable during merge",
         %{
           tmp_dir: tmp_dir
         } do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(
        source_file,
        Jason.encode!(%{"id" => "s", "name" => "S", "workflows" => []})
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      # This tests the case where validation detects unwritable directory
      # The early validation will catch this before merge
      protected_dir = Path.join(tmp_dir, "protected")
      File.mkdir_p!(protected_dir)
      output_file = Path.join(protected_dir, "output.json")

      File.chmod!(protected_dir, 0o555)

      try do
        assert_raise Mix.Error, ~r/No write permission for directory/, fn ->
          Mix.Tasks.Lightning.MergeProjects.run([
            source_file,
            target_file,
            "-o",
            output_file
          ])
        end
      after
        File.chmod!(protected_dir, 0o755)
      end
    end
  end

  describe "merge operation errors" do
    test "raises clear error when project structure causes merge to fail", %{
      tmp_dir: tmp_dir
    } do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      # Source with workflows as a string instead of array
      # This will cause an Enum error when MergeProjects tries to iterate
      File.write!(
        source_file,
        Jason.encode!(%{
          "id" => "source-id",
          "name" => "Source",
          "workflows" => "NOT_AN_ARRAY"
        })
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      assert_raise Mix.Error, ~r/Failed to merge projects/, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
      end
    end

    test "raises clear error with KeyError details when required field is missing",
         %{
           tmp_dir: tmp_dir
         } do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      # Missing 'workflows' key will cause KeyError
      File.write!(
        source_file,
        Jason.encode!(%{"id" => "source-id", "name" => "Source"})
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      assert_raise Mix.Error, ~r/Failed to merge projects/, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
      end
    end

    test "raises clear error for generic merge exception", %{tmp_dir: tmp_dir} do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      # Create source with data that will cause an ArgumentError in merge_project
      # when trying to iterate over workflows as if they were a list
      File.write!(
        source_file,
        Jason.encode!(%{
          "id" => "s",
          "name" => "Source",
          "workflows" => "not_a_list"
        })
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "Target", "workflows" => []})
      )

      assert_raise Mix.Error, ~r/Failed to merge projects/, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
      end
    end
  end

  describe "additional file operation errors" do
    test "raises clear error for generic file read errors", %{tmp_dir: tmp_dir} do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(
        source_file,
        Jason.encode!(%{"id" => "s", "name" => "S", "workflows" => []})
      )

      # Create a directory with the same name as our target file
      # This will cause File.read to fail with :eisdir (is a directory) error
      File.mkdir_p!(target_file)

      try do
        assert_raise Mix.Error, ~r/Failed to read target file/, fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end
      after
        File.rm_rf!(target_file)
      end
    end

    test "raises clear error for generic file write errors", %{tmp_dir: tmp_dir} do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(
        source_file,
        Jason.encode!(%{"id" => "s", "name" => "S", "workflows" => []})
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      # Create a symlink to a directory for the output file
      # Then try to write to it, which will fail with :eisdir
      output_dir = Path.join(tmp_dir, "output_as_dir")
      File.mkdir_p!(output_dir)

      output_file = Path.join(tmp_dir, "output.json")

      :ok =
        :file.make_symlink(
          String.to_charlist(output_dir),
          String.to_charlist(output_file)
        )

      try do
        assert_raise Mix.Error, ~r/Failed to write merged project/, fn ->
          Mix.Tasks.Lightning.MergeProjects.run([
            source_file,
            target_file,
            "-o",
            output_file
          ])
        end
      after
        File.rm(output_file)
        File.rm_rf!(output_dir)
      end
    end

    test "raises clear error when file stat cannot access directory", %{
      tmp_dir: tmp_dir
    } do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(
        source_file,
        Jason.encode!(%{"id" => "s", "name" => "S", "workflows" => []})
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      # Create a symlink to a non-existent directory
      # This will cause File.dir? to return true (symlink exists)
      # But File.stat will fail
      nonexistent = Path.join(tmp_dir, "nonexistent")
      output_dir = Path.join(tmp_dir, "broken_link")

      :ok =
        :file.make_symlink(
          String.to_charlist(nonexistent),
          String.to_charlist(output_dir)
        )

      output_file = Path.join(output_dir, "output.json")

      try do
        assert_raise Mix.Error, ~r/Output directory does not exist/, fn ->
          Mix.Tasks.Lightning.MergeProjects.run([
            source_file,
            target_file,
            "-o",
            output_file
          ])
        end
      after
        File.rm(output_dir)
      end
    end
  end

  describe "JSON encoding errors with mocking" do
    test "handles Protocol.UndefinedError from Jason.encode", %{tmp_dir: tmp_dir} do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(
        source_file,
        Jason.encode!(%{"id" => "s", "name" => "S", "workflows" => []})
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      :meck.new(Jason, [:passthrough])

      :meck.expect(Jason, :encode!, fn _data, _opts ->
        raise Protocol.UndefinedError,
          protocol: Jason.Encoder,
          value: %{__struct__: SomeStruct}
      end)

      try do
        assert_raise Mix.Error,
                     ~r/Failed to encode merged project as JSON.*protocol Jason.Encoder not implemented/s,
                     fn ->
                       Mix.Tasks.Lightning.MergeProjects.run([
                         source_file,
                         target_file
                       ])
                     end
      after
        :meck.unload(Jason)
      end
    end

    test "handles generic Jason encoding errors", %{tmp_dir: tmp_dir} do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(
        source_file,
        Jason.encode!(%{"id" => "s", "name" => "S", "workflows" => []})
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      :meck.new(Jason, [:passthrough])

      :meck.expect(Jason, :encode!, fn _data, _opts ->
        raise RuntimeError, "Unexpected encoding error"
      end)

      try do
        assert_raise Mix.Error,
                     ~r/Failed to encode merged project as JSON/,
                     fn ->
                       Mix.Tasks.Lightning.MergeProjects.run([
                         source_file,
                         target_file
                       ])
                     end
      after
        :meck.unload(Jason)
      end
    end
  end

  describe "File.write errors with mocking" do
    test "handles :enoent error during File.write", %{tmp_dir: tmp_dir} do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")
      output_file = Path.join(tmp_dir, "output.json")

      File.write!(
        source_file,
        Jason.encode!(%{"id" => "s", "name" => "S", "workflows" => []})
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      :meck.new(File, [:passthrough, :unstick])

      :meck.expect(File, :write, fn ^output_file, _content ->
        {:error, :enoent}
      end)

      try do
        assert_raise Mix.Error, ~r/Output directory does not exist/, fn ->
          Mix.Tasks.Lightning.MergeProjects.run([
            source_file,
            target_file,
            "-o",
            output_file
          ])
        end
      after
        :meck.unload(File)
      end
    end

    test "handles :enospc (disk full) error during File.write", %{
      tmp_dir: tmp_dir
    } do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")
      output_file = Path.join(tmp_dir, "output.json")

      File.write!(
        source_file,
        Jason.encode!(%{"id" => "s", "name" => "S", "workflows" => []})
      )

      File.write!(
        target_file,
        Jason.encode!(%{"id" => "t", "name" => "T", "workflows" => []})
      )

      :meck.new(File, [:passthrough, :unstick])

      :meck.expect(File, :write, fn ^output_file, _content ->
        {:error, :enospc}
      end)

      try do
        assert_raise Mix.Error, ~r/Not enough disk space/, fn ->
          Mix.Tasks.Lightning.MergeProjects.run([
            source_file,
            target_file,
            "-o",
            output_file
          ])
        end
      after
        :meck.unload(File)
      end
    end
  end
end
