defmodule Lightning.Projects.MergeProjectsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.MergeProjects

  describe "merge_project/2" do
    test "merge preserves target project identity (name, description, env, color)" do
      target_project =
        insert(:project,
          name: "Production",
          description: "Main production environment",
          env: "production",
          color: "#FF0000"
        )

      source_project =
        insert(:project,
          name: "feature-branch",
          description: "Development sandbox",
          env: "development",
          color: "#00FF00"
        )

      insert(:workflow, name: "shared_workflow", project: target_project)
      insert(:workflow, name: "shared_workflow", project: source_project)

      result = MergeProjects.merge_project(source_project, target_project)

      assert result["id"] == target_project.id

      assert result["name"] == "Production",
             "Target project name should be preserved"

      assert result["description"] == "Main production environment",
             "Target project description should be preserved"

      assert result["env"] == "production",
             "Target project env should be preserved"

      assert result["color"] == "#FF0000",
             "Target project color should be preserved"

      assert length(result["workflows"]) == 1
    end

    test "merge project with matching workflow names" do
      # Create projects using factory
      target_project =
        insert(:project,
          name: "Target Project",
          description: "Original description"
        )

      source_project =
        insert(:project,
          name: "Source Project",
          description: "Updated description"
        )

      # Create workflows using factory
      target_workflow =
        insert(:workflow, name: "shared_workflow", project: target_project)

      source_workflow =
        insert(:workflow, name: "shared_workflow", project: source_project)

      result = MergeProjects.merge_project(source_project, target_project)

      # Should preserve target project identity
      assert result["id"] == target_project.id
      assert result["name"] == target_project.name
      assert result["description"] == target_project.description
      assert result["env"] == target_project.env
      assert result["color"] == target_project.color

      # Should have one workflow (merged)
      assert length(result["workflows"]) == 1
      workflow = hd(result["workflows"])

      # Workflow should preserve target ID but use source name
      assert workflow["id"] == target_workflow.id
      assert workflow["name"] == source_workflow.name

      # Workflow should not be marked for deletion
      refute workflow["delete"]
    end

    test "merge project with new workflow containing jobs, triggers, and edges" do
      target_project = insert(:project, name: "Target Project")
      source_project = insert(:project, name: "Source Project")

      insert(:workflow, name: "existing_workflow", project: target_project)

      {source_new_workflow,
       %{:webhook => source_trigger, "process" => source_job}} =
        generate_workflow([{:webhook, "process"}], %{
          :workflow => %{name: "new_feature", project: source_project},
          "process" => %{
            body: "fn(state => state)",
            adaptor: "@openfn/language-common@latest"
          }
        })

      result = MergeProjects.merge_project(source_project, target_project)

      new_workflow =
        Enum.find(result["workflows"], &(&1["name"] == "new_feature"))

      assert new_workflow, "New workflow should exist"
      assert new_workflow["id"] != source_new_workflow.id, "Should have new UUID"
      refute new_workflow["delete"], "Should not be marked for deletion"

      assert length(new_workflow["jobs"]) == 1, "New workflow should have 1 job"
      new_job = hd(new_workflow["jobs"])
      assert new_job["name"] == source_job.name
      assert new_job["body"] == source_job.body
      assert new_job["adaptor"] == source_job.adaptor
      assert new_job["id"] != source_job.id, "Job should have new UUID"
      refute new_job["delete"]

      assert length(new_workflow["triggers"]) == 1,
             "New workflow should have 1 trigger"

      new_trigger = hd(new_workflow["triggers"])
      assert new_trigger["type"] == source_trigger.type

      assert new_trigger["id"] != source_trigger.id,
             "Trigger should have new UUID"

      refute new_trigger["delete"]

      assert length(new_workflow["edges"]) == 1,
             "New workflow should have 1 edge"

      new_edge = hd(new_workflow["edges"])
      assert new_edge["source_trigger_id"] == new_trigger["id"]
      assert new_edge["target_job_id"] == new_job["id"]
      refute new_edge["delete"]
    end

    test "merge project with removed workflow in source" do
      # Create projects
      target_project = insert(:project, name: "Target Project")
      source_project = insert(:project, name: "Source Project")

      # Target project with two workflows
      target_workflow1 =
        insert(:workflow, name: "workflow_to_keep", project: target_project)

      target_workflow2 =
        insert(:workflow, name: "workflow_to_remove", project: target_project)

      # Source project with only one workflow (removed one)
      _source_workflow =
        insert(:workflow, name: "workflow_to_keep", project: source_project)

      result = MergeProjects.merge_project(source_project, target_project)

      # Should have two workflows (kept + deleted)
      assert length(result["workflows"]) == 2

      kept_workflow =
        Enum.find(result["workflows"], &(&1["name"] == "workflow_to_keep"))

      assert kept_workflow["id"] == target_workflow1.id
      refute kept_workflow["delete"]

      # Removed workflow should be marked for deletion
      deleted_workflow =
        Enum.find(result["workflows"], &(&1["id"] == target_workflow2.id))

      assert deleted_workflow["delete"]
    end

    test "merge project with no matching workflows" do
      # Create projects
      target_project = insert(:project, name: "Target Project")
      source_project = insert(:project, name: "Source Project")

      # Target project with one workflow
      target_workflow =
        insert(:workflow, name: "target_workflow", project: target_project)

      # Source project with completely different workflow
      source_workflow =
        insert(:workflow, name: "source_workflow", project: source_project)

      result = MergeProjects.merge_project(source_project, target_project)

      # Should have two workflows
      assert length(result["workflows"]) == 2

      # Source workflow should get new UUID
      new_workflow =
        Enum.find(result["workflows"], &(&1["name"] == "source_workflow"))

      assert new_workflow["id"] != source_workflow.id
      refute new_workflow["delete"]

      # Target workflow should be marked for deletion
      deleted_workflow =
        Enum.find(result["workflows"], &(&1["id"] == target_workflow.id))

      assert deleted_workflow["delete"]
    end

    test "merge empty projects" do
      target_project = insert(:project, name: "Target Project")
      source_project = insert(:project, name: "Source Project")

      result = MergeProjects.merge_project(source_project, target_project)

      # Should preserve target identity
      assert result["id"] == target_project.id
      assert result["name"] == target_project.name
      assert result["description"] == target_project.description
      assert result["env"] == target_project.env
      assert result["color"] == target_project.color
      assert result["workflows"] == []
    end

    test "merge project with workflow containing jobs - integration test" do
      # Test that workflow merging logic works correctly within project merging

      # Create projects
      target_project = insert(:project, name: "Target Project")
      source_project = insert(:project, name: "Source Project")

      # Target project with workflow containing a job
      {target_workflow,
       %{:webhook => target_trigger, "process_data" => target_job}} =
        generate_workflow([{:webhook, "process_data"}], %{
          :workflow => %{name: "data_processing", project: target_project},
          "process_data" => %{
            body: "fn(s => s)",
            adaptor: "@openfn/language-common@latest"
          }
        })

      # Source project with same workflow name but different job adaptor
      {source_workflow, %{"process_data" => source_job}} =
        generate_workflow([{:webhook, "process_data"}], %{
          :workflow => %{name: "data_processing", project: source_project},
          "process_data" => %{
            body: "fn(s => s)",
            adaptor: "@openfn/language-http@latest"
          }
        })

      result = MergeProjects.merge_project(source_project, target_project)

      # Should have one workflow (merged)
      assert length(result["workflows"]) == 1
      workflow = hd(result["workflows"])

      # Workflow should preserve target ID
      assert workflow["id"] == target_workflow.id
      assert workflow["name"] == source_workflow.name

      # Should have one job with updated adaptor but preserved UUID
      job = hd(workflow["jobs"])
      assert job["id"] == target_job.id
      assert job["name"] == source_job.name
      # Source adaptor used
      assert job["adaptor"] == source_job.adaptor
      refute job["delete"]

      # Should have one trigger with preserved UUID
      trigger = hd(workflow["triggers"])
      assert trigger["id"] == target_trigger.id
      refute trigger["delete"]

      # Should have one edge with preserved UUID
      edge = hd(workflow["edges"])
      target_edge = hd(target_workflow.edges)
      assert edge["id"] == target_edge.id
      refute edge["delete"]
    end
  end

  describe "merge_workflow/2 - ported from cli" do
    test "no changes: single node workflow" do
      # Both source and target have identical single trigger
      {source, _source_elements} = generate_workflow([:webhook])

      {target, _target_elements} = generate_workflow([:webhook])

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
      {source, _source_elements} = generate_workflow([{:webhook, "a"}])

      {target, %{:webhook => target_trigger, "a" => target_job_a}} =
        generate_workflow([{:webhook, "a"}])

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

      # Source workflow using generate_workflow helper
      {source, _source_elements} =
        generate_workflow([
          {:webhook, "a"},
          {:webhook, "b"},
          {"a", "c"},
          {"a", "d"},
          {"b", "d"},
          {"b", "e"},
          {"c", "f"},
          {"e", "g"}
        ])

      # Target workflow with identical structure
      {target,
       %{
         :webhook => target_trigger,
         "a" => target_job_a,
         "b" => target_job_b,
         "c" => target_job_c,
         "d" => target_job_d,
         "e" => target_job_e,
         "f" => target_job_f,
         "g" => target_job_g
       }} =
        generate_workflow([
          {:webhook, "a"},
          {:webhook, "b"},
          {"a", "c"},
          {"a", "d"},
          {"b", "d"},
          {"b", "e"},
          {"c", "f"},
          {"e", "g"}
        ])

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

      # Verify specific edge mappings exist and IDs haven't changed
      result_webhook_a = find_edge_by_names(result, "webhook", "a")
      target_webhook_a = find_edge_by_names(target, "webhook", "a")
      assert result_webhook_a
      assert result_webhook_a["id"] == target_webhook_a["id"]

      result_webhook_b = find_edge_by_names(result, "webhook", "b")
      target_webhook_b = find_edge_by_names(target, "webhook", "b")
      assert result_webhook_b
      assert result_webhook_b["id"] == target_webhook_b["id"]

      result_a_c = find_edge_by_names(result, "a", "c")
      target_a_c = find_edge_by_names(target, "a", "c")
      assert result_a_c
      assert result_a_c["id"] == target_a_c["id"]

      result_a_d = find_edge_by_names(result, "a", "d")
      target_a_d = find_edge_by_names(target, "a", "d")
      assert result_a_d
      assert result_a_d["id"] == target_a_d["id"]

      result_b_d = find_edge_by_names(result, "b", "d")
      target_b_d = find_edge_by_names(target, "b", "d")
      assert result_b_d
      assert result_b_d["id"] == target_b_d["id"]

      result_b_e = find_edge_by_names(result, "b", "e")
      target_b_e = find_edge_by_names(target, "b", "e")
      assert result_b_e
      assert result_b_e["id"] == target_b_e["id"]

      result_c_f = find_edge_by_names(result, "c", "f")
      target_c_f = find_edge_by_names(target, "c", "f")
      assert result_c_f
      assert result_c_f["id"] == target_c_f["id"]

      result_e_g = find_edge_by_names(result, "e", "g")
      target_e_g = find_edge_by_names(target, "e", "g")
      assert result_e_g
      assert result_e_g["id"] == target_e_g["id"]
    end

    test "id change: single node" do
      # Source has trigger only, target has trigger only but different trigger type
      # This tests the case where triggers are mapped by type
      {source, _source_elements} = generate_workflow([:webhook])

      {target, _target_elements} =
        generate_workflow([:cron], %{:cron => %{cron_expression: "0 * * * *"}})

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

      # Source workflow using generate_workflow helper
      {source, _source_elements} =
        generate_workflow([{:webhook, "a"}, {:webhook, "b"}])

      # Target workflow using generate_workflow helper
      {target, %{:webhook => target_trigger}} =
        generate_workflow([{:webhook, "x"}, {:webhook, "y"}])

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

      # Verify edges exist and IDs are preserved from target
      result_webhook_a = find_edge_by_names(result, "webhook", "a")
      result_webhook_b = find_edge_by_names(result, "webhook", "b")
      assert result_webhook_a
      assert result_webhook_b

      # Since source has same structure, edges should map to target edges
      target_webhook_x = find_edge_by_names(target, "webhook", "x")
      target_webhook_y = find_edge_by_names(target, "webhook", "y")

      # Edges should preserve target IDs (mapped in structural order)
      assert result_webhook_a["id"] == target_webhook_x["id"]
      assert result_webhook_b["id"] == target_webhook_y["id"]

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end
    end

    test "id change: internal node" do
      # Source: trigger->a, a->b
      # Target: trigger->x, x->b
      # Should map a->x based on structural similarity (same parent and child)

      # Source workflow using generate_workflow helper
      {source, _source_elements} =
        generate_workflow([{:webhook, "a"}, {"a", "b"}])

      # Target workflow using generate_workflow helper
      {target,
       %{:webhook => target_trigger, "x" => target_job_x, "b" => target_job_b}} =
        generate_workflow([{:webhook, "x"}, {"x", "b"}])

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
      result_webhook_a = find_edge_by_names(result, "webhook", "a")
      target_webhook_x = find_edge_by_names(target, "webhook", "x")
      assert result_webhook_a
      assert result_webhook_a["id"] == target_webhook_x["id"]

      # a->b
      result_a_b = find_edge_by_names(result, "a", "b")
      target_x_b = find_edge_by_names(target, "x", "b")
      assert result_a_b
      assert result_a_b["id"] == target_x_b["id"]

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end
    end

    test "id change: internal nodes(same parent and child)" do
      # Source: trigger->a, trigger->b, a->c, b->c
      # Target: trigger->x, trigger->y, x->c, y->c
      # Should map a->x, b->y based on structural similarity

      # Source workflow using generate_workflow helper
      {source, _source_elements} =
        generate_workflow([
          {:webhook, "a"},
          {:webhook, "b"},
          {"a", "c"},
          {"b", "c"}
        ])

      # Target workflow using generate_workflow helper
      {target,
       %{
         :webhook => target_trigger,
         "x" => target_job_x,
         "y" => target_job_y,
         "c" => target_job_c
       }} =
        generate_workflow([
          {:webhook, "x"},
          {:webhook, "y"},
          {"x", "c"},
          {"y", "c"}
        ])

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

      # Get target edges for comparison
      target_webhook_x = find_edge_by_names(target, "webhook", "x")
      target_webhook_y = find_edge_by_names(target, "webhook", "y")
      target_x_c = find_edge_by_names(target, "x", "c")
      target_y_c = find_edge_by_names(target, "y", "c")

      # trigger->a (maps to webhook->x)
      result_webhook_a = find_edge_by_names(result, "webhook", "a")
      assert result_webhook_a
      assert result_webhook_a["id"] == target_webhook_x["id"]

      # trigger->b (maps to webhook->y)
      result_webhook_b = find_edge_by_names(result, "webhook", "b")
      assert result_webhook_b
      assert result_webhook_b["id"] == target_webhook_y["id"]

      # a->c (maps to x->c)
      result_a_c = find_edge_by_names(result, "a", "c")
      assert result_a_c
      assert result_a_c["id"] == target_x_c["id"]

      # b->c (maps to y->c)
      result_b_c = find_edge_by_names(result, "b", "c")
      assert result_b_c
      assert result_b_c["id"] == target_y_c["id"]

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end
    end

    test "id change: several internal nodes (mid-size workflow)" do
      # Source: trigger->a, trigger->b, a->c, b->d, c->e, d->f, e->g, f->g
      # Target: trigger->a1, trigger->b1, a1->x, b1->y, x->e, y->f, e->z, f->z
      # Should map: a->a1, b->b1, c->x, d->y, e->e, f->f, g->z

      # Source workflow using generate_workflow helper
      {source, _source_elements} =
        generate_workflow([
          {:webhook, "a"},
          {:webhook, "b"},
          {"a", "c"},
          {"b", "d"},
          {"c", "e"},
          {"d", "f"},
          {"e", "g"},
          {"f", "g"}
        ])

      # Target workflow using generate_workflow helper
      {target,
       %{
         :webhook => target_trigger,
         "a1" => target_job_a1,
         "b1" => target_job_b1,
         "x" => target_job_x,
         "y" => target_job_y,
         "e" => target_job_e,
         "f" => target_job_f,
         "z" => target_job_z
       }} =
        generate_workflow([
          {:webhook, "a1"},
          {:webhook, "b1"},
          {"a1", "x"},
          {"b1", "y"},
          {"x", "e"},
          {"y", "f"},
          {"e", "z"},
          {"f", "z"}
        ])

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

      # Verify edges exist and IDs are preserved from target
      # Mapping: a->a1, b->b1, c->x, d->y, e->e, f->f, g->z
      # trigger->a (source) maps to webhook->a1 (target)
      result_webhook_a = find_edge_by_names(result, "webhook", "a")
      target_webhook_a1 = find_edge_by_names(target, "webhook", "a1")
      assert result_webhook_a
      assert result_webhook_a["id"] == target_webhook_a1["id"]

      # trigger->b (source) maps to webhook->b1 (target)
      result_webhook_b = find_edge_by_names(result, "webhook", "b")
      target_webhook_b1 = find_edge_by_names(target, "webhook", "b1")
      assert result_webhook_b
      assert result_webhook_b["id"] == target_webhook_b1["id"]

      # a->c (source) maps to a1->x (target)
      result_a_c = find_edge_by_names(result, "a", "c")
      target_a1_x = find_edge_by_names(target, "a1", "x")
      assert result_a_c
      assert result_a_c["id"] == target_a1_x["id"]

      # b->d (source) maps to b1->y (target)
      result_b_d = find_edge_by_names(result, "b", "d")
      target_b1_y = find_edge_by_names(target, "b1", "y")
      assert result_b_d
      assert result_b_d["id"] == target_b1_y["id"]

      # c->e (source) maps to x->e (target)
      result_c_e = find_edge_by_names(result, "c", "e")
      target_x_e = find_edge_by_names(target, "x", "e")
      assert result_c_e
      assert result_c_e["id"] == target_x_e["id"]

      # d->f (source) maps to y->f (target)
      result_d_f = find_edge_by_names(result, "d", "f")
      target_y_f = find_edge_by_names(target, "y", "f")
      assert result_d_f
      assert result_d_f["id"] == target_y_f["id"]

      # e->g (source) maps to e->z (target)
      result_e_g = find_edge_by_names(result, "e", "g")
      target_e_z = find_edge_by_names(target, "e", "z")
      assert result_e_g
      assert result_e_g["id"] == target_e_z["id"]

      # f->g (source) maps to f->z (target)
      result_f_g = find_edge_by_names(result, "f", "g")
      target_f_z = find_edge_by_names(target, "f", "z")
      assert result_f_g
      assert result_f_g["id"] == target_f_z["id"]

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end
    end

    test "id change: several internal nodes (mid-size workflow) 2" do
      # Source: trigger->a, trigger->b, a->c, a->d, b->e, b->f, d->g, e->g
      # Target: trigger->x, trigger->y, x->c, x->m, y->n, y->f, m->g, n->g
      # Should map: a->x, b->y, c->c, d->m, e->n, f->f, g->g

      # Source workflow using generate_workflow helper
      {source, _source_elements} =
        generate_workflow([
          {:webhook, "a"},
          {:webhook, "b"},
          {"a", "c"},
          {"a", "d"},
          {"b", "e"},
          {"b", "f"},
          {"d", "g"},
          {"e", "g"}
        ])

      # Target workflow using generate_workflow helper
      {target,
       %{
         :webhook => target_trigger,
         "c" => target_job_c,
         "f" => target_job_f,
         "g" => target_job_g,
         "x" => target_job_x,
         "y" => target_job_y,
         "m" => target_job_m,
         "n" => target_job_n
       }} =
        generate_workflow([
          {:webhook, "x"},
          {:webhook, "y"},
          {"x", "c"},
          {"x", "m"},
          {"y", "n"},
          {"y", "f"},
          {"m", "g"},
          {"n", "g"}
        ])

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

      # Verify edges exist and IDs are preserved from target
      # Mapping: a->x, b->y, c->c, d->m, e->n, f->f, g->g
      # trigger->a (source) maps to webhook->x (target)
      result_webhook_a = find_edge_by_names(result, "webhook", "a")
      target_webhook_x = find_edge_by_names(target, "webhook", "x")
      assert result_webhook_a
      assert result_webhook_a["id"] == target_webhook_x["id"]

      # trigger->b (source) maps to webhook->y (target)
      result_webhook_b = find_edge_by_names(result, "webhook", "b")
      target_webhook_y = find_edge_by_names(target, "webhook", "y")
      assert result_webhook_b
      assert result_webhook_b["id"] == target_webhook_y["id"]

      # a->c (source) maps to x->c (target)
      result_a_c = find_edge_by_names(result, "a", "c")
      target_x_c = find_edge_by_names(target, "x", "c")
      assert result_a_c
      assert result_a_c["id"] == target_x_c["id"]

      # a->d (source) maps to x->m (target)
      result_a_d = find_edge_by_names(result, "a", "d")
      target_x_m = find_edge_by_names(target, "x", "m")
      assert result_a_d
      assert result_a_d["id"] == target_x_m["id"]

      # b->e (source) maps to y->n (target)
      result_b_e = find_edge_by_names(result, "b", "e")
      target_y_n = find_edge_by_names(target, "y", "n")
      assert result_b_e
      assert result_b_e["id"] == target_y_n["id"]

      # b->f (source) maps to y->f (target)
      result_b_f = find_edge_by_names(result, "b", "f")
      target_y_f = find_edge_by_names(target, "y", "f")
      assert result_b_f
      assert result_b_f["id"] == target_y_f["id"]

      # d->g (source) maps to m->g (target)
      result_d_g = find_edge_by_names(result, "d", "g")
      target_m_g = find_edge_by_names(target, "m", "g")
      assert result_d_g
      assert result_d_g["id"] == target_m_g["id"]

      # e->g (source) maps to n->g (target)
      result_e_g = find_edge_by_names(result, "e", "g")
      target_n_g = find_edge_by_names(target, "n", "g")
      assert result_e_g
      assert result_e_g["id"] == target_n_g["id"]

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end
    end

    test "id change: chained internal nodes" do
      # Source: trigger->a, a->b, b->c, b->d
      # Target: trigger->x, x->y, y->z, y->q
      # Special case: node 'b' has both parent and children changed
      # Should map: a->x, b->y, c->z, d->q
      # because we dont know which node is on the left or right, c and d can map to either z or q

      # Source workflow using generate_workflow helper
      {source, _source_elements} =
        generate_workflow([{:webhook, "a"}, {"a", "b"}, {"b", "c"}, {"b", "d"}])

      # Target workflow using generate_workflow helper
      {target,
       %{
         :webhook => target_trigger,
         "x" => target_job_x,
         "y" => target_job_y,
         "z" => target_job_z,
         "q" => target_job_q
       }} =
        generate_workflow([{:webhook, "x"}, {"x", "y"}, {"y", "z"}, {"y", "q"}])

      result = MergeProjects.merge_workflow(source, target)

      # Check trigger mapping
      result_trigger = hd(result["triggers"])
      assert result_trigger["id"] == target_trigger.id
      refute result_trigger["delete"]

      assert length(result["jobs"]) == 4

      result_job_a = Enum.find(result["jobs"], &(&1["name"] == "a"))
      assert result_job_a["id"] == target_job_x.id
      refute result_job_a["delete"]

      result_job_b = Enum.find(result["jobs"], &(&1["name"] == "b"))
      assert result_job_b["id"] == target_job_y.id
      refute result_job_b["delete"]

      # Check variable mappings for c and d
      result_job_c = Enum.find(result["jobs"], &(&1["name"] == "c"))
      result_job_d = Enum.find(result["jobs"], &(&1["name"] == "d"))

      refute result_job_c["id"] == result_job_d["id"]
      assert result_job_c["id"] in [target_job_z.id, target_job_q.id]
      assert result_job_d["id"] in [target_job_z.id, target_job_q.id]

      refute result_job_c["delete"]
      refute result_job_d["delete"]

      # Check edge mappings - should have 4 edges
      assert length(result["edges"]) == 4

      # Verify edges exist and IDs are preserved from target
      # trigger->a (maps to webhook->x)
      result_webhook_a = find_edge_by_names(result, "webhook", "a")
      target_webhook_x = find_edge_by_names(target, "webhook", "x")
      assert result_webhook_a
      assert result_webhook_a["id"] == target_webhook_x["id"]

      # a->b (maps to x->y)
      result_a_b = find_edge_by_names(result, "a", "b")
      target_x_y = find_edge_by_names(target, "x", "y")
      assert result_a_b
      assert result_a_b["id"] == target_x_y["id"]

      # b->c and b->d edges
      # The edge IDs depend on which job c and d map to
      result_b_c = find_edge_by_names(result, "b", "c")
      result_b_d = find_edge_by_names(result, "b", "d")
      target_y_z = find_edge_by_names(target, "y", "z")
      target_y_q = find_edge_by_names(target, "y", "q")

      assert result_b_c
      assert result_b_d

      # If c maps to z, then b->c should map to y->z
      # If c maps to q, then b->c should map to y->q
      if result_job_c["id"] == target_job_z.id do
        assert result_b_c["id"] == target_y_z["id"],
               "Edge b->c should map to y->z when c maps to z"

        assert result_b_d["id"] == target_y_q["id"],
               "Edge b->d should map to y->q when c maps to z"
      else
        assert result_job_c["id"] == target_job_q.id,
               "c should map to q if not z"

        assert result_b_c["id"] == target_y_q["id"],
               "Edge b->c should map to y->q when c maps to q"

        assert result_b_d["id"] == target_y_z["id"],
               "Edge b->d should map to y->z when c maps to q"
      end

      for result_edge <- result["edges"] do
        refute result_edge["delete"]
      end
    end

    test "node removal: single node" do
      # Source: empty workflow (just trigger)
      # Target: trigger with one job
      # Should result in empty mapping, target job should be marked for deletion

      # Source workflow - just a trigger
      {source, _source_elements} = generate_workflow([:webhook])

      # Target workflow - trigger with a job
      {target, %{:webhook => target_trigger, "removed_job" => target_job}} =
        generate_workflow([{:webhook, "removed_job"}])

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
      {source, _source_elements} = generate_workflow([:webhook])

      # Target workflow - trigger with leaf job
      {target, %{:webhook => target_trigger, "a" => target_job_a}} =
        generate_workflow([{:webhook, "a"}])

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
      {source, _source_elements} = generate_workflow([:webhook])

      # Target workflow - trigger with two leaf jobs
      {target, %{:webhook => target_trigger}} =
        generate_workflow([{:webhook, "a"}, {:webhook, "b"}])

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
      {source, _source_elements} =
        generate_workflow([{:webhook, "a"}, {:webhook, "b"}])

      # Target workflow - same structure plus additional leaf jobs
      {target,
       %{
         :webhook => target_trigger,
         "a" => target_job_a,
         "b" => target_job_b,
         "c" => target_job_c,
         "d" => target_job_d
       }} =
        generate_workflow([
          {:webhook, "a"},
          {:webhook, "b"},
          {"a", "c"},
          {"b", "d"}
        ])

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

      # Edges trigger->a and trigger->b should be preserved with their IDs
      result_webhook_a = find_edge_by_names(result, "webhook", "a")
      result_webhook_b = find_edge_by_names(result, "webhook", "b")
      assert result_webhook_a
      assert result_webhook_b

      # Verify edge IDs are preserved from target
      target_webhook_a = find_edge_by_names(target, "webhook", "a")
      target_webhook_b = find_edge_by_names(target, "webhook", "b")
      assert result_webhook_a["id"] == target_webhook_a["id"]
      assert result_webhook_b["id"] == target_webhook_b["id"]

      # Edges a->c and b->d should be marked for deletion
      deleted_edges = Enum.filter(result["edges"], & &1["delete"])
      assert length(deleted_edges) == 2
    end

    test "node removal: single node (different parents)" do
      # Source: trigger->a, trigger->b (two separate jobs from trigger)
      # Target: trigger->a, trigger->b, a->c, b->c (job 'c' has two different parents: 'a' and 'b')
      # Job 'c' should be marked for deletion along with its edges

      # Source workflow - trigger with two separate jobs
      {source, _source_elements} =
        generate_workflow([{:webhook, "a"}, {:webhook, "b"}])

      # Target workflow - same base structure plus job 'c' with edges from both 'a' and 'b'
      {target,
       %{
         :webhook => target_trigger,
         "a" => target_job_a,
         "b" => target_job_b,
         "c" => target_job_c
       }} =
        generate_workflow([
          {:webhook, "a"},
          {:webhook, "b"},
          {"a", "c"},
          {"b", "c"}
        ])

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
      {source, _source_elements} = generate_workflow([{:webhook, "b"}])

      # Target workflow - trigger to a, a to b (a is internal node)
      {target,
       %{:webhook => target_trigger, "a" => target_job_a, "b" => target_job_b}} =
        generate_workflow([{:webhook, "a"}, {"a", "b"}])

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
      {source, _source_elements} = generate_workflow([{:webhook, "a"}])

      # Target workflow - trigger to a, a to b (b is additional leaf)
      {target,
       %{:webhook => target_trigger, "a" => target_job_a, "b" => target_job_b}} =
        generate_workflow([{:webhook, "a"}, {"a", "b"}])

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
      {source, _source_elements} =
        generate_workflow([{:webhook, "a"}, {"a", "b"}])

      # Target workflow - same chain plus branching from a to c to d
      {target,
       %{
         :webhook => target_trigger,
         "a" => target_job_a,
         "b" => target_job_b,
         "c" => target_job_c,
         "d" => target_job_d
       }} =
        generate_workflow([
          {:webhook, "a"},
          {"a", "b"},
          {"a", "c"},
          {"c", "d"}
        ])

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
      {source, _source_elements} =
        generate_workflow([{:webhook, "a"}, {"a", "b"}])

      # Target workflow - both a and b connected to trigger
      {target,
       %{:webhook => target_trigger, "a" => target_job_a, "b" => target_job_b}} =
        generate_workflow([{:webhook, "a"}, {:webhook, "b"}])

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
      {source, _source_elements} = generate_workflow([{:webhook, "a"}])

      # Target workflow - trigger->x, x->b (a renamed to x, plus leaf b)
      {target,
       %{:webhook => target_trigger, "x" => target_job_x, "b" => target_job_b}} =
        generate_workflow([{:webhook, "x"}, {"x", "b"}])

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
      {source, _source_elements} =
        generate_workflow([
          {:webhook, "m"},
          {"m", "n"},
          {"m", "o"},
          {"o", "d"},
          {"o", "e"}
        ])

      # Target workflow - a has children b,c; b has children d,e
      {target,
       %{
         :webhook => target_trigger,
         "a" => target_job_a,
         "b" => target_job_b,
         "c" => target_job_c,
         "d" => target_job_d,
         "e" => target_job_e
       }} =
        generate_workflow([
          {:webhook, "a"},
          {"a", "b"},
          {"a", "c"},
          {"b", "d"},
          {"b", "e"}
        ])

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
      {source, _source_elements} =
        generate_workflow(
          [{:webhook, "x"}, {:webhook, "y"}],
          %{jobs: %{"x" => %{body: "foo"}, "y" => %{body: "bar"}}}
        )

      # Target workflow - two jobs with matching expressions
      {target,
       %{:webhook => target_trigger, "a" => target_job_a, "b" => target_job_b}} =
        generate_workflow(
          [{:webhook, "a"}, {:webhook, "b"}],
          %{jobs: %{"a" => %{body: "foo"}, "b" => %{body: "bar"}}}
        )

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

  describe "merge_workflow/2 - merge attributes" do
    test "maps workflow-level attributes from source" do
      # source workflow attributes (name, concurrency, enable_job_logs) are used
      {source, _source_elements} =
        generate_workflow(
          [{:webhook, "test_job"}],
          %{
            workflow: %{
              name: "Source Workflow",
              concurrency: 5,
              enable_job_logs: true
            }
          }
        )

      {target, _target_elements} =
        generate_workflow(
          [{:webhook, "test_job"}],
          %{
            workflow: %{
              name: "Target Workflow",
              concurrency: 10,
              enable_job_logs: false
            }
          }
        )

      result = MergeProjects.merge_workflow(source, target)

      # Should preserve target ID but use source attributes
      assert result["id"] == target.id
      assert result["name"] == source.name
      assert result["concurrency"] == source.concurrency
      assert result["enable_job_logs"] == source.enable_job_logs
    end

    test "maps job attributes from source" do
      #  (name, body, adaptor, credentials) are used from source
      {source, _source_elements} =
        generate_workflow(
          [
            {:webhook, "process_data"}
          ],
          %{
            jobs: %{
              "process_data" => %{
                body: "fn(state => ({ ...state, processed: true }))",
                adaptor: "@openfn/language-http@latest"
              }
            }
          }
        )

      {target, %{"process_data" => target_job}} =
        generate_workflow(
          [
            {:webhook, "process_data"}
          ],
          %{
            jobs: %{
              "process_data" => %{
                body: "fn(state => state)",
                adaptor: "@openfn/language-common@latest"
              }
            }
          }
        )

      result = MergeProjects.merge_workflow(source, target)

      result_job = hd(result["jobs"])
      source_job = hd(source.jobs)
      # Should preserve target ID but use source attributes
      assert result_job["id"] == target_job.id
      assert result_job["name"] == source_job.name
      assert result_job["body"] == source_job.body
      assert result_job["adaptor"] == source_job.adaptor
    end

    test "maps trigger attributes from source" do
      {source, _source_elements} =
        generate_workflow([:cron], %{
          :cron => %{cron_expression: "0 */2 * * *", comment: "Every 2 hours"}
        })

      {target, %{:webhook => target_trigger}} =
        generate_workflow([:webhook], %{})

      result = MergeProjects.merge_workflow(source, target)

      result_trigger = hd(result["triggers"])
      source_trigger = hd(source.triggers)
      # Should preserve target ID but use source attributes
      assert result_trigger["id"] == target_trigger.id
      assert result_trigger["type"] == source_trigger.type
      assert result_trigger["cron_expression"] == source_trigger.cron_expression
      assert result_trigger["comment"] == source_trigger.comment
    end

    test "maps edge attributes from source" do
      # Test that edge attributes (condition_type, condition_expression, etc.) are used from source
      {source, _source_elements} =
        generate_workflow([{:webhook, "test_job"}], %{
          {:webhook, "test_job"} => %{
            condition_type: :js_expression,
            condition_expression: "state.shouldProcess",
            condition_label: "Process if flag is set",
            enabled: false
          }
        })

      {target, _target_elements} =
        generate_workflow([{:webhook, "test_job"}], %{
          {:webhook, "test_job"} => %{
            condition_type: :always,
            condition_expression: nil,
            condition_label: nil,
            enabled: true
          }
        })

      result = MergeProjects.merge_workflow(source, target)

      result_edge = hd(result["edges"])
      target_edge = hd(target.edges)
      source_edge = hd(source.edges)

      # Should preserve target ID but use source attributes
      assert result_edge["id"] == target_edge.id
      assert result_edge["condition_type"] == source_edge.condition_type

      assert result_edge["condition_expression"] ==
               source_edge.condition_expression

      assert result_edge["condition_label"] == source_edge.condition_label
      assert result_edge["enabled"] == source_edge.enabled
    end

    test "maps workflow positions correctly" do
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "job_a")
      source_job_b = build(:job, name: "job_b")

      # Source has specific positions
      source_positions = %{
        source_trigger.id => %{"x" => 100, "y" => 200},
        source_job_a.id => %{"x" => 300, "y" => 400},
        source_job_b.id => %{"x" => 500, "y" => 600}
      }

      source =
        build(:workflow, positions: source_positions)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_job(source_job_b)
        |> with_edge({source_trigger, source_job_a})
        |> with_edge({source_job_a, source_job_b})
        |> insert()

      target_trigger = build(:trigger, type: :webhook)
      target_job_a = build(:job, name: "job_a")
      target_job_b = build(:job, name: "job_b")

      # Target has different positions
      target_positions = %{
        target_trigger.id => %{"x" => 0, "y" => 0},
        target_job_a.id => %{"x" => 0, "y" => 0},
        target_job_b.id => %{"x" => 0, "y" => 0}
      }

      target =
        build(:workflow, positions: target_positions)
        |> with_trigger(target_trigger)
        |> with_job(target_job_a)
        |> with_job(target_job_b)
        |> with_edge({target_trigger, target_job_a})
        |> with_edge({target_job_a, target_job_b})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Positions should be from source but with target IDs
      expected_positions = %{
        target_trigger.id => %{"x" => 100, "y" => 200},
        target_job_a.id => %{"x" => 300, "y" => 400},
        target_job_b.id => %{"x" => 500, "y" => 600}
      }

      assert result["positions"] == expected_positions
    end

    test "handles missing positions gracefully" do
      # Test when source has no positions defined
      source_trigger = build(:trigger, type: :webhook)
      source_job = build(:job, name: "test_job")

      source =
        build(:workflow, positions: nil)
        |> with_trigger(source_trigger)
        |> with_job(source_job)
        |> with_edge({source_trigger, source_job})
        |> insert()

      target_trigger = build(:trigger, type: :webhook)
      target_job = build(:job, name: "test_job")

      target =
        build(:workflow,
          positions: %{target_job.id => %{"x" => 100, "y" => 200}}
        )
        |> with_trigger(target_trigger)
        |> with_job(target_job)
        |> with_edge({target_trigger, target_job})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Should result in empty positions
      assert result["positions"] == %{}
    end

    test "maps positions for renamed jobs correctly" do
      source_trigger = build(:trigger, type: :webhook)
      source_job_a = build(:job, name: "source_job")

      source_positions = %{
        source_job_a.id => %{"x" => 100, "y" => 200}
      }

      source =
        build(:workflow, positions: source_positions)
        |> with_trigger(source_trigger)
        |> with_job(source_job_a)
        |> with_edge({source_trigger, source_job_a})
        |> insert()

      target_trigger = build(:trigger, type: :webhook)
      target_job_x = build(:job, name: "target_job")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job_x)
        |> with_edge({target_trigger, target_job_x})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Position should be mapped to target job ID but preserve source coordinates
      expected_positions = %{
        target_job_x.id => %{"x" => 100, "y" => 200}
      }

      assert result["positions"] == expected_positions
    end

    test "preserves webhook trigger custom_path" do
      {source, _source_elements} =
        generate_workflow([:webhook], %{
          triggers: %{
            :webhook => %{custom_path: "/custom/webhook/path"}
          }
        })

      {target, _target_elements} =
        generate_workflow([:webhook], %{
          triggers: %{
            :webhook => %{custom_path: "/different/path"}
          }
        })

      result = MergeProjects.merge_workflow(source, target)

      result_trigger = hd(result["triggers"])
      source_trigger = hd(source.triggers)
      assert result_trigger["custom_path"] == source_trigger.custom_path
    end

    test "preserves kafka trigger configuration" do
      # Test that kafka trigger configuration is preserved from source
      source_kafka_config = %{
        "hosts" => ["localhost:9092"],
        "topic" => "source_topic",
        "partition" => 0
      }

      source_trigger =
        build(:trigger,
          type: :kafka,
          kafka_configuration: source_kafka_config
        )

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> insert()

      target_kafka_config = %{
        "hosts" => ["different:9092"],
        "topic" => "target_topic",
        "partition" => 1
      }

      target_trigger =
        build(:trigger,
          type: :kafka,
          kafka_configuration: target_kafka_config
        )

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      result_trigger = hd(result["triggers"])
      # Kafka configuration should contain the source values (as a struct)
      kafka_config = result_trigger["kafka_configuration"]

      # The kafka_configuration appears to be a mix of struct fields and map values
      # Check that the source values are preserved in the map part
      assert Map.get(kafka_config, "hosts") == source_kafka_config["hosts"]
      assert Map.get(kafka_config, "topic") == source_kafka_config["topic"]

      assert Map.get(kafka_config, "partition") ==
               source_kafka_config["partition"]
    end

    test "preserves attributes with multiple triggers feeding same job" do
      # Source workflow - cron trigger only
      {source, %{:cron => source_cron_trigger, "process_data" => source_job}} =
        generate_workflow(
          [
            {:cron, "process_data"}
          ],
          %{
            triggers: %{
              :cron => %{
                cron_expression: "0 */6 * * *",
                comment: "Every 6 hours"
              }
            },
            jobs: %{
              "process_data" => %{
                body: "fn(state => ({ ...state, processed: true }))",
                adaptor: "@openfn/language-http@latest"
              }
            }
          }
        )

      # Target workflow - webhook + cron triggers with different attributes
      {target,
       %{
         :webhook => target_webhook_trigger,
         :cron => target_cron_trigger,
         "process_data" => target_job
       }} =
        generate_workflow(
          [
            {:webhook, "process_data"},
            {:cron, "process_data"}
          ],
          %{
            triggers: %{
              :webhook => %{custom_path: "/target/webhook"},
              :cron => %{
                cron_expression: "0 * * * *",
                comment: "Every hour"
              }
            },
            jobs: %{
              "process_data" => %{
                body: "fn(state => state)",
                adaptor: "@openfn/language-common@latest"
              }
            }
          }
        )

      result = MergeProjects.merge_workflow(source, target)

      assert result["id"] == target.id

      assert length(result["triggers"]) == 2

      # Cron trigger should preserve target ID but use source attributes
      result_cron_trigger = Enum.find(result["triggers"], &(&1["type"] == :cron))

      assert result_cron_trigger["id"] == target_cron_trigger.id

      assert result_cron_trigger["cron_expression"] ==
               source_cron_trigger.cron_expression

      assert result_cron_trigger["comment"] == source_cron_trigger.comment
      refute result_cron_trigger["delete"]

      # Webhook trigger is deleted
      [result_webhook_trigger] = result["triggers"] -- [result_cron_trigger]
      assert result_webhook_trigger["id"] == target_webhook_trigger.id
      assert result_webhook_trigger["delete"]

      # Should have 1 job with source attributes but target ID
      assert length(result["jobs"]) == 1
      result_job = hd(result["jobs"])

      assert result_job["id"] == target_job.id
      assert result_job["name"] == source_job.name
      assert result_job["body"] == source_job.body
      assert result_job["adaptor"] == source_job.adaptor
      refute result_job["delete"]

      assert length(result["edges"]) == 2

      cron_edge =
        Enum.find(
          result["edges"],
          &(&1["source_trigger_id"] == target_cron_trigger.id)
        )

      [webhook_edge] = result["edges"] -- [cron_edge]

      assert webhook_edge["delete"], "webhook edge is deleted"

      assert cron_edge["target_job_id"] == target_job.id
      refute cron_edge["delete"]
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

  # Helper function to generate a workflow from a sequence specification.
  # Takes a list of tuples representing the workflow structure and optional attributes.
  defp generate_workflow(sequence, opts \\ %{}) do
    # Extract workflow options and build initial workflow
    workflow_opts = Map.get(opts, :workflow, %{})
    workflow = build(:workflow, workflow_opts)

    # Parse sequence to extract unique triggers and jobs
    {triggers, jobs, edges} = parse_sequence(sequence)

    # Create triggers
    {workflow, trigger_elements} = add_triggers(workflow, triggers, opts)

    # Create jobs
    {workflow, job_elements} = add_jobs(workflow, jobs, opts)

    # Create edges
    workflow =
      add_edges(workflow, edges, Map.merge(trigger_elements, job_elements), opts)

    # Insert the workflow
    inserted_workflow = insert(workflow)

    {inserted_workflow, Map.merge(trigger_elements, job_elements)}
  end

  defp parse_sequence(sequence) do
    triggers = MapSet.new()
    jobs = MapSet.new()
    edges = []

    {triggers, jobs, edges} =
      Enum.reduce(sequence, {triggers, jobs, edges}, fn
        # Trigger only (no jobs)
        trigger_type, {triggers, jobs, edges} when is_atom(trigger_type) ->
          {
            MapSet.put(triggers, trigger_type),
            jobs,
            edges
          }

        # Trigger -> Job edge
        {trigger_type, job_name}, {triggers, jobs, edges}
        when is_atom(trigger_type) ->
          {
            MapSet.put(triggers, trigger_type),
            MapSet.put(jobs, job_name),
            [{trigger_type, job_name} | edges]
          }

        # Job -> Job edge
        {source_job, target_job}, {triggers, jobs, edges}
        when is_binary(source_job) and is_binary(target_job) ->
          {
            triggers,
            jobs |> MapSet.put(source_job) |> MapSet.put(target_job),
            [{source_job, target_job} | edges]
          }
      end)

    {MapSet.to_list(triggers), MapSet.to_list(jobs), Enum.reverse(edges)}
  end

  defp add_triggers(workflow, triggers, opts) do
    {workflow, elements} =
      Enum.reduce(triggers, {workflow, %{}}, fn trigger_type, {wf, elements} ->
        trigger_opts = Map.get(opts, trigger_type, %{})
        trigger = build(:trigger, Map.merge(%{type: trigger_type}, trigger_opts))

        {
          with_trigger(wf, trigger),
          Map.put(elements, trigger_type, trigger)
        }
      end)

    {workflow, elements}
  end

  defp add_jobs(workflow, jobs, opts) do
    {workflow, elements} =
      Enum.reduce(jobs, {workflow, %{}}, fn job_name, {wf, elements} ->
        job_opts = Map.get(opts, job_name, %{})
        job = build(:job, Map.merge(%{name: job_name}, job_opts))

        {
          with_job(wf, job),
          Map.put(elements, job_name, job)
        }
      end)

    {workflow, elements}
  end

  defp add_edges(workflow, edges, elements, opts) do
    Enum.reduce(edges, workflow, fn
      # Trigger -> Job edge
      {trigger_type, job_name}, wf when is_atom(trigger_type) ->
        trigger = elements[trigger_type]
        job = elements[job_name]
        edge_opts = Map.get(opts, {trigger_type, job_name}, %{})
        with_edge(wf, {trigger, job}, edge_opts)

      # Job -> Job edge
      {source_job_name, target_job_name}, wf ->
        source_job = elements[source_job_name]
        target_job = elements[target_job_name]
        edge_opts = Map.get(opts, {source_job_name, target_job_name}, %{})
        with_edge(wf, {source_job, target_job}, edge_opts)
    end)
  end

  describe "diverged_workflows/2" do
    setup do
      source_project = insert(:project, name: "Source Project")
      target_project = insert(:project, name: "Target Project")

      {:ok, source_project: source_project, target_project: target_project}
    end

    test "returns empty list when no workflows exist", %{
      source_project: source,
      target_project: target
    } do
      assert [] = MergeProjects.diverged_workflows(source, target)
    end

    test "returns empty list when workflows are identical", %{
      source_project: source,
      target_project: target
    } do
      # Create identical workflows in both projects
      workflow = insert(:workflow, project: target, name: "Test Workflow")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          workflow,
          "abc123def456",
          "app"
        )

      sandbox_workflow =
        insert(:workflow, project: source, name: "Test Workflow")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          sandbox_workflow,
          "abc123def456",
          "app"
        )

      assert [] = MergeProjects.diverged_workflows(source, target)
    end

    test "returns workflow name when single workflow has diverged", %{
      source_project: source,
      target_project: target
    } do
      # Create diverged workflow
      target_workflow =
        insert(:workflow, project: target, name: "Diverged Workflow")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          target_workflow,
          "abc123def456",
          "app"
        )

      sandbox_workflow =
        insert(:workflow, project: source, name: "Diverged Workflow")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          sandbox_workflow,
          "def456abc123",
          "app"
        )

      assert ["Diverged Workflow"] =
               MergeProjects.diverged_workflows(source, target)
    end

    test "returns list of names when multiple workflows have diverged", %{
      source_project: source,
      target_project: target
    } do
      # Create two diverged workflows
      target_wf1 = insert(:workflow, project: target, name: "Workflow A")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          target_wf1,
          "aaa111111111",
          "app"
        )

      target_wf2 = insert(:workflow, project: target, name: "Workflow B")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          target_wf2,
          "bbb222222222",
          "app"
        )

      sandbox_wf1 = insert(:workflow, project: source, name: "Workflow A")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          sandbox_wf1,
          "aaa999999999",
          "app"
        )

      sandbox_wf2 = insert(:workflow, project: source, name: "Workflow B")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          sandbox_wf2,
          "bbb888888888",
          "app"
        )

      diverged = MergeProjects.diverged_workflows(source, target)
      assert length(diverged) == 2
      assert "Workflow A" in diverged
      assert "Workflow B" in diverged
    end

    test "returns only diverged workflow when one diverged and others match", %{
      source_project: source,
      target_project: target
    } do
      # One matching workflow
      matching_target = insert(:workflow, project: target, name: "Matching")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          matching_target,
          "aabbccddee00",
          "app"
        )

      matching_source = insert(:workflow, project: source, name: "Matching")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          matching_source,
          "aabbccddee00",
          "app"
        )

      # One diverged workflow
      diverged_target = insert(:workflow, project: target, name: "Diverged")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          diverged_target,
          "abc123456789",
          "app"
        )

      diverged_source = insert(:workflow, project: source, name: "Diverged")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          diverged_source,
          "def987654321",
          "app"
        )

      assert ["Diverged"] = MergeProjects.diverged_workflows(source, target)
    end

    test "ignores workflows only in target (not in source)", %{
      source_project: source,
      target_project: target
    } do
      # Workflow only in target
      target_only = insert(:workflow, project: target, name: "Target Only")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          target_only,
          "aabbccddeeff",
          "app"
        )

      assert [] = MergeProjects.diverged_workflows(source, target)
    end

    test "ignores workflows only in source (not in target)", %{
      source_project: source,
      target_project: target
    } do
      # Workflow only in source
      source_only = insert(:workflow, project: source, name: "Source Only")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          source_only,
          "ffeeddccbbaa",
          "app"
        )

      assert [] = MergeProjects.diverged_workflows(source, target)
    end
  end
end
