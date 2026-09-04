defmodule Lightning.Workflows.Trigger do
  @moduledoc """
  Ecto model for Triggers.

  Triggers represent the criteria in which a Job might be invoked.

  ## Types

  ### Webhook (default)

  A webhook trigger allows a Job to invoked (via `Lightning.Invocation`) when it's
  endpoint is called.
  """
  use Lightning.Schema
  import Lightning.Validators

  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Triggers.WebhookResponseConfig
  alias Lightning.Workflows.Workflow

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil
        }
  @type trigger_type :: :webhook | :cron

  @trigger_types [:webhook, :cron]
  # `\z` not `$`, which in PCRE also matches before a trailing newline.
  @custom_path_format ~r/\A[a-z0-9_-]+\z/
  @custom_path_max 255
  @webhook_reply_types [:before_start, :after_completion, :custom]

  @derive {Jason.Encoder,
           only: [
             :id,
             :comment,
             :custom_path,
             :cron_expression,
             :cron_cursor_job_id,
             :type,
             :enabled,
             :webhook_reply,
             :webhook_response_config
           ]}
  schema "triggers" do
    field :comment, :string
    field :custom_path, :string
    field :cron_expression, :string
    field :enabled, :boolean, default: false

    field :webhook_reply, Ecto.Enum, values: @webhook_reply_types

    belongs_to :workflow, Workflow
    belongs_to :cron_cursor_job, Job

    # Denormalised from the workflow so a custom path is unique within its
    # project. Held there by a composite FK, and never cast from user input.
    field :project_id, :binary_id

    # Set once by the migration, for triggers that already answered at a bare
    # `/i/<path>`. Never cast from params, so the set can only shrink.
    field :legacy_bare_path, :boolean, default: false

    has_many :edges, Lightning.Workflows.Edge, foreign_key: :source_trigger_id

    field :type, Ecto.Enum, values: @trigger_types, default: :webhook

    field :delete, :boolean, virtual: true
    field :has_auth_method, :boolean, virtual: true

    many_to_many :webhook_auth_methods, Lightning.Workflows.WebhookAuthMethod,
      join_through: "trigger_webhook_auth_methods",
      on_replace: :delete

    embeds_one :webhook_response_config, WebhookResponseConfig,
      on_replace: :update

    timestamps()
  end

  def new(attrs) do
    # `change/2` applies whatever it is handed, so the two fields the bare-URL
    # design rests on are stripped here the same way `cast_changeset/2` refuses
    # to cast them.
    attrs = Map.drop(attrs, [:project_id, :legacy_bare_path])

    change(%__MODULE__{}, Map.merge(attrs, %{id: Ecto.UUID.generate()}))
    |> change(attrs)
    |> validate_custom_path()
    |> clear_legacy_bare_path_on_rename()
    |> put_project_id()
    |> put_constraints()
  end

  @doc """
  Whether a string is usable as a webhook's custom path.

  Asked by anything that copies a path written before these rules existed.
  """
  @spec valid_custom_path?(term()) :: boolean()
  def valid_custom_path?(path) when is_binary(path) do
    String.length(path) <= @custom_path_max and
      Regex.match?(@custom_path_format, path) and
      not uuid_shaped?(path)
  end

  def valid_custom_path?(_path), do: false

  defp uuid_shaped?(<<_::288>> = path),
    do: match?({:ok, _}, Ecto.UUID.cast(path))

  defp uuid_shaped?(_path), do: false

  @doc """
  Whether a rejected changeset failed only on the shape of its custom path.

  A duplicate or a missing project also report against `:custom_path`, and
  neither may be answered by inserting without the path, since the path would
  be written back afterwards.
  """
  @spec custom_path_shape_error?(Ecto.Changeset.t()) :: boolean()
  def custom_path_shape_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:custom_path, {_message, meta}} ->
        Keyword.get(meta, :validation) in [:format, :length] or
          Keyword.get(meta, :custom_path_shape) == true

      _other ->
        false
    end)
  end

  @doc """
  Returns true if the trigger uses a synchronous webhook reply mode
  (i.e., the HTTP connection is held open waiting for a response).

  This set must stay in step with the reply modes that actually publish a
  `{:webhook_response, ...}` message — see
  `LightningWeb.RunChannel.maybe_send_after_completion_response/2`, which
  broadcasts for `:after_completion` only. A mode that is synchronous here but
  has no publisher there parks the request process until the webhook response
  timeout for a message nobody sends, so `:custom` (accepted by the schema but
  not implemented, and not offered by the trigger editor) is deliberately
  excluded.
  """
  @spec synchronous?(t()) :: boolean()
  def synchronous?(%__MODULE__{webhook_reply: :after_completion}), do: true

  def synchronous?(%__MODULE__{}), do: false

  @doc false
  def changeset(trigger, attrs) do
    trigger
    |> cast_changeset(attrs)
    |> cast_embed(:webhook_response_config,
      required: false,
      with: &WebhookResponseConfig.changeset/2
    )
    |> validate()
  end

  def cast_changeset(trigger, attrs) do
    cast(trigger, attrs, [
      :id,
      :comment,
      :custom_path,
      :enabled,
      :type,
      :workflow_id,
      :cron_expression,
      :cron_cursor_job_id,
      :has_auth_method,
      :webhook_reply
    ])
  end

  def validate(changeset) do
    changeset
    |> validate_required([:type])
    |> assoc_constraint(:workflow)
    |> validate_by_type()
    |> validate_custom_path()
    # After the trim, so a padded path is judged on what would be stored.
    |> revalidate_custom_path_on_type_change()
    |> put_project_id()
    |> validate_uuid([:id, :workflow_id, :cron_cursor_job_id])
    |> clear_legacy_bare_path_on_rename()
    |> put_constraints()
    |> foreign_key_constraint(:project_id,
      name: :triggers_workflow_id_project_id_fkey,
      message: "does not match the trigger's workflow"
    )
    |> foreign_key_constraint(:cron_cursor_job_id,
      name: "triggers_cron_cursor_job_id_fkey",
      message: "cursor job doesn't exist, or is not in the same workflow"
    )
  end

  defp put_constraints(changeset) do
    changeset
    |> unique_constraint(:id, name: "triggers_pkey")
    |> unique_constraint([:project_id, :custom_path],
      name: :triggers_project_id_custom_path_index,
      error_key: :custom_path,
      message: "is already used by another workflow in this project"
    )
    |> unique_constraint(:custom_path,
      name: :triggers_legacy_bare_path_index,
      message: "is already in use"
    )
  end

  # A grandfathered bare URL belongs to the name it was grandfathered on.
  defp clear_legacy_bare_path_on_rename(changeset) do
    # Ecto drops a change equal to the stored value, so the equal case does not
    # arise today. Compared anyway, so a no-op save cannot retire a live URL.
    case fetch_change(changeset, :custom_path) do
      {:ok, renamed} ->
        if renamed == changeset.data.custom_path do
          changeset
        else
          # `force_change/3`: the struct in hand may be stale.
          force_change(changeset, :legacy_bare_path, false)
        end

      _unchanged ->
        changeset
    end
  end

  # Resolved inside the insert transaction, so any caller with a workflow gets
  # it without knowing to. The composite FK rejects a wrong value.
  defp put_project_id(changeset) do
    prepare_changes(changeset, fn changeset ->
      changeset
      |> resolve_project_id()
      |> require_project_for_custom_path()
    end)
  end

  defp resolve_project_id(changeset) do
    workflow_id = get_field(changeset, :workflow_id)

    if is_nil(get_field(changeset, :project_id)) and not is_nil(workflow_id) do
      case changeset.repo.get(Workflow, workflow_id) do
        %Workflow{project_id: project_id} ->
          put_change(changeset, :project_id, project_id)

        nil ->
          changeset
      end
    else
      changeset
    end
  end

  # Without a project a path is both unreachable and unconstrained. Checked
  # after the project is resolved, since most callers never set it.
  defp require_project_for_custom_path(changeset) do
    if get_field(changeset, :custom_path) &&
         is_nil(get_field(changeset, :project_id)) do
      add_error(
        changeset,
        :custom_path,
        "needs a project, which comes from the trigger's workflow"
      )
    else
      changeset
    end
  end

  # UUID-shaped paths are rejected because `Workflows.get_webhook_trigger/2`
  # resolves those against trigger ids, so one would be unreachable.
  defp validate_custom_path(changeset) do
    changeset
    |> update_change(:custom_path, fn
      path when is_binary(path) ->
        case String.trim(path) do
          "" -> nil
          trimmed -> trimmed
        end

      other ->
        other
    end)
    |> validate_length(:custom_path, max: @custom_path_max)
    |> validate_format(:custom_path, @custom_path_format,
      message:
        "must only contain lowercase letters, numbers, hyphens and underscores"
    )
    |> validate_change(:custom_path, fn :custom_path, path ->
      # `Ecto.UUID.cast/1` accepts any 16-byte binary, which would reject an
      # ordinary name like `orders_intake_v1`.
      case path do
        <<_::288>> ->
          case Ecto.UUID.cast(path) do
            {:ok, _} ->
              [custom_path: {"cannot be a UUID", custom_path_shape: true}]

            :error ->
              []
          end

        _shorter_or_longer ->
          []
      end
    end)
  end

  defp validate_cron(changeset, _options \\ []) do
    changeset
    |> validate_change(:cron_expression, fn _field, cron_expression ->
      Crontab.CronExpression.Parser.parse(cron_expression)
      |> case do
        {:error, error_message} ->
          [{:cron_expression, error_message}]

        {:ok, _exp} ->
          []
      end
    end)
  end

  # Append validations based on the type of the Trigger.
  defp validate_by_type(changeset) do
    changeset
    |> fetch_field!(:type)
    |> case do
      # A cron row can hold a never-validated path. Becoming a webhook
      # would make it a live URL, so it is checked in and dropped out.
      :webhook ->
        changeset
        |> put_change(:cron_expression, nil)
        |> put_change(:cron_cursor_job_id, nil)
        |> put_default(:webhook_reply, :before_start)
        |> maybe_clear_webhook_response_config()

      :cron ->
        changeset
        |> put_change(:custom_path, nil)
        |> put_default(:cron_expression, "0 0 * * *")
        |> validate_cron()
        |> put_change(:webhook_reply, nil)
        |> put_change(:webhook_response_config, nil)

      nil ->
        changeset
    end
  end

  # For a stored path nobody touched. A changed one is already validated, and
  # judging it twice would report a UUID as a character problem.
  defp revalidate_custom_path_on_type_change(changeset) do
    with :error <- fetch_change(changeset, :custom_path),
         {:ok, :webhook} <- fetch_change(changeset, :type),
         path when is_binary(path) <- get_field(changeset, :custom_path),
         false <- valid_custom_path?(path) do
      add_error(
        changeset,
        :custom_path,
        "must only contain lowercase letters, numbers, hyphens and underscores"
      )
    else
      _usable_or_not_a_webhook -> changeset
    end
  end

  defp maybe_clear_webhook_response_config(changeset) do
    case fetch_field!(changeset, :webhook_reply) do
      :after_completion -> changeset
      _ -> put_change(changeset, :webhook_response_config, nil)
    end
  end

  defp put_default(changeset, field, value) do
    changeset
    |> get_field(field)
    |> case do
      nil -> changeset |> put_change(field, value)
      _value -> changeset
    end
  end
end
