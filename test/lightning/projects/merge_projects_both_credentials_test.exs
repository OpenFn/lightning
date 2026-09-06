defmodule Lightning.Projects.MergeProjectsBothCredentialsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Projects.MergeProjects
  alias Lightning.Projects.Project
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Workflow

  describe "MergeProjects.merge_project/3 with both credential kinds set" do
    test "remaps each reference instead of silently dropping one" do
      # A persisted job can never hold both references (the DB
      # `credential_exclusivity` constraint forbids it), so this drives an
      # in-memory document through merge_project/3. Both references must
      # survive the remap — the invalid combination is left for import
      # validation to reject loudly, never resolved by silently discarding
      # the project credential.
      source_id = Ecto.UUID.generate()
      target_id = Ecto.UUID.generate()

      source_kc = %KeychainCredential{
        id: Ecto.UUID.generate(),
        name: "shared",
        project_id: source_id
      }

      target_kc = %KeychainCredential{
        id: Ecto.UUID.generate(),
        name: "shared",
        project_id: target_id
      }

      job = %Job{
        id: Ecto.UUID.generate(),
        name: "J1",
        body: "fn(state => state)",
        adaptor: "@openfn/language-common@latest",
        keychain_credential_id: source_kc.id,
        project_credential_id: Ecto.UUID.generate()
      }

      source_workflow = %Workflow{
        id: Ecto.UUID.generate(),
        name: "Flow",
        jobs: [job],
        triggers: [],
        edges: []
      }

      source = %Project{
        id: source_id,
        name: "src",
        workflows: [source_workflow],
        project_credentials: [],
        keychain_credentials: [source_kc]
      }

      target = %Project{
        id: target_id,
        name: "tgt",
        workflows: [],
        project_credentials: [],
        keychain_credentials: [target_kc]
      }

      document = MergeProjects.merge_project(source, target)

      [merged_workflow] = document["workflows"]
      [merged_job] = merged_workflow["jobs"]

      assert merged_job["keychain_credential_id"] == target_kc.id
      assert merged_job["project_credential_id"] == job.project_credential_id
    end
  end
end
