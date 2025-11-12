defmodule Mix.Tasks.Lightning.MergeProjectsTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  import Lightning.MergeProjectsHelpers

  @moduletag :tmp_dir

  describe "run/1 - basic functionality" do
    test "merges two valid project state files and outputs to stdout", %{
      tmp_dir: tmp_dir
    } do
      source_state =
        build_simple_project(
          id: "source-id",
          name: "source-project",
          workflow_name: "Test Workflow",
          job_name: "Job 1",
          job_body: "console.log('updated')"
        )

      target_state =
        build_simple_project(
          id: "target-id",
          name: "target-project",
          env: "production",
          workflow_name: "Test Workflow",
          job_name: "Job 1",
          job_body: "console.log('old')"
        )

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(source_state))
      File.write!(target_file, Jason.encode!(target_state))

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end)

      {:ok, result} = Jason.decode(output)

      assert result["id"] == "target-id"
      assert result["name"] == "target-project"
      assert length(result["workflows"]) == 1

      workflow = hd(result["workflows"])
      target_workflow = hd(target_state["workflows"])
      assert workflow["id"] == target_workflow["id"]
      assert workflow["name"] == "Test Workflow"

      job = hd(workflow["jobs"])
      assert job["body"] == "console.log('updated')"
    end

    test "writes merged output to file when --output flag is provided", %{
      tmp_dir: tmp_dir
    } do
      source_state =
        build_project_state(
          id: "source-id",
          name: "source-project",
          workflows: []
        )

      target_state =
        build_project_state(
          id: "target-id",
          name: "target-project",
          workflows: []
        )

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
      assert result["name"] == "target-project"
    end

    test "writes merged output to file when -o flag is provided", %{
      tmp_dir: tmp_dir
    } do
      source_state =
        build_project_state(
          id: "source-id",
          name: "source-project",
          workflows: []
        )

      target_state =
        build_project_state(
          id: "target-id",
          name: "target-project",
          workflows: []
        )

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
  end

  describe "run/1 - argument validation" do
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

  describe "run/1 - file operation errors" do
    test "raises error when source file does not exist", %{tmp_dir: tmp_dir} do
      target_file = Path.join(tmp_dir, "target.json")
      File.write!(target_file, Jason.encode!(%{}))

      nonexistent_file =
        Path.join(tmp_dir, "nonexistent_#{:rand.uniform(999_999)}.json")

      assert_raise Mix.Error, ~r/Source file not found/, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([
          nonexistent_file,
          target_file
        ])
      end
    end

    test "raises error when target file does not exist", %{tmp_dir: tmp_dir} do
      source_file = Path.join(tmp_dir, "source.json")
      File.write!(source_file, Jason.encode!(%{}))

      nonexistent_file =
        Path.join(tmp_dir, "nonexistent_#{:rand.uniform(999_999)}.json")

      assert_raise Mix.Error, ~r/Target file not found/, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([
          source_file,
          nonexistent_file
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

  describe "run/1 - output path validation" do
    test "raises clear error when output directory does not exist", %{
      tmp_dir: tmp_dir
    } do
      source_state =
        build_project_state(id: "s", name: "source-project", workflows: [])

      target_state =
        build_project_state(id: "t", name: "target-project", workflows: [])

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(source_state))
      File.write!(target_file, Jason.encode!(target_state))

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
      source_state =
        build_project_state(id: "s", name: "source-project", workflows: [])

      target_state =
        build_project_state(id: "t", name: "target-project", workflows: [])

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(source_state))
      File.write!(target_file, Jason.encode!(target_state))

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

    test "raises clear error when output file cannot be written due to permissions",
         %{
           tmp_dir: tmp_dir
         } do
      source_state =
        build_project_state(id: "s", name: "source-project", workflows: [])

      target_state =
        build_project_state(id: "t", name: "target-project", workflows: [])

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(source_state))
      File.write!(target_file, Jason.encode!(target_state))

      output_file = Path.join(tmp_dir, "readonly_output.json")
      File.write!(output_file, "")
      File.chmod!(output_file, 0o444)

      try do
        assert_raise Mix.Error, ~r/Permission denied writing to/, fn ->
          capture_io(fn ->
            Mix.Tasks.Lightning.MergeProjects.run([
              source_file,
              target_file,
              "-o",
              output_file
            ])
          end)
        end
      after
        File.chmod!(output_file, 0o644)
      end
    end
  end

  describe "run/1 - merge operation errors" do
    test "raises error when project structure causes merge to fail", %{
      tmp_dir: tmp_dir
    } do
      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

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

      # The merge will fail with Protocol.UndefinedError when trying to
      # enumerate workflows (which is a string instead of a list)
      # This is expected behavior - we let the merge algorithm fail naturally
      assert_raise Protocol.UndefinedError, fn ->
        Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
      end
    end
  end

  describe "run/1 - flexibility for testing (Joe's requirements)" do
    test "allows non-UUID IDs for testing purposes", %{tmp_dir: tmp_dir} do
      source_state =
        build_simple_project(
          id: "test-source-1",
          name: "source-project",
          workflow_name: "Test Workflow",
          job_name: "Job 1",
          job_body: "console.log('updated')"
        )

      target_state =
        build_simple_project(
          id: "test-target-1",
          name: "target-project",
          workflow_name: "Test Workflow",
          job_name: "Job 1",
          job_body: "console.log('old')"
        )

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(source_state))
      File.write!(target_file, Jason.encode!(target_state))

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end)

      {:ok, result} = Jason.decode(output)

      assert result["id"] == "test-target-1"
      assert result["name"] == "target-project"
    end

    test "handles projects with simple numeric IDs", %{tmp_dir: tmp_dir} do
      source_state =
        build_project_state(
          id: "1",
          name: "source-project",
          workflows: []
        )

      target_state =
        build_project_state(
          id: "2",
          name: "target-project",
          workflows: []
        )

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(source_state))
      File.write!(target_file, Jason.encode!(target_state))

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end)

      {:ok, result} = Jason.decode(output)

      assert result["id"] == "2"
      assert result["name"] == "target-project"
    end

    test "successfully merges projects with deeply nested structures", %{
      tmp_dir: tmp_dir
    } do
      source_state =
        build_simple_project(
          id: "source",
          name: "Source Project",
          workflow_name: "Workflow 1",
          job_name: "Job 1",
          job_body: "console.log('updated')"
        )

      target_state =
        build_simple_project(
          id: "target",
          name: "Target Project",
          workflow_name: "Workflow 1",
          job_name: "Job 1",
          job_body: "console.log('old')"
        )

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(source_state))
      File.write!(target_file, Jason.encode!(target_state))

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end)

      {:ok, result} = Jason.decode(output)

      assert result["id"] == "target"

      workflow = hd(result["workflows"])
      assert workflow["name"] == "Workflow 1"

      job = hd(workflow["jobs"])
      assert job["body"] == "console.log('updated')"
      assert job["name"] == "Job 1"
    end

    test "works offline without database access", %{tmp_dir: tmp_dir} do
      source_state =
        build_project_state(
          id: "offline-source",
          name: "source-project",
          workflows: []
        )

      target_state =
        build_project_state(
          id: "offline-target",
          name: "target-project",
          workflows: []
        )

      source_file = Path.join(tmp_dir, "source.json")
      target_file = Path.join(tmp_dir, "target.json")

      File.write!(source_file, Jason.encode!(source_state))
      File.write!(target_file, Jason.encode!(target_state))

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.MergeProjects.run([source_file, target_file])
        end)

      {:ok, result} = Jason.decode(output)

      assert result["id"] == "offline-target"
    end
  end
end
