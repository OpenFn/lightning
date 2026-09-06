defmodule Lightning.Credentials.ScopingNullProjectTest do
  # async: false — this test issues DDL (drops the NOT NULL constraint) inside
  # its own sandboxed transaction, rolled back on exit. It lives in its own file
  # so the constraint drop cannot race the async scoping_test.exs suite.
  use Lightning.DataCase, async: false

  alias Lightning.Credentials.Scoping
  alias Lightning.Projects.ProjectCredential

  import Lightning.Factories

  test "flags a project_credential with a NULL project_id (fail closed)" do
    Repo.query!(
      "ALTER TABLE project_credentials ALTER COLUMN project_id DROP NOT NULL"
    )

    project = insert(:project)
    credential = insert(:credential)
    pc_id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {1, _} =
      Repo.insert_all(ProjectCredential, [
        %{
          id: pc_id,
          project_id: nil,
          credential_id: credential.id,
          inserted_at: now,
          updated_at: now
        }
      ])

    refs = [%{key: :job_a, project_credential_id: pc_id}]

    assert Scoping.out_of_project_references(project.id, refs) ==
             [%{key: :job_a, field: :project_credential_id}]
  end
end
