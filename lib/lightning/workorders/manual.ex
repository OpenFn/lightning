defmodule Lightning.WorkOrders.Manual do
  @moduledoc """
  A model is used to build WorkOrders with custom input data.
  """
  @type t :: %__MODULE__{
          project: Lightning.Projects.Project.t(),
          job: Lightning.Jobs.Job.t(),
          user: Lightning.Accounts.User.t(),
          dataclip_id: String.t(),
          body: String.t(),
          is_persisted: boolean()
        }

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_one :project, Lightning.Projects.Project
    embeds_one :user, Lightning.Accounts.User
    embeds_one :job, Lightning.Jobs.Job
    field :is_persisted, :boolean
    field :dataclip_id, Ecto.UUID
    field :body, :string
  end

  def changeset(%{project: project, job: job, user: user}, attrs) do
    %__MODULE__{}
    |> cast(attrs, [:body, :dataclip_id])
    |> put_embed(:project, project)
    |> put_embed(:job, job)
    |> put_embed(:user, user)
    |> validate_required([:project, :job, :user])
    |> remove_body_if_dataclip_present()
    |> validate_change(:body, fn
      _, nil ->
        []

      _, body ->
        case Jason.decode(body) do
          {:ok, _} ->
            []

          {:error, _} ->
            [{:body, "Invalid JSON"}]
        end
    end)
    |> Lightning.Validators.validate_one_required(
      [:dataclip_id, :body],
      "Either a dataclip or a custom body must be present."
    )
    |> Lightning.Validators.validate_exclusive(
      [:dataclip_id, :body],
      "Dataclip and custom body are mutually exclusive."
    )
    |> then(fn changeset ->
      with %{__meta__: %{state: :built}} <- get_field(changeset, :job) do
        changeset |> add_error(:job, "Workflow must be saved first.")
      else
        _ -> changeset
      end
    end)
  end

  defp remove_body_if_dataclip_present(changeset) do
    case get_change(changeset, :dataclip_id) do
      nil -> changeset
      _ -> Ecto.Changeset.delete_change(changeset, :body)
    end
  end
end
