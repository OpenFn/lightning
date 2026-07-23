defmodule Lightning.WorkOrders.Manual do
  @moduledoc """
  A model is used to build WorkOrders with custom input data.
  """

  use Lightning.Schema

  alias Lightning.Validators

  @type t :: %__MODULE__{
          workflow: Lightning.Workflows.Workflow.t(),
          project: Lightning.Projects.Project.t(),
          job: Lightning.Workflows.Job.t(),
          created_by: Lightning.Accounts.User.t(),
          dataclip_id: String.t(),
          body: String.t(),
          is_persisted: boolean()
        }

  @primary_key false
  embedded_schema do
    embeds_one :workflow, Lightning.Workflows.Workflow
    embeds_one :project, Lightning.Projects.Project
    embeds_one :created_by, Lightning.Accounts.User
    embeds_one :job, Lightning.Workflows.Job
    field :is_persisted, :boolean
    field :dataclip_id, Ecto.UUID
    field :body, :string
  end

  def new(params, attrs \\ []) do
    struct(__MODULE__, attrs)
    |> cast(params, [:dataclip_id, :body])
    |> validate_required([:project, :job, :created_by, :workflow])
    |> remove_body_if_dataclip_present()
    |> validate_body_or_dataclip()
    |> validate_dataclip_in_project()
    |> validate_json(:body)
    |> validate_change(:workflow, fn _field, workflow ->
      case workflow do
        %{__meta__: %{state: :built}} ->
          [:workflow, "Workflow must be saved first."]

        _other ->
          []
      end
    end)
  end

  defp remove_body_if_dataclip_present(changeset) do
    if is_nil(get_change(changeset, :dataclip_id)) do
      changeset
    else
      Ecto.Changeset.delete_change(changeset, :body)
    end
  end

  defp validate_json(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      body ->
        case Jason.decode(body) do
          {:ok, body} when is_map(body) -> changeset
          {:ok, _} -> add_error(changeset, field, "Must be an object")
          {:error, _} -> add_error(changeset, field, "Invalid JSON")
        end
    end
  end

  # A client-supplied dataclip_id must belong to the run's project, otherwise a
  # manual run could pull another project's dataclip in as job input.
  defp validate_dataclip_in_project(changeset) do
    dataclip_id = get_change(changeset, :dataclip_id)
    project = get_field(changeset, :project)

    if is_nil(dataclip_id) or is_nil(project) or
         Lightning.Invocation.dataclip_in_project?(dataclip_id, project.id) do
      changeset
    else
      add_error(changeset, :dataclip_id, "does not belong to this project")
    end
  end

  defp validate_body_or_dataclip(changeset) do
    changeset
    |> Validators.validate_one_required(
      [:dataclip_id, :body],
      "Either a dataclip or a custom body must be present."
    )
    |> Validators.validate_exclusive(
      [:dataclip_id, :body],
      "Dataclip and custom body are mutually exclusive."
    )
  end
end
