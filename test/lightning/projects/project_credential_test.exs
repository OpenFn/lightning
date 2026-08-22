defmodule Lightning.Projects.ProjectCredentialTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.ProjectCredential

  import Lightning.Factories

  test "project_id is NOT NULL at the database layer" do
    credential = insert(:credential)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.insert_all(ProjectCredential, [
          %{
            id: Ecto.UUID.generate(),
            project_id: nil,
            credential_id: credential.id,
            inserted_at: now,
            updated_at: now
          }
        ])
      end

    assert %Postgrex.Error{postgres: %{code: :not_null_violation}} = error
  end
end
