defmodule Lightning.Credentials.BodyGrantBackfillTest do
  @moduledoc """
  The backfill decides which projects keep working when credential resolution
  starts reading the grant instead of matching environment names. Its one UPDATE
  has no other coverage, so it is read straight out of the migration file and run
  against rows in the state it would find. Reading the file rather than copying
  the SQL means an edit to the migration is an edit to what this tests.
  """
  use Lightning.DataCase, async: false

  import Ecto.Query
  import Lightning.Factories

  alias Lightning.Projects.ProjectCredential
  alias Lightning.Repo

  @migration "priv/repo/migrations/20260908201651_backfill_credential_body_grants.exs"

  defp backfill do
    sql =
      File.read!(@migration)
      |> then(&Regex.run(~r/execute """\n(\s*UPDATE.*?)\n\s*"""/s, &1))
      |> Enum.at(1)
      |> String.trim()

    Repo.query!(sql)
  end

  defp grant_of(share), do: Repo.reload!(share).credential_body_id

  # Clears the grants the credential-creation path sets, so each case starts from
  # the state the migration would actually find on an existing database.
  defp ungrant_all do
    Repo.update_all(ProjectCredential, set: [credential_body_id: nil])
  end

  setup do
    user = insert(:user)

    credential =
      insert(:credential, user: user)
      |> with_body(%{name: "main", body: %{"key" => "production"}})
      |> with_body(%{name: "dev", body: %{"key" => "sandbox"}})

    bodies = Map.new(credential.credential_bodies, &{&1.name, &1.id})

    %{user: user, credential: credential, bodies: bodies}
  end

  test "a root project is granted the body it resolves today", %{
    credential: credential,
    bodies: bodies
  } do
    project = insert(:project, env: "main")
    share = insert(:project_credential, project: project, credential: credential)
    ungrant_all()

    backfill()

    assert grant_of(share) == bodies["main"]
  end

  test "a root project that predates the env column resolves main", %{
    credential: credential,
    bodies: bodies
  } do
    project = insert(:project, env: nil)
    share = insert(:project_credential, project: project, credential: credential)
    ungrant_all()

    backfill()

    # Environment.fetch answers "main" for a root with no env, so that is what
    # the project resolves today and what the grant has to preserve.
    assert grant_of(share) == bodies["main"]
  end

  test "a sandbox is left ungranted even when its env matches a body", %{
    credential: credential
  } do
    parent = insert(:project, env: "main")
    sandbox = insert(:project, env: "dev", parent_id: parent.id)
    share = insert(:project_credential, project: sandbox, credential: credential)
    ungrant_all()

    backfill()

    # This one resolves the dev body today and would keep working if granted.
    # It is still left ungranted: the whole point is that a sandbox's access is
    # a decision someone makes, not one its environment name makes for them.
    assert is_nil(grant_of(share))
  end

  test "a sandbox sitting on its parent's env is left ungranted", %{
    credential: credential
  } do
    parent = insert(:project, env: "main")
    sandbox = insert(:project, env: "main", parent_id: parent.id)
    share = insert(:project_credential, project: sandbox, credential: credential)
    ungrant_all()

    backfill()

    # This is the exposure. Granting it here would record the accident as a
    # decision and keep the sandbox reading production.
    assert is_nil(grant_of(share))
  end

  test "a root project whose env matches no body stays ungranted", %{
    credential: credential
  } do
    project = insert(:project, env: "staging")
    share = insert(:project_credential, project: project, credential: credential)
    ungrant_all()

    backfill()

    # It fails to resolve today too, so leaving it alone preserves behaviour.
    assert is_nil(grant_of(share))
  end

  test "a grant already chosen is not overwritten", %{
    credential: credential,
    bodies: bodies
  } do
    project = insert(:project, env: "main")
    share = insert(:project_credential, project: project, credential: credential)

    Repo.update_all(
      from(pc in ProjectCredential, where: pc.id == ^share.id),
      set: [credential_body_id: bodies["dev"]]
    )

    backfill()

    assert grant_of(share) == bodies["dev"]
  end
end
