defmodule LightningWeb.API.WorkflowTemplateController do
  @moduledoc """
  Workflow templates: workflows published for anyone on the instance to start
  from. Both routes are open to a person on either of their tokens; the
  service account and repo connections are refused 403.

  Publishing is for support users who are members of the workflow's project,
  or whose project allows support access. It publishes the workflow as it is
  saved now, as v2 YAML with its positions, so the body carries only the
  template's `name`, `description` and `tags`. A workflow has at most one
  template, so publishing again replaces it: 201 when it creates, 200 when it
  replaces. To anyone but the service account, who is refused before the
  lookup, an unknown or malformed workflow id is 403 `forbidden`, as for a
  workflow in a project they may not publish from.

  ## Examples

      GET /api/workflow_templates?q=dhis2&tags=fhir,dhis2&page=2
      PUT /api/workflows/a1b2c3d4-.../template
      {"name": "DHIS2 to FHIR", "description": "...", "tags": ["dhis2"]}
  """
  use LightningWeb, :controller

  alias Lightning.Workflows
  alias Lightning.Workflows.WorkflowTemplate
  alias Lightning.WorkflowTemplates
  alias LightningWeb.API.Errors
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback LightningWeb.API.FallbackController

  @fields [:name, :description, :tags]

  plug AuthorizeAction, {:workflows, :list_templates} when action == :index

  plug AuthorizeAction,
       {:workflows, :publish_template} when action == :update

  @doc """
  A page of templates by name, searched by `q` (name and description) and
  filtered by `tags`.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, filters} <-
           params
           |> Filters.workflow_templates()
           |> Errors.refuse_parameters() do
      page =
        WorkflowTemplates.paginate_templates(filters, Filters.page(params))

      render(conn, "index.json", page: page, filters: filters, conn: conn)
    end
  end

  @doc """
  Publishes the workflow as a template, or replaces its template.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    body = conn.body_params

    with {:ok, workflow} <-
           Target.in_project_of(
             conn.assigns.scope,
             Request.param(conn, "id"),
             {:workflows, :publish_template},
             &Workflows.get_project_id/1,
             &Workflows.get_workflow_for_project(&1, &2,
               include: [:edges, :jobs, :triggers]
             )
           ),
         :ok <- Request.check_object(body),
         attrs = %{
           name: body["name"],
           description: body["description"],
           tags: Map.get(body, "tags", [])
         },
         :ok <- refuse_unknown_keys(body, workflow, attrs),
         {:ok, outcome, template} <-
           WorkflowTemplates.publish_workflow(workflow, attrs) do
      conn
      |> put_status(if outcome == :created, do: :created, else: :ok)
      |> render("show.json", template: template)
    end
  end

  # An unknown key, such as a `code` the client built, refuses the body
  # together with every error the template's fields hold.
  defp refuse_unknown_keys(body, workflow, attrs) do
    case Request.unknown_keys(body, [], @fields) do
      [] ->
        :ok

      unknown ->
        # The server writes `code`, so a stand-in keeps it out of the errors.
        changeset =
          WorkflowTemplates.change_template(
            %WorkflowTemplate{},
            Map.merge(attrs, %{code: "-", workflow_id: workflow.id})
          )

        Errors.refuse(unknown ++ Errors.from_changeset(changeset))
    end
  end
end
