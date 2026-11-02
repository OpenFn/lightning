defmodule LightningWeb.API.ProjectSettingsController do
  @moduledoc """
  The project settings that each have a route of their own, because each needs
  more than renaming a project does. Every route answers 200 with the project,
  as `GET /api/projects/:id` shows it, and refuses any key it doesn't take
  with a 422 `unknown_key` entry.

  `PUT /api/projects/:id/data_retention` takes `retention_policy` (required),
  `history_retention_period` and `dataclip_retention_period`, and needs
  `:edit_data_retention`. A period missing from the body is `null`. A period
  the plan doesn't allow is a `not_allowed` entry, and a dataclip period longer
  than the history period an `out_of_range` one. The dataclip period is
  cleared for `erase_all`, and when there is no history period. Every owner
  and admin is emailed when a period changes.

  `PUT /api/projects/:id/mfa_requirement` takes `requires_mfa` and needs
  `:edit_project`. A sandbox copies it from the project it was created from,
  so setting it there is a `not_allowed` entry. Changing it, on or off, is
  402 `exceeds_limit` when the plan doesn't include requiring MFA.

  `PUT /api/projects/:id/support_access` takes `allow_support_access` and needs
  `:edit_project`.
  """
  use LightningWeb, :controller

  import Ecto.Changeset

  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectLimiter
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:project_users, :edit_data_retention}
       when action == :data_retention

  plug AuthorizeAction,
       {:project_users, :edit_project}
       when action in [:mfa_requirement, :support_access]

  @retention_fields [
    :retention_policy,
    :history_retention_period,
    :dataclip_retention_period
  ]

  @periods [:history_retention_period, :dataclip_retention_period]

  @not_in_plan {"is not a retention period the plan allows", code: :not_allowed}

  @on_sandbox {"can't be set on a sandbox, which copies it from the project it was created from",
               code: :not_allowed}

  @spec data_retention(Plug.Conn.t(), map()) ::
          Plug.Conn.t() | {:error, term()}
  def data_retention(conn, _params) do
    body = conn.body_params

    with {:ok, project} <- target(conn, :edit_data_retention),
         :ok <- Request.check_object(body),
         attrs = retention_attrs(body),
         :ok <- Errors.refuse(retention_entries(project, body, attrs)) do
      update(conn, project, attrs)
    end
  end

  @spec mfa_requirement(Plug.Conn.t(), map()) ::
          Plug.Conn.t() | {:error, term()}
  def mfa_requirement(conn, _params) do
    with {:ok, project} <- target(conn, :edit_project),
         {:ok, requires_mfa} <-
           flag(conn.body_params, :requires_mfa, on_sandbox(project)),
         :ok <- limit_mfa(project, requires_mfa) do
      update(conn, project, %{requires_mfa: requires_mfa})
    end
  end

  @spec support_access(Plug.Conn.t(), map()) ::
          Plug.Conn.t() | {:error, term()}
  def support_access(conn, _params) do
    with {:ok, project} <- target(conn, :edit_project),
         {:ok, allowed} <- flag(conn.body_params, :allow_support_access) do
      update(conn, project, %{allow_support_access: allowed})
    end
  end

  defp target(conn, action) do
    Target.project(
      conn.assigns.scope,
      Request.param(conn, "id"),
      {:project_users, action}
    )
  end

  # A `PUT` replaces all three, so a period left out is `null`, and the
  # dataclip period goes with an `erase_all` policy even when neither period
  # changes, which the project changeset alone would leave in place.
  defp retention_attrs(body) do
    attrs = Map.new(@retention_fields, &{&1, body[Atom.to_string(&1)]})

    if attrs.retention_policy == "erase_all",
      do: %{attrs | dataclip_retention_period: nil},
      else: attrs
  end

  defp retention_entries(project, body, attrs) do
    changeset = Project.changeset(project, attrs)

    required =
      if is_nil(body["retention_policy"]),
        do: [
          Errors.entry(
            [:retention_policy],
            {"can't be blank", validation: :required}
          )
        ],
        else: []

    Request.unknown_keys(body, [], @retention_fields) ++
      required ++ Errors.from_changeset(changeset) ++ plan_entries(changeset)
  end

  # Only periods the request changes are held to the plan, so a project whose
  # plan has since shrunk can still send its settings back unchanged.
  defp plan_entries(changeset) do
    allowed = ProjectLimiter.get_data_retention_periods(changeset.data.id)

    for field <- @periods,
        not Keyword.has_key?(changeset.errors, field),
        {:ok, period} when is_integer(period) <- [fetch_change(changeset, field)],
        period not in allowed,
        do: Errors.entry([field], @not_in_plan)
  end

  # `entries` are the route's own problems with the body, reported with the
  # flag's.
  defp flag(body, field, entries \\ []) do
    with :ok <- Request.check_object(body) do
      request =
        {%{}, %{field => :boolean}}
        |> cast(body, [field])
        |> validate_required(field)

      entries =
        Request.unknown_keys(body, [], [field]) ++
          Errors.from_changeset(request) ++ entries

      with :ok <- Errors.refuse(entries), do: {:ok, get_field(request, field)}
    end
  end

  defp on_sandbox(project) do
    if Project.sandbox?(project),
      do: [Errors.entry([:requires_mfa], @on_sandbox)],
      else: []
  end

  # As the settings page's toggle, a plan without the feature refuses any
  # change, off as well as on. Sending the current value back changes nothing.
  defp limit_mfa(%Project{requires_mfa: same}, same), do: :ok

  defp limit_mfa(project, _requires_mfa),
    do: ProjectLimiter.limit_require_mfa(project.id)

  defp update(conn, project, attrs) do
    with {:ok, project} <-
           Projects.update_project(
             project,
             attrs,
             conn.assigns.current_resource
           ) do
      conn
      |> put_view(json: LightningWeb.API.ProjectJSON)
      |> render("show.json",
        project: Projects.get_project_with_users!(project.id),
        conn: conn
      )
    end
  end
end
