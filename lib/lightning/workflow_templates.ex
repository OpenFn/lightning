defmodule Lightning.WorkflowTemplates do
  @moduledoc """
  The WorkflowTemplates context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowTemplate

  @doc """
  Creates or updates a workflow template.

  If a template already exists for the workflow, it will be updated.
  Otherwise, a new template will be created.

  ## Examples

      iex> create_template(%{name: "My Template", code: "workflow code", workflow_id: "123"})
      {:ok, %WorkflowTemplate{}}

      iex> create_template(%{name: "Invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def create_template(attrs \\ %{}) do
    case get_template_by_workflow_id(attrs["workflow_id"]) do
      nil ->
        %WorkflowTemplate{}
        |> WorkflowTemplate.changeset(attrs)
        |> Repo.insert()

      template ->
        template
        |> WorkflowTemplate.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Gets a template by workflow ID.

  ## Examples

      iex> get_template_by_workflow_id("123")
      %WorkflowTemplate{}

      iex> get_template_by_workflow_id("456")
      nil

  """
  def get_template_by_workflow_id(workflow_id) when is_nil(workflow_id), do: nil

  def get_template_by_workflow_id(workflow_id) do
    Repo.one(from t in WorkflowTemplate, where: t.workflow_id == ^workflow_id)
  end

  @doc """
  Updates a workflow template.

  ## Examples

      iex> update_template(template, %{name: "New Name"})
      {:ok, %WorkflowTemplate{}}

      iex> update_template(template, %{name: ""})
      {:error, %Ecto.Changeset{}}

  """
  def update_template(%WorkflowTemplate{} = template, attrs) do
    template
    |> WorkflowTemplate.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a workflow template.

  ## Examples

      iex> delete_template(template)
      {:ok, %WorkflowTemplate{}}

      iex> delete_template(template)
      {:error, %Ecto.Changeset{}}

  """
  def delete_template(%WorkflowTemplate{} = template) do
    Repo.delete(template)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking template changes.

  ## Examples

      iex> change_template(template)
      %Ecto.Changeset{data: %WorkflowTemplate{}}

  """
  def change_template(%WorkflowTemplate{} = template, attrs \\ %{}) do
    WorkflowTemplate.changeset(template, attrs)
  end

  @doc """
  Gets a single workflow template.

  Raises `Ecto.NoResultsError` if the Workflow template does not exist.

  ## Examples

      iex> get_template!(123)
      %WorkflowTemplate{}

      iex> get_template!(456)
      ** (Ecto.NoResultsError)

  """
  def get_template!(id), do: Repo.get!(WorkflowTemplate, id)

  @doc """
  Gets a single workflow template.

  Returns `nil` if the Workflow template does not exist.

  ## Examples

      iex> get_template(123)
      %WorkflowTemplate{}

      iex> get_template(456)
      nil

  """
  def get_template(id), do: Repo.get(WorkflowTemplate, id)

  @doc """
  Lists all workflow templates.

  ## Examples

      iex> list_templates()
      [%WorkflowTemplate{}, ...]

  """
  def list_templates do
    WorkflowTemplate
    |> order_by([t], t.name)
    |> Repo.all()
  end

  @doc """
  Lists workflow templates for a specific workflow.

  ## Examples

      iex> list_workflow_templates(workflow)
      [%WorkflowTemplate{}, ...]

  """
  def list_workflow_templates(%Workflow{} = workflow) do
    Repo.all(from t in WorkflowTemplate, where: t.workflow_id == ^workflow.id)
  end
end
