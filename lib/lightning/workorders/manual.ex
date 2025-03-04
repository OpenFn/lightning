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
    field :body, :string, default: "{}"
  end

  def new(params, attrs \\ []) do
    # params = Map.update(params, "body", "{}", fn body ->
    #   if is_nil(body) and (params["dataclip_id"] || "") == "" do
    #     "{}"
    #   else
    #     body
    #   end
    # end)

    struct(__MODULE__, attrs)
    |> cast(params, [:dataclip_id, :body])
    |> validate_required([:project, :job, :created_by, :workflow])
    |> validate_body_or_dataclip()
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

  defp validate_body_or_dataclip(changeset) do
    Validators.validate_one_required(
      changeset,
      [:dataclip_id, :body],
      "Either a dataclip or a custom body must be present."
    )
  end
end
