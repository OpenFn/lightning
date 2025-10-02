defmodule Lightning.Collaboration.WorkflowSerializerTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Collaboration.WorkflowSerializer
  alias Lightning.Workflows
  alias Lightning.Repo

  # Helper to preload all workflow associations needed for serialization
  defp preload_workflow_associations(workflow) do
    Repo.preload(workflow, [:jobs, :edges, :triggers])
  end

  describe "serialize_to_ydoc/2" do
    test "writes workflow with nil name as empty string" do
      workflow =
        insert(:workflow, name: nil)
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      workflow_map = Yex.Doc.get_map(doc, "workflow")
      assert Yex.Map.fetch!(workflow_map, "name") == ""
    end

    test "writes jobs array to Y.Doc" do
      workflow =
        build(:workflow)
        |> with_job(build(:job, name: "Job 1", body: "console.log('1');"))
        |> with_job(build(:job, name: "Job 2", body: "console.log('2');"))
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      # Verify jobs array exists
      jobs_array = Yex.Doc.get_array(doc, "jobs")
      assert Yex.Array.length(jobs_array) == 2

      # Verify job structure and field types
      job1 = Yex.Array.fetch!(jobs_array, 0)
      assert job1["id"] == Enum.at(workflow.jobs, 0).id
      assert job1["name"] == "Job 1"

      # Body should be Y.Text
      assert %Yex.Text{} = job1["body"]
      assert Yex.Text.to_string(job1["body"]) == "console.log('1');"

      assert is_binary(job1["adaptor"]) or is_nil(job1["adaptor"])
    end

    test "handles jobs with nil values" do
      workflow =
        build(:workflow)
        |> with_job(
          build(:job,
            name: nil,
            body: nil,
            adaptor: nil,
            project_credential_id: nil
          )
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      jobs_array = Yex.Doc.get_array(doc, "jobs")
      job = Yex.Array.fetch!(jobs_array, 0)

      assert job["name"] == ""
      assert Yex.Text.to_string(job["body"]) == ""
      assert is_nil(job["adaptor"])
      assert is_nil(job["project_credential_id"])
      assert is_nil(job["keychain_credential_id"])
    end

    test "writes edges array to Y.Doc" do
      trigger = build(:trigger, type: :webhook)
      job1 = build(:job, name: "Job 1")
      job2 = build(:job, name: "Job 2")

      workflow =
        build(:workflow)
        |> with_trigger(trigger)
        |> with_job(job1)
        |> with_job(job2)
        |> with_edge({trigger, job1}, condition_type: :always)
        |> with_edge({job1, job2},
          condition_type: :on_job_success,
          condition_label: "Success",
          condition_expression: "state.success == true",
          enabled: true
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      # Verify edges array
      edges_array = Yex.Doc.get_array(doc, "edges")
      assert Yex.Array.length(edges_array) == 2

      # Check first edge (trigger -> job1)
      edge1 = Yex.Array.fetch!(edges_array, 0)
      workflow_edge1 = Enum.at(workflow.edges, 0)
      assert edge1["id"] == workflow_edge1.id
      assert edge1["condition_type"] == "always"
      assert edge1["source_trigger_id"] == trigger.id
      assert edge1["target_job_id"] == job1.id
      assert is_nil(edge1["source_job_id"])
      assert edge1["enabled"] == workflow_edge1.enabled

      # Check second edge (job1 -> job2)
      edge2 = Yex.Array.fetch!(edges_array, 1)
      assert edge2["condition_type"] == "on_job_success"
      assert edge2["condition_label"] == "Success"
      assert edge2["condition_expression"] == "state.success == true"
      assert edge2["source_job_id"] == job1.id
      assert edge2["target_job_id"] == job2.id
      assert is_nil(edge2["source_trigger_id"])
    end

    test "converts edge condition_type atoms to strings" do
      [job1, job2] = build_list(2, :job)

      workflow =
        build(:workflow)
        |> with_job(job1)
        |> with_job(job2)
        |> with_edge({job1, job2}, condition_type: :on_job_failure)
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      edges_array = Yex.Doc.get_array(doc, "edges")
      edge = Yex.Array.fetch!(edges_array, 0)

      # Should be converted to string
      assert edge["condition_type"] == "on_job_failure"
      assert is_binary(edge["condition_type"])
    end

    test "writes triggers array to Y.Doc with webhook trigger" do
      workflow =
        build(:workflow)
        |> with_trigger(
          build(:trigger,
            type: :webhook,
            enabled: true,
            has_auth_method: false
          )
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      # Verify triggers array
      triggers_array = Yex.Doc.get_array(doc, "triggers")
      assert Yex.Array.length(triggers_array) == 1

      trigger = Yex.Array.fetch!(triggers_array, 0)
      workflow_trigger = Enum.at(workflow.triggers, 0)

      assert trigger["id"] == workflow_trigger.id
      assert trigger["type"] == "webhook"
      assert trigger["enabled"] == true
      assert trigger["has_auth_method"] == false
      assert is_nil(trigger["cron_expression"])
    end

    test "writes triggers array with cron trigger" do
      workflow =
        build(:workflow)
        |> with_trigger(
          build(:trigger,
            type: :cron,
            enabled: false,
            cron_expression: "0 0 * * *"
          )
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      triggers_array = Yex.Doc.get_array(doc, "triggers")
      trigger = Yex.Array.fetch!(triggers_array, 0)

      assert trigger["type"] == "cron"
      assert trigger["cron_expression"] == "0 0 * * *"
      assert trigger["enabled"] == false
    end

    test "converts trigger type atoms to strings" do
      workflow =
        build(:workflow)
        |> with_trigger(build(:trigger, type: :kafka))
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      triggers_array = Yex.Doc.get_array(doc, "triggers")
      trigger = Yex.Array.fetch!(triggers_array, 0)

      # Should be converted to string
      assert trigger["type"] == "kafka"
      assert is_binary(trigger["type"])
    end

    test "writes positions map to Y.Doc" do
      [job1, job2] = build_list(2, :job)

      positions = %{
        job1.id => %{"x" => 100, "y" => 200},
        job2.id => %{"x" => 300, "y" => 400}
      }

      workflow =
        build(:workflow, positions: positions)
        |> with_job(job1)
        |> with_job(job2)
        |> with_edge({job1, job2}, condition_type: :always)
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      # Verify positions map
      positions_map = Yex.Doc.get_map(doc, "positions")
      positions_json = Yex.Map.to_json(positions_map)

      assert positions_json[job1.id] == %{"x" => 100, "y" => 200}
      assert positions_json[job2.id] == %{"x" => 300, "y" => 400}
    end

    test "handles workflow with all component types" do
      # Create a complex workflow with jobs, triggers, edges, and positions
      workflow =
        insert(:complex_workflow, name: "Complex Workflow")
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      # Verify all collections exist and have correct lengths
      workflow_map = Yex.Doc.get_map(doc, "workflow")
      assert Yex.Map.fetch!(workflow_map, "id") == workflow.id
      assert Yex.Map.fetch!(workflow_map, "name") == "Complex Workflow"

      jobs_array = Yex.Doc.get_array(doc, "jobs")
      assert Yex.Array.length(jobs_array) == length(workflow.jobs)

      edges_array = Yex.Doc.get_array(doc, "edges")
      assert Yex.Array.length(edges_array) == length(workflow.edges)

      triggers_array = Yex.Doc.get_array(doc, "triggers")
      assert Yex.Array.length(triggers_array) == length(workflow.triggers)

      # Verify all jobs are present with correct IDs
      job_ids =
        jobs_array
        |> Yex.Array.to_list()
        |> Enum.map(& &1["id"])
        |> MapSet.new()

      workflow_job_ids = workflow.jobs |> Enum.map(& &1.id) |> MapSet.new()
      assert MapSet.equal?(job_ids, workflow_job_ids)

      # Verify all edges are present with correct IDs
      edge_ids =
        edges_array
        |> Yex.Array.to_list()
        |> Enum.map(& &1["id"])
        |> MapSet.new()

      workflow_edge_ids = workflow.edges |> Enum.map(& &1.id) |> MapSet.new()
      assert MapSet.equal?(edge_ids, workflow_edge_ids)
    end

    test "handles empty collections" do
      # Workflow with no jobs, edges, triggers, or positions
      workflow =
        insert(:workflow, name: "Empty Workflow")
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      # Verify collections exist but are empty
      jobs_array = Yex.Doc.get_array(doc, "jobs")
      assert Yex.Array.length(jobs_array) == 0

      edges_array = Yex.Doc.get_array(doc, "edges")
      assert Yex.Array.length(edges_array) == 0

      triggers_array = Yex.Doc.get_array(doc, "triggers")
      assert Yex.Array.length(triggers_array) == 0

      positions_map = Yex.Doc.get_map(doc, "positions")
      assert Yex.Map.to_json(positions_map) == %{}
    end

    test "returns the doc for chaining" do
      workflow =
        insert(:workflow)
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      result = WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      # Should return the same doc reference
      assert result == doc
    end

    test "handles all edge condition types" do
      [job1, job2, job3, job4] = build_list(4, :job)

      workflow =
        build(:workflow)
        |> with_job(job1)
        |> with_job(job2)
        |> with_job(job3)
        |> with_job(job4)
        |> with_edge({job1, job2}, condition_type: :always)
        |> with_edge({job1, job3}, condition_type: :on_job_success)
        |> with_edge({job1, job4}, condition_type: :on_job_failure)
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      edges_array = Yex.Doc.get_array(doc, "edges")

      condition_types =
        edges_array
        |> Yex.Array.to_list()
        |> Enum.map(& &1["condition_type"])
        |> Enum.sort()

      # All should be strings
      assert condition_types == ["always", "on_job_failure", "on_job_success"]
    end

    test "preserves job credential references" do
      project = insert(:project)

      credential =
        insert(:credential,
          project_credentials: [%{project_id: project.id}]
        )

      project_credential =
        Enum.find(credential.project_credentials, &(&1.project_id == project.id))

      workflow =
        build(:workflow, project: project)
        |> with_job(
          build(:job,
            name: "Job with creds",
            project_credential_id: project_credential.id
          )
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      jobs_array = Yex.Doc.get_array(doc, "jobs")
      job = Yex.Array.fetch!(jobs_array, 0)

      assert job["project_credential_id"] == project_credential.id
    end

    test "handles workflow preloaded from database" do
      # Create and insert workflow
      workflow_from_factory = insert(:simple_workflow)

      # Reload from database with preloads (simulating real usage)
      workflow =
        Workflows.get_workflow(workflow_from_factory.id,
          include: [:jobs, :edges, :triggers]
        )

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      # Should work exactly the same as factory-built workflows
      workflow_map = Yex.Doc.get_map(doc, "workflow")
      assert Yex.Map.fetch!(workflow_map, "id") == workflow.id

      jobs_array = Yex.Doc.get_array(doc, "jobs")
      assert Yex.Array.length(jobs_array) == length(workflow.jobs)

      edges_array = Yex.Doc.get_array(doc, "edges")
      assert Yex.Array.length(edges_array) == length(workflow.edges)

      triggers_array = Yex.Doc.get_array(doc, "triggers")
      assert Yex.Array.length(triggers_array) == length(workflow.triggers)
    end
  end

  describe "integration with Session" do
    test "Session.initialize_workflow_data/2 delegates correctly" do
      workflow = insert(:simple_workflow, name: "Session Test")
      doc = Yex.Doc.new()

      # This should delegate to WorkflowSerializer.serialize_to_ydoc/2
      result =
        Lightning.Collaboration.Session.initialize_workflow_document(
          doc,
          workflow.id
        )

      # Should return the doc
      assert result == doc

      # Verify structure is correct
      workflow_map = Yex.Doc.get_map(doc, "workflow")
      assert Yex.Map.fetch!(workflow_map, "name") == "Session Test"

      jobs_array = Yex.Doc.get_array(doc, "jobs")
      assert Yex.Array.length(jobs_array) == length(workflow.jobs)
    end
  end

  describe "deserialize_from_ydoc/2" do
    test "extracts workflow data from Y.Doc" do
      # Create a workflow with all components
      trigger = build(:trigger, type: :webhook, enabled: true)
      job1 = build(:job, name: "Job 1", body: "console.log('job1');")
      job2 = build(:job, name: "Job 2", body: "console.log('job2');")

      workflow =
        build(:workflow, name: "Test Workflow")
        |> with_trigger(trigger)
        |> with_job(job1)
        |> with_job(job2)
        |> with_edge({trigger, job1}, condition_type: :always)
        |> with_edge({job1, job2}, condition_type: :on_job_success)
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      # Serialize first
      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      # Now deserialize
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      # Verify structure uses string keys
      assert is_map(extracted)
      assert Map.has_key?(extracted, "name")
      assert Map.has_key?(extracted, "jobs")
      assert Map.has_key?(extracted, "edges")
      assert Map.has_key?(extracted, "triggers")
      assert Map.has_key?(extracted, "positions")

      # Verify workflow name
      assert extracted["name"] == "Test Workflow"

      # Verify jobs
      assert length(extracted["jobs"]) == 2
      [extracted_job1, extracted_job2] = extracted["jobs"]

      assert %{
               "id" => job1.id,
               "name" => "Job 1",
               "body" => "console.log('job1');",
               "adaptor" => job1.adaptor,
               "project_credential_id" => job1.project_credential_id,
               "keychain_credential_id" => job1.keychain_credential_id
             } == extracted_job1

      assert %{
               "id" => job2.id,
               "name" => "Job 2",
               "body" => "console.log('job2');",
               "adaptor" => job2.adaptor,
               "project_credential_id" => job2.project_credential_id,
               "keychain_credential_id" => job2.keychain_credential_id
             } == extracted_job2

      # Verify edges
      assert length(extracted["edges"]) == 2
      [extracted_edge1, extracted_edge2] = extracted["edges"]

      workflow_edge1 = Enum.at(workflow.edges, 0)
      workflow_edge2 = Enum.at(workflow.edges, 1)

      assert %{
               "id" => workflow_edge1.id,
               "condition_type" => "always",
               "source_trigger_id" => trigger.id,
               "target_job_id" => job1.id,
               "source_job_id" => nil,
               "condition_expression" => workflow_edge1.condition_expression,
               "condition_label" => workflow_edge1.condition_label,
               "enabled" => workflow_edge1.enabled
             } == extracted_edge1

      assert %{
               "id" => workflow_edge2.id,
               "condition_type" => "on_job_success",
               "source_job_id" => job1.id,
               "target_job_id" => job2.id,
               "source_trigger_id" => nil,
               "condition_expression" => workflow_edge2.condition_expression,
               "condition_label" => workflow_edge2.condition_label,
               "enabled" => workflow_edge2.enabled
             } == extracted_edge2

      # Verify triggers
      assert length(extracted["triggers"]) == 1
      extracted_trigger = List.first(extracted["triggers"])

      assert %{
               "id" => trigger.id,
               "type" => "webhook",
               "enabled" => true,
               "has_auth_method" => trigger.has_auth_method,
               "cron_expression" => nil
             } == extracted_trigger

      # Verify positions is a map
      assert is_map(extracted["positions"])
    end

    test "converts Y.Text body field to String" do
      workflow =
        build(:workflow)
        |> with_job(
          build(:job,
            name: "Test Job",
            body: "fn(state => { return state; })"
          )
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      job = List.first(extracted["jobs"])

      # Body should be converted from Y.Text to String
      assert is_binary(job["body"])
      refute is_struct(job["body"], Yex.Text)
      assert job["body"] == "fn(state => { return state; })"
    end

    test "preserves trigger type as strings" do
      workflow =
        build(:workflow)
        |> with_trigger(build(:trigger, type: :webhook))
        |> with_trigger(
          build(:trigger, type: :cron, cron_expression: "0 * * * *")
        )
        |> with_trigger(build(:trigger, type: :kafka))
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      trigger_types =
        extracted["triggers"]
        |> Enum.map(& &1["type"])
        |> Enum.sort()

      # All types should be strings
      assert trigger_types == ["cron", "kafka", "webhook"]
    end

    test "preserves edge condition_type as strings" do
      [job1, job2, job3, job4] = build_list(4, :job)

      workflow =
        build(:workflow)
        |> with_job(job1)
        |> with_job(job2)
        |> with_job(job3)
        |> with_job(job4)
        |> with_edge({job1, job2}, condition_type: :always)
        |> with_edge({job1, job3}, condition_type: :on_job_success)
        |> with_edge({job1, job4}, condition_type: :on_job_failure)
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      condition_types =
        extracted["edges"]
        |> Enum.map(& &1["condition_type"])
        |> Enum.sort()

      assert condition_types == ["always", "on_job_failure", "on_job_success"]
    end

    test "preserves js_expression condition_type as string" do
      [job1, job2] = build_list(2, :job)

      workflow =
        build(:workflow)
        |> with_job(job1)
        |> with_job(job2)
        |> with_edge({job1, job2},
          condition_type: :js_expression,
          condition_expression: "state.data.success === true"
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      edge = List.first(extracted["edges"])
      assert edge["condition_type"] == "js_expression"
      assert edge["condition_expression"] == "state.data.success === true"
    end

    test "round-trip: serialize then deserialize produces equivalent data" do
      # Create a complex workflow with all field types
      project = insert(:project)

      credential =
        insert(:credential,
          project_credentials: [%{project_id: project.id}]
        )

      project_credential =
        Enum.find(credential.project_credentials, &(&1.project_id == project.id))

      trigger = build(:trigger, type: :cron, cron_expression: "0 0 * * *")

      job1 =
        build(:job,
          name: "Extract Data",
          body: "fn(state => state);",
          adaptor: "@openfn/language-common@1.0.0",
          project_credential_id: project_credential.id
        )

      job2 =
        build(:job,
          name: "Transform Data",
          body: "fn(state => ({ ...state, transformed: true }));",
          adaptor: "@openfn/language-http@2.0.0"
        )

      positions = %{
        job1.id => %{"x" => 100, "y" => 200},
        job2.id => %{"x" => 300, "y" => 400}
      }

      workflow =
        build(:workflow,
          name: "Round Trip Test",
          project: project,
          positions: positions
        )
        |> with_trigger(trigger)
        |> with_job(job1)
        |> with_job(job2)
        |> with_edge({trigger, job1},
          condition_type: :always,
          enabled: true
        )
        |> with_edge({job1, job2},
          condition_type: :on_job_success,
          condition_label: "Success path",
          condition_expression: "state.success == true",
          enabled: false
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      # Serialize
      WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      # Deserialize
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      # Verify all data matches (accounting for type conversions)
      assert extracted["name"] == workflow.name

      # Jobs
      assert length(extracted["jobs"]) == 2

      Enum.each(Enum.zip(extracted["jobs"], workflow.jobs), fn {extracted_job,
                                                                original_job} ->
        assert %{
                 "id" => original_job.id,
                 "name" => original_job.name,
                 "body" => original_job.body,
                 "adaptor" => original_job.adaptor,
                 "project_credential_id" => original_job.project_credential_id,
                 "keychain_credential_id" => original_job.keychain_credential_id
               } == extracted_job
      end)

      # Edges
      assert length(extracted["edges"]) == 2

      Enum.zip(extracted["edges"], workflow.edges)
      |> Enum.each(fn {extracted, original} ->
        assert %{
                 "id" => original.id,
                 "source_trigger_id" => original.source_trigger_id,
                 "source_job_id" => original.source_job_id,
                 "target_job_id" => original.target_job_id,
                 "condition_type" => to_string(original.condition_type),
                 "condition_expression" => original.condition_expression,
                 "condition_label" => original.condition_label,
                 "enabled" => original.enabled
               } == extracted
      end)

      # Triggers
      assert length(extracted["triggers"]) == 1
      extracted_trigger = List.first(extracted["triggers"])
      original_trigger = List.first(workflow.triggers)

      assert %{
               "id" => original_trigger.id,
               "type" => to_string(original_trigger.type),
               "enabled" => original_trigger.enabled,
               "cron_expression" => original_trigger.cron_expression,
               "has_auth_method" => original_trigger.has_auth_method
             } == extracted_trigger

      # Positions
      assert extracted["positions"] == workflow.positions
    end

    test "handles empty collections" do
      workflow =
        insert(:workflow, name: "Empty Workflow")
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      assert %{
               "name" => "Empty Workflow",
               "jobs" => [],
               "edges" => [],
               "triggers" => [],
               "positions" => %{}
             } = extracted
    end

    test "handles nil values in optional job fields" do
      workflow =
        build(:workflow)
        |> with_job(
          build(:job,
            name: nil,
            body: nil,
            adaptor: nil,
            project_credential_id: nil,
            keychain_credential_id: nil
          )
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      job = List.first(extracted["jobs"])

      assert %{
               "name" => "",
               "body" => "",
               "adaptor" => nil,
               "project_credential_id" => nil,
               "keychain_credential_id" => nil
             } = job
    end

    test "handles nil values in optional edge fields" do
      [job1, job2] = build_list(2, :job)

      workflow =
        build(:workflow)
        |> with_job(job1)
        |> with_job(job2)
        |> with_edge({job1, job2},
          condition_type: :always,
          condition_expression: nil,
          condition_label: nil
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      edge = List.first(extracted["edges"])

      assert %{
               "condition_type" => "always",
               "condition_expression" => nil,
               "condition_label" => nil
             } = edge
    end

    test "handles nil cron_expression in triggers" do
      workflow =
        build(:workflow)
        |> with_trigger(build(:trigger, type: :webhook, cron_expression: nil))
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      trigger = List.first(extracted["triggers"])
      assert is_nil(trigger["cron_expression"])
    end

    test "handles empty strings in job fields" do
      workflow =
        build(:workflow)
        |> with_job(
          build(:job,
            name: "",
            body: "",
            adaptor: ""
          )
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      job = List.first(extracted["jobs"])

      assert %{
               "name" => "",
               "body" => "",
               "adaptor" => ""
             } = job
    end

    test "return format has correct structure for save_workflow/2" do
      workflow = insert(:simple_workflow)

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      # Should have these keys
      assert MapSet.subset?(
               MapSet.new([
                 "id",
                 "name",
                 "jobs",
                 "edges",
                 "triggers",
                 "positions"
               ]),
               MapSet.new(Map.keys(extracted))
             )

      # Should NOT have these keys (they're not part of change_workflow)
      assert MapSet.disjoint?(
               MapSet.new([
                 "lock_version",
                 "project_id",
                 "inserted_at",
                 "updated_at"
               ]),
               MapSet.new(Map.keys(extracted))
             )

      # All keys should be strings
      Enum.each(Map.keys(extracted), fn key ->
        assert is_binary(key), "Expected string key, got: #{inspect(key)}"
      end)

      # Jobs should have string keys
      if length(extracted["jobs"]) > 0 do
        job = List.first(extracted["jobs"])

        Enum.each(Map.keys(job), fn key ->
          assert is_binary(key),
                 "Expected string key in job, got: #{inspect(key)}"
        end)
      end
    end

    test "handles workflow preloaded from database" do
      # Create and insert workflow
      workflow_from_factory = insert(:complex_workflow)

      # Reload from database with preloads (simulating real usage)
      workflow =
        Workflows.get_workflow(workflow_from_factory.id,
          include: [:jobs, :edges, :triggers]
        )

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      # Should work exactly the same as factory-built workflows
      assert extracted["name"] == workflow.name
      assert length(extracted["jobs"]) == length(workflow.jobs)
      assert length(extracted["edges"]) == length(workflow.edges)
      assert length(extracted["triggers"]) == length(workflow.triggers)
    end

    test "preserves all 6 job fields" do
      project = insert(:project)

      credential =
        insert(:credential,
          project_credentials: [%{project_id: project.id}]
        )

      project_credential =
        Enum.find(credential.project_credentials, &(&1.project_id == project.id))

      workflow =
        build(:workflow, project: project)
        |> with_job(
          build(:job,
            name: "Test Job",
            body: "console.log('test');",
            adaptor: "@openfn/language-common@1.0.0",
            project_credential_id: project_credential.id,
            keychain_credential_id: nil
          )
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      job = List.first(extracted["jobs"])
      original_job = List.first(workflow.jobs)

      # All 6 fields should be present
      assert %{
               "id" => original_job.id,
               "name" => "Test Job",
               "body" => "console.log('test');",
               "adaptor" => "@openfn/language-common@1.0.0",
               "project_credential_id" => project_credential.id,
               "keychain_credential_id" => nil
             } == job
    end

    test "preserves all 8 edge fields" do
      [job1, job2] = build_list(2, :job)

      workflow =
        build(:workflow)
        |> with_job(job1)
        |> with_job(job2)
        |> with_edge({job1, job2},
          condition_type: :js_expression,
          condition_expression: "state.success === true",
          condition_label: "When successful",
          enabled: false
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      edge = List.first(extracted["edges"])
      original_edge = List.first(workflow.edges)

      # All 8 fields should be present
      assert %{
               "id" => original_edge.id,
               "source_trigger_id" => original_edge.source_trigger_id,
               "source_job_id" => job1.id,
               "target_job_id" => job2.id,
               "condition_type" => "js_expression",
               "condition_expression" => "state.success === true",
               "condition_label" => "When successful",
               "enabled" => false
             } == edge
    end

    test "preserves all 5 trigger fields" do
      workflow =
        build(:workflow)
        |> with_trigger(
          build(:trigger,
            type: :cron,
            enabled: true,
            cron_expression: "0 */6 * * *",
            has_auth_method: false
          )
        )
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      trigger = List.first(extracted["triggers"])
      original_trigger = List.first(workflow.triggers)

      # All 5 fields should be present
      assert %{
               "id" => original_trigger.id,
               "type" => "cron",
               "enabled" => true,
               "cron_expression" => "0 */6 * * *",
               "has_auth_method" => false
             } == trigger
    end

    test "handles complex positions map structure" do
      [job1, job2] = build_list(2, :job)
      trigger = build(:trigger, type: :webhook)

      positions = %{
        job1.id => %{"x" => 150, "y" => 250},
        job2.id => %{"x" => 450, "y" => 350},
        trigger.id => %{"x" => 50, "y" => 100}
      }

      workflow =
        build(:workflow, positions: positions)
        |> with_trigger(trigger)
        |> with_job(job1)
        |> with_job(job2)
        |> with_edge({trigger, job1}, condition_type: :always)
        |> insert()
        |> preload_workflow_associations()

      doc = Yex.Doc.new()

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
      extracted = WorkflowSerializer.deserialize_from_ydoc(doc, workflow.id)

      assert extracted["positions"][job1.id] == %{"x" => 150, "y" => 250}
      assert extracted["positions"][job2.id] == %{"x" => 450, "y" => 350}
      assert extracted["positions"][trigger.id] == %{"x" => 50, "y" => 100}
    end
  end
end
