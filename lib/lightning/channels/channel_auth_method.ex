defmodule Lightning.Channels.ChannelAuthMethod do
  @moduledoc """
  Join table connecting channels to auth method implementations.

  Each record has a `role` (:source or :sink) and points to exactly one
  of `webhook_auth_method` (for source/inbound auth) or
  `project_credential` (for sink/outbound auth).
  """
  use Lightning.Schema

  alias Lightning.Channels.Channel
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Validators
  alias Lightning.Workflows.WebhookAuthMethod

  @roles [:source, :sink]

  schema "channel_auth_methods" do
    field :role, Ecto.Enum, values: @roles

    belongs_to :channel, Channel
    belongs_to :webhook_auth_method, WebhookAuthMethod
    belongs_to :project_credential, ProjectCredential

    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :role,
      :channel_id,
      :webhook_auth_method_id,
      :project_credential_id
    ])
    |> validate_required([:role, :channel_id])
    |> Validators.validate_exclusive(
      [:webhook_auth_method_id, :project_credential_id],
      "webhook_auth_method_id and project_credential_id are mutually exclusive"
    )
    |> Validators.validate_one_required(
      [:webhook_auth_method_id, :project_credential_id],
      "must reference either a webhook auth method or a project credential"
    )
    |> validate_role_target_consistency()
    |> assoc_constraint(:channel)
    |> foreign_key_constraint(:webhook_auth_method_id)
    |> foreign_key_constraint(:project_credential_id)
  end

  defp validate_role_target_consistency(changeset) do
    case get_field(changeset, :role) do
      :source ->
        if get_field(changeset, :project_credential_id) do
          add_error(
            changeset,
            :project_credential_id,
            "source auth must use a webhook auth method, not a project credential"
          )
        else
          changeset
        end

      :sink ->
        if get_field(changeset, :webhook_auth_method_id) do
          add_error(
            changeset,
            :webhook_auth_method_id,
            "sink auth must use a project credential, not a webhook auth method"
          )
        else
          changeset
        end

      _ ->
        changeset
    end
  end
end
