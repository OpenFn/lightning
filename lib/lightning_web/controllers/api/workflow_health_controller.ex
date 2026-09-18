defmodule LightningWeb.API.WorkflowHealthController do
  @moduledoc """
  Aggregate stats for the workflow health page.

  Cookie-authenticated, because the only caller is the React component the
  health LiveView mounts. This is its own trust boundary — the LiveView's
  `on_mount` guards do not protect it, since a client can request any path.
  Access to the project is re-checked here, via the same policy the rest of the
  app uses, so support users get in and soft-deleted projects don't.

  One action per chart, so a cheap chart isn't held up by an expensive one.
  """
  use LightningWeb, :controller

  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Workflows

  plug :authorize_workflow
  # After :authorize_workflow so a 404 wins over a 400.
  plug :validate_days
  plug :validate_timezone when action in [:runs]

  def outcomes(conn, _params) do
    json(
      conn,
      Workflows.Stats.outcomes(conn.assigns.workflow, conn.assigns.days_back)
    )
  end

  def error_signatures(conn, _params) do
    json(
      conn,
      Workflows.Stats.error_signatures(
        conn.assigns.workflow,
        conn.assigns.days_back
      )
    )
  end

  # `vary` because this is the one action whose body depends on a request
  # header, and nothing between the browser and here would guess that.
  def runs(conn, _params) do
    conn
    |> put_resp_header("vary", "x-timezone")
    |> json(
      Workflows.Stats.runs(
        conn.assigns.workflow,
        conn.assigns.days_back,
        conn.assigns.timezone
      )
    )
  end

  # Closed set, string-matched — no free integer, no parse to defend.
  @days %{"1" => 1, "7" => 7, "30" => 30}
  @default_days "30"
  @default_timezone "Etc/UTC"

  # CLDR's sentinel for a host clock it could not map to an IANA zone. A
  # browser sending it is telling us it does not know, which is the same thing
  # as not telling us.
  @unknown_timezone "Etc/Unknown"

  defp validate_days(conn, _opts) do
    case Map.fetch(@days, conn.params["days"] || @default_days) do
      {:ok, days_back} ->
        assign(conn, :days_back, days_back)

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "days must be one of 1, 7, 30"})
        |> halt()
    end
  end

  # The reader's timezone, because nothing in Lightning records one. The only
  # place a default is chosen: a browser that sends no header, or says it does
  # not know, gets UTC; anything else that is not a zone is a 400, because the
  # browser picked it and drawing someone else's clock would hide that.
  #
  # Validated before it reaches the cache key, so `:workflow_stats` is keyed on
  # the tz database rather than on anything a header can carry.
  defp validate_timezone(conn, _opts) do
    case get_req_header(conn, "x-timezone") do
      [] ->
        assign(conn, :timezone, @default_timezone)

      [@unknown_timezone] ->
        assign(conn, :timezone, @default_timezone)

      [timezone] ->
        if Tzdata.zone_exists?(timezone),
          do: assign(conn, :timezone, timezone),
          else: reject_timezone(conn)

      _ ->
        reject_timezone(conn)
    end
  end

  defp reject_timezone(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "x-timezone must be an IANA timezone name"})
    |> halt()
  end

  defp authorize_workflow(conn, _opts) do
    %{"project_id" => project_id, "workflow_id" => workflow_id} = conn.params

    with %_{} = user <- conn.assigns[:current_user],
         {:ok, project_id} <- Ecto.UUID.cast(project_id),
         %{project: project} = workflow <-
           Workflows.get_workflow_for_project(
             %Project{id: project_id},
             workflow_id,
             include: [:project]
           ),
         :ok <- Permissions.can(:project_users, :access_project, user, project) do
      assign(conn, :workflow, workflow)
    else
      # 404 for every failure, not 403: a 403 would confirm the workflow exists
      # to someone who can't see the project.
      _ ->
        conn
        |> put_status(:not_found)
        |> put_view(LightningWeb.ErrorView)
        |> render(:"404")
        |> halt()
    end
  end
end
