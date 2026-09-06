defmodule Lightning.Credentials.ScopingTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.Scoping

  import Lightning.Factories

  describe "out_of_project_references/2" do
    test "reports a project_credential owned by another project" do
      project = insert(:project)
      other = insert(:project)
      pc = insert(:project_credential, project: other)

      refs = [%{key: :job_a, project_credential_id: pc.id}]

      assert Scoping.out_of_project_references(project.id, refs) ==
               [%{key: :job_a, field: :project_credential_id}]
    end

    test "reports a keychain_credential owned by another project" do
      project = insert(:project)
      other = insert(:project)
      kc = insert(:keychain_credential, project: other)

      refs = [%{key: :job_a, keychain_credential_id: kc.id}]

      assert Scoping.out_of_project_references(project.id, refs) ==
               [%{key: :job_a, field: :keychain_credential_id}]
    end

    test "does not report credentials owned by the same project" do
      project = insert(:project)
      pc = insert(:project_credential, project: project)
      kc = insert(:keychain_credential, project: project)

      refs = [
        %{
          key: :job_a,
          project_credential_id: pc.id,
          keychain_credential_id: kc.id
        }
      ]

      assert Scoping.out_of_project_references(project.id, refs) == []
    end

    test "does not report nil ids" do
      project = insert(:project)

      refs = [
        %{key: :job_a, project_credential_id: nil, keychain_credential_id: nil}
      ]

      assert Scoping.out_of_project_references(project.id, refs) == []
    end

    test "does not report unknown/non-existent ids" do
      project = insert(:project)

      refs = [
        %{
          key: :job_a,
          project_credential_id: Ecto.UUID.generate(),
          keychain_credential_id: Ecto.UUID.generate()
        }
      ]

      assert Scoping.out_of_project_references(project.id, refs) == []
    end

    test "reports both fields when a single ref offends on both" do
      project = insert(:project)
      other = insert(:project)
      pc = insert(:project_credential, project: other)
      kc = insert(:keychain_credential, project: other)

      refs = [
        %{
          key: :job_a,
          project_credential_id: pc.id,
          keychain_credential_id: kc.id
        }
      ]

      violations = Scoping.out_of_project_references(project.id, refs)

      assert Enum.sort_by(violations, & &1.field) == [
               %{key: :job_a, field: :keychain_credential_id},
               %{key: :job_a, field: :project_credential_id}
             ]
    end

    test "reports only the offending refs in a mixed batch" do
      project = insert(:project)
      other = insert(:project)

      same_pc = insert(:project_credential, project: project)
      other_pc = insert(:project_credential, project: other)
      other_kc = insert(:keychain_credential, project: other)

      refs = [
        %{key: :ok_job, project_credential_id: same_pc.id},
        %{key: :bad_pc_job, project_credential_id: other_pc.id},
        %{key: :bad_kc_job, keychain_credential_id: other_kc.id},
        %{key: :empty_job, project_credential_id: nil}
      ]

      violations = Scoping.out_of_project_references(project.id, refs)

      assert Enum.sort_by(violations, & &1.key) == [
               %{key: :bad_kc_job, field: :keychain_credential_id},
               %{key: :bad_pc_job, field: :project_credential_id}
             ]
    end
  end

  describe "job_refs_for_project/1" do
    test "returns every job across the project's workflows with the ref shape" do
      project = insert(:project)
      pc = insert(:project_credential, project: project)
      kc = insert(:keychain_credential, project: project)

      wf_a = insert(:workflow, project: project)
      wf_b = insert(:workflow, project: project)

      pc_job = insert(:job, workflow: wf_a, project_credential: pc)
      kc_job = insert(:job, workflow: wf_a, keychain_credential: kc)
      bare_job = insert(:job, workflow: wf_b)

      # A soft-deleted workflow still contributes its jobs: a document that
      # soft-deletes a workflow while planting a cross-project ref must be scanned.
      deleted_wf =
        insert(:workflow, project: project, deleted_at: DateTime.utc_now())

      deleted_job = insert(:job, workflow: deleted_wf)

      # A job in another project must not appear.
      other_project = insert(:project)
      other_wf = insert(:workflow, project: other_project)
      insert(:job, workflow: other_wf)

      refs = Scoping.job_refs_for_project(project.id)

      assert Enum.sort_by(refs, & &1.label) ==
               Enum.sort_by(
                 [
                   %{
                     key: pc_job.id,
                     label: pc_job.name,
                     project_credential_id: pc.id,
                     keychain_credential_id: nil
                   },
                   %{
                     key: kc_job.id,
                     label: kc_job.name,
                     project_credential_id: nil,
                     keychain_credential_id: kc.id
                   },
                   %{
                     key: bare_job.id,
                     label: bare_job.name,
                     project_credential_id: nil,
                     keychain_credential_id: nil
                   },
                   %{
                     key: deleted_job.id,
                     label: deleted_job.name,
                     project_credential_id: nil,
                     keychain_credential_id: nil
                   }
                 ],
                 & &1.label
               )
    end

    test "returns [] for a project with no jobs" do
      project = insert(:project)

      assert Scoping.job_refs_for_project(project.id) == []
    end
  end

  describe "job_refs_for_workflow/1" do
    test "returns only the target workflow's jobs with the ref shape" do
      project = insert(:project)
      pc = insert(:project_credential, project: project)

      target_wf = insert(:workflow, project: project)
      other_wf = insert(:workflow, project: project)

      target_job = insert(:job, workflow: target_wf, project_credential: pc)
      insert(:job, workflow: other_wf)

      assert Scoping.job_refs_for_workflow(target_wf.id) == [
               %{
                 key: target_job.id,
                 label: target_job.name,
                 project_credential_id: pc.id,
                 keychain_credential_id: nil
               }
             ]
    end
  end
end
