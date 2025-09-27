defmodule Lightning.Projects.MergeProjectsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.MergeProjects

  describe "merge_project/2" do
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

      # Should preserve target project ID but use source metadata
      assert result["id"] == target_project.id
      assert result["name"] == source_project.name
      assert result["description"] == source_project.description

      # Should have one workflow (merged)
      assert length(result["workflows"]) == 1
      workflow = hd(result["workflows"])

      # Workflow should preserve target ID but use source name
      assert workflow["id"] == target_workflow.id
      assert workflow["name"] == source_workflow.name

      # Workflow should not be marked for deletion
      refute workflow["delete"]
    end

    test "merge project with new workflow in source" do
      # Create projects
      target_project = insert(:project, name: "Target Project")
      source_project = insert(:project, name: "Source Project")

      # Target project with one workflow
      target_workflow =
        insert(:workflow, name: "existing_workflow", project: target_project)

      # Source project with existing workflow + new one
      _source_workflow1 =
        insert(:workflow, name: "existing_workflow", project: source_project)

      source_workflow2 =
        insert(:workflow, name: "new_workflow", project: source_project)

      result = MergeProjects.merge_project(source_project, target_project)

      # Should have two workflows
      assert length(result["workflows"]) == 2

      workflow_names =
        result["workflows"] |> Enum.map(& &1["name"]) |> Enum.sort()

      assert workflow_names == ["existing_workflow", "new_workflow"]

      # Existing workflow should preserve target ID
      existing_workflow =
        Enum.find(result["workflows"], &(&1["name"] == "existing_workflow"))

      assert existing_workflow["id"] == target_workflow.id
      refute existing_workflow["delete"]

      # New workflow should get a new UUID (not source ID)
      new_workflow =
        Enum.find(result["workflows"], &(&1["name"] == "new_workflow"))

      assert new_workflow["id"] != source_workflow2.id
      refute new_workflow["delete"]
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

      # Should preserve target ID but use source name
      assert result["id"] == target_project.id
      assert result["name"] == source_project.name
      assert result["workflows"] == []
    end

    test "merge project with workflow containing jobs - integration test" do
      # Test that workflow merging logic works correctly within project merging

      # Create projects
      target_project = insert(:project, name: "Target Project")
      source_project = insert(:project, name: "Source Project")

      # Target project with workflow containing a job
      target_trigger = build(:trigger, type: :webhook)

      target_job =
        build(:job,
          name: "process_data",
          body: "fn(s => s)",
          adaptor: "@openfn/language-common@latest"
        )

      target_workflow =
        build(:workflow, name: "data_processing", project: target_project)
        |> with_trigger(target_trigger)
        |> with_job(target_job)
        |> with_edge({target_trigger, target_job})
        |> insert()

      # Source project with same workflow name but different job adaptor
      source_trigger = build(:trigger, type: :webhook)

      source_job =
        build(:job,
          name: "process_data",
          body: "fn(s => s)",
          adaptor: "@openfn/language-http@latest"
        )

      source_workflow =
        build(:workflow, name: "data_processing", project: source_project)
        |> with_trigger(source_trigger)
        |> with_job(source_job)
        |> with_edge({source_trigger, source_job})
        |> insert()

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

  describe "merge_workflow/2 - merge attributes" do
    test "maps workflow-level attributes from source" do
      # source workflow attributes (name, concurrency, enable_job_logs) are used
      source_trigger = build(:trigger, type: :webhook)
      source_job = build(:job, name: "test_job")

      source =
        build(:workflow,
          name: "Source Workflow",
          concurrency: 5,
          enable_job_logs: true
        )
        |> with_trigger(source_trigger)
        |> with_job(source_job)
        |> with_edge({source_trigger, source_job})
        |> insert()

      target_trigger = build(:trigger, type: :webhook)
      target_job = build(:job, name: "test_job")

      target =
        build(:workflow,
          name: "Target Workflow",
          concurrency: 10,
          enable_job_logs: false
        )
        |> with_trigger(target_trigger)
        |> with_job(target_job)
        |> with_edge({target_trigger, target_job})
        |> insert()

      result = MergeProjects.merge_workflow(source, target)

      # Should preserve target ID but use source attributes
      assert result["id"] == target.id
      assert result["name"] == source.name
      assert result["concurrency"] == source.concurrency
      assert result["enable_job_logs"] == source.enable_job_logs
    end

    test "maps job attributes from source" do
      #  (name, body, adaptor, credentials) are used from source
      source_trigger = build(:trigger, type: :webhook)

      source_job =
        build(:job,
          name: "process_data",
          body: "fn(state => ({ ...state, processed: true }))",
          adaptor: "@openfn/language-http@latest"
        )

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job)
        |> with_edge({source_trigger, source_job})
        |> insert()

      target_trigger = build(:trigger, type: :webhook)

      target_job =
        build(:job,
          name: "process_data",
          body: "fn(state => state)",
          adaptor: "@openfn/language-common@latest"
        )

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job)
        |> with_edge({target_trigger, target_job})
        |> insert()

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
      source_trigger =
        build(:trigger,
          type: :cron,
          cron_expression: "0 */2 * * *",
          comment: "Every 2 hours"
        )

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> insert()

      target_trigger =
        build(:trigger,
          type: :webhook
        )

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> insert()

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
      source_trigger = build(:trigger, type: :webhook)
      source_job = build(:job, name: "test_job")

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> with_job(source_job)
        |> with_edge({source_trigger, source_job},
          condition_type: :js_expression,
          condition_expression: "state.shouldProcess",
          condition_label: "Process if flag is set",
          enabled: false
        )
        |> insert()

      target_trigger = build(:trigger, type: :webhook)
      target_job = build(:job, name: "test_job")

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> with_job(target_job)
        |> with_edge({target_trigger, target_job},
          condition_type: :always,
          condition_expression: nil,
          condition_label: nil,
          enabled: true
        )
        |> insert()

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
      source_trigger =
        build(:trigger,
          type: :webhook,
          custom_path: "/custom/webhook/path"
        )

      source =
        build(:workflow)
        |> with_trigger(source_trigger)
        |> insert()

      target_trigger =
        build(:trigger,
          type: :webhook,
          custom_path: "/different/path"
        )

      target =
        build(:workflow)
        |> with_trigger(target_trigger)
        |> insert()

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
      source_cron_trigger =
        build(:trigger,
          type: :cron,
          cron_expression: "0 */6 * * *",
          comment: "Every 6 hours"
        )

      source_job =
        build(:job,
          name: "process_data",
          body: "fn(state => ({ ...state, processed: true }))",
          adaptor: "@openfn/language-http@latest"
        )

      source =
        build(:workflow)
        |> with_trigger(source_cron_trigger)
        |> with_job(source_job)
        |> with_edge({source_cron_trigger, source_job})
        |> insert()

      # Target workflow - webhook + cron triggers with different attributes
      target_webhook_trigger =
        build(:trigger,
          type: :webhook,
          custom_path: "/target/webhook"
        )

      target_cron_trigger =
        build(:trigger,
          type: :cron,
          cron_expression: "0 * * * *",
          comment: "Every hour"
        )

      target_job =
        build(:job,
          name: "process_data",
          body: "fn(state => state)",
          adaptor: "@openfn/language-common@latest"
        )

      target =
        build(:workflow)
        |> with_trigger(target_webhook_trigger)
        |> with_trigger(target_cron_trigger)
        |> with_job(target_job)
        |> with_edge({target_webhook_trigger, target_job})
        |> with_edge({target_cron_trigger, target_job})
        |> insert()

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
end
