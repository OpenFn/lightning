defmodule Lightning.Repo.Migrations.BackfillCredentialBodyGrants do
  use Ecto.Migration

  @moduledoc """
  Gives every root project's share the values it resolves today.

  Root projects keep working: their grant is the body whose name matches the
  environment they already resolve under, which is `env`, or `"main"` for a root
  that predates the column.

  Sandboxes are deliberately left ungranted. A sandbox that resolves its
  parent's production values does so only because the two projects happen to
  name the same environment, and granting that here would record the accident as
  a decision.
  """

  def up do
    execute """
    UPDATE project_credentials pc
    SET credential_body_id = cb.id
    FROM projects p, credential_bodies cb
    WHERE pc.project_id = p.id
      AND pc.credential_body_id IS NULL
      AND p.parent_id IS NULL
      AND cb.credential_id = pc.credential_id
      AND cb.name = COALESCE(p.env, 'main')
    """

    report()
  end

  # Only the grants this migration set. A choice someone has made since is not
  # this migration's to discard.
  def down do
    execute """
    UPDATE project_credentials pc
    SET credential_body_id = NULL
    FROM projects p, credential_bodies cb
    WHERE pc.project_id = p.id
      AND p.parent_id IS NULL
      AND cb.id = pc.credential_body_id
      AND cb.name = COALESCE(p.env, 'main')
    """
  end

  # Counts rather than raises. None of these is a reason to stop: they all
  # resolve nothing today either, so leaving them ungranted preserves behaviour
  # rather than changing it. They are printed because the number of sandboxes
  # that will need a grant is the thing to know before the readers are switched
  # over.
  defp report do
    root_without_body =
      one!("""
      SELECT count(*) FROM project_credentials pc
      JOIN projects p ON p.id = pc.project_id
      WHERE p.parent_id IS NULL AND pc.credential_body_id IS NULL
      """)

    sandbox_shares =
      one!("""
      SELECT count(*) FROM project_credentials pc
      JOIN projects p ON p.id = pc.project_id
      WHERE p.parent_id IS NOT NULL
      """)

    sandboxes_using_a_credential =
      one!("""
      SELECT count(DISTINCT pc.project_id) FROM project_credentials pc
      JOIN projects p ON p.id = pc.project_id
      JOIN jobs j ON j.project_credential_id = pc.id
      WHERE p.parent_id IS NOT NULL
      """)

    IO.puts("""

    Credential grants backfilled.

      Root-project shares still ungranted: #{root_without_body}
        (no body matches the project's environment; these fail to resolve today
        too, so nothing changed for them)

      Sandbox shares, all ungranted by design: #{sandbox_shares}
      Sandboxes with a credential wired to a job: #{sandboxes_using_a_credential}
        (each of these needs a body chosen for it before credential resolution
        starts reading the grant)
    """)
  end

  defp one!(sql) do
    %{rows: [[n]]} = repo().query!(sql)
    n
  end
end
