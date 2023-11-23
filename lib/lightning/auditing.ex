defmodule Lightning.Auditing do
  @moduledoc """
  Context for working with Audit records.
  """

  import Ecto.Query
  alias Lightning.Repo
  alias Lightning.Credentials.Audit, as: CredentialAudit
  alias Lightning.Workflows.WebhookAuthMethodAudit, as: WebhookAuthAudit
  alias Lightning.Accounts.User

  def list_all(params \\ %{}) do
    credential_audit_query = create_audit_query(CredentialAudit)
    webhook_auth_audit_query = create_audit_query(WebhookAuthAudit)

    combined_query =
      combine_audit_queries(credential_audit_query, webhook_auth_audit_query)

    final_query = create_final_query(combined_query)

    Repo.paginate(final_query, params)
  end

  defp create_audit_query(audit_module) do
    from a in audit_module.base_query(),
      select: %{
        id: a.id,
        event: a.event,
        item_type: a.item_type,
        item_id: a.item_id,
        changes: a.changes,
        actor_id: a.actor_id,
        inserted_at: a.inserted_at
      }
  end

  defp combine_audit_queries(query1, query2) do
    from a in subquery(query1),
      union_all: ^subquery(query2)
  end

  defp create_final_query(combined_query) do
    from a in subquery(combined_query),
      left_join: u in User,
      on: u.id == a.actor_id,
      select: %{
        id: a.id,
        event: a.event,
        item_type: a.item_type,
        item_id: a.item_id,
        changes: a.changes,
        actor_id: a.actor_id,
        inserted_at: a.inserted_at,
        actor: u
      },
      order_by: [desc: a.inserted_at]
  end
end
