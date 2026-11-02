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
  A page of workflow templates by name, as `Lightning.Repo.paginate/2` takes
  `page`.

  Filters:

    * `:q` - a case-insensitive search of the name and description.
    * `:tags` - only templates carrying every one of these tags.
  """
  @spec paginate_templates(%{optional(:q | :tags) => term()}, keyword()) ::
          Scrivener.Page.t()
  def paginate_templates(filters, page) do
    WorkflowTemplate
    |> filter_search(filters[:q])
    |> filter_tags(filters[:tags])
    |> order_by([t], asc: t.name, asc: t.id)
    |> Repo.paginate(page)
  end

  defp filter_search(query, q) when is_binary(q) and q != "" do
    pattern = "%" <> escape_like(q) <> "%"

    where(
      query,
      [t],
      ilike(t.name, ^pattern) or ilike(coalesce(t.description, ""), ^pattern)
    )
  end

  defp filter_search(query, _q), do: query

  defp filter_tags(query, [_ | _] = tags),
    do: where(query, [t], fragment("? @> ?", t.tags, ^tags))

  defp filter_tags(query, _tags), do: query

  defp escape_like(text),
    do: String.replace(text, ["\\", "%", "_"], &("\\" <> &1))

  @doc """
  Publishes the workflow as it is saved now, as v2 YAML with its positions,
  under the name, description and tags in `attrs`. A workflow has at most one
  template, so publishing again replaces it.

  `workflow` must have its jobs, triggers and edges loaded. Answers whether the
  template was `:created` or `:updated`, a changeset for invalid `attrs`, or
  `{:error, :export_conflict}` when two of its jobs export under the same key.
  """
  @spec publish_workflow(Workflow.t(), map()) ::
          {:ok, :created | :updated, WorkflowTemplate.t()}
          | {:error, Ecto.Changeset.t() | :export_conflict}
  def publish_workflow(%Workflow{} = workflow, attrs) do
    case Lightning.Workflows.YamlFormat.V2.serialize_workflow(workflow) do
      {:ok, code} ->
        attrs
        |> Map.take([:name, :description, :tags])
        |> Map.merge(%{
          code: code,
          positions: workflow.positions,
          workflow_id: workflow.id
        })
        |> put_template(workflow.id)

      {:error, message} when is_binary(message) ->
        {:error, :export_conflict}
    end
  end

  # Another request may create the workflow's template between the lookup and
  # the insert, which the unique index on `workflow_id` refuses, or delete it
  # before the update, which then finds no row. Either way the request runs
  # again from the lookup. A workflow deleted after it was read takes its
  # template with it, so that is `:concurrent_edit`.
  defp put_template(attrs, workflow_id) do
    case get_template_by_workflow_id(workflow_id) do
      nil -> insert_template(attrs, workflow_id)
      template -> replace_template(template, attrs, workflow_id)
    end
  end

  defp insert_template(attrs, workflow_id) do
    %WorkflowTemplate{}
    |> WorkflowTemplate.changeset(attrs)
    |> Ecto.Changeset.unique_constraint(:workflow_id)
    |> Repo.insert()
    |> case do
      {:ok, template} ->
        {:ok, :created, template}

      {:error, changeset} ->
        cond do
          constraint_on?(changeset, :workflow_id, :unique) ->
            put_template(attrs, workflow_id)

          constraint_on?(changeset, :workflow, :assoc) ->
            {:error, :concurrent_edit}

          true ->
            {:error, changeset}
        end
    end
  end

  defp replace_template(template, attrs, workflow_id) do
    template
    |> WorkflowTemplate.changeset(attrs)
    |> Repo.update(stale_error_field: :id)
    |> case do
      {:ok, template} ->
        {:ok, :updated, template}

      {:error, %{errors: [id: {_message, [stale: true]}]}} ->
        put_template(attrs, workflow_id)

      error ->
        error
    end
  end

  defp constraint_on?(changeset, field, constraint) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.any?(fn {_message, opts} -> opts[:constraint] == constraint end)
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
