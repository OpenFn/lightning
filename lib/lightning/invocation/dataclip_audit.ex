defmodule Lightning.Invocation.DataclipAudit do
  @moduledoc """
  Log dataclip events.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "dataclip",
    events: ["label_created", "label_deleted"]

  @spec save_name_updated(
          Lightning.Invocation.Dataclip.t(),
          Ecto.Changeset.t(Lightning.Invocation.Dataclip.t()),
          Lightning.Accounts.User.t()
        ) ::
          {:ok, :no_changes}
          | {:ok, Ecto.Schema.t()}
          | {:error, Ecto.Changeset.t()}
  def save_name_updated(dataclip, changeset, user) do
    event_name =
      if Ecto.Changeset.get_change(changeset, :name) do
        "label_created"
      else
        "label_deleted"
      end

    event_name
    |> event(dataclip.id, user, changeset)
    |> save()
  end
end
