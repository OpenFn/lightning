defmodule Lightning.Repo.Migrations.RemoveLegacyCredentialTransfers do
  use Ecto.Migration

  import Ecto.Query

  @moduledoc """
  Clears state left by the pre-stateless credential-transfer flow.

  Older transfers were confirmed via an opaque email token plus a three-segment
  URL that no longer routes, so any transfer still pending at deploy time can
  never be confirmed. Cancel those pending transfers and drop the orphaned
  `credential_transfer` token rows, which the stateless flow never reads.

  Runs before the new code serves traffic, so every pending transfer at this
  point predates the change. `:completed` transfers are left untouched as
  historical markers. Irreversible: `down` is a no-op.
  """

  def up do
    execute(fn ->
      repo().delete_all(from(t in "user_tokens", where: t.context == "credential_transfer"))
    end)

    execute(fn ->
      repo().update_all(
        from(c in "credentials", where: c.transfer_status == "pending"),
        set: [transfer_status: nil]
      )
    end)
  end

  def down, do: :ok
end
