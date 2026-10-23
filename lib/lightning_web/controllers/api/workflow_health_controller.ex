defmodule LightningWeb.API.WorkflowHealthController do
  @moduledoc """
  Aggregate stats for the workflow health page.

  Cookie-authenticated, because the only caller is the React component the
  health LiveView mounts. This is its own trust boundary — the LiveView's
  `on_mount` guards do not protect it, since a client can request any path.
  Access to the project is re-checked here, via the same policy the rest of the
  app uses, so support users get in and a project scheduled for deletion is
  refused.

  One action per chart, so a cheap chart isn't held up by an expensive one.
  """
  use LightningWeb, :controller

  alias Ecto.Changeset
  alias Lightning.Workflows
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Problem
  alias LightningWeb.API.Target

  action_fallback FallbackController

  def outcomes(conn, params) do
    with {:ok, workflow} <- authorize(conn, params),
         {:ok, days_back} <- fetch_days(params) do
      json(conn, Workflows.Stats.outcomes(workflow, days_back))
    end
  end

  def error_signatures(conn, params) do
    with {:ok, workflow} <- authorize(conn, params),
         {:ok, days_back} <- fetch_days(params) do
      json(conn, Workflows.Stats.error_signatures(workflow, days_back))
    end
  end

  # `vary` because this is the one action whose body depends on a request
  # header, and nothing between the browser and here would guess that.
  def runs(conn, params) do
    with {:ok, workflow} <- authorize(conn, params),
         {:ok, days_back} <- fetch_days(params),
         {:ok, timezone} <- fetch_timezone(conn) do
      conn
      |> put_resp_header("vary", "x-timezone")
      |> json(Workflows.Stats.runs(workflow, days_back, timezone))
    end
  end

  # A closed set matched as strings, so there is no integer to parse.
  @days %{"1" => 1, "7" => 7, "30" => 30}
  @default_timezone "Etc/UTC"

  # CLDR's sentinel for a host clock it could not map to an IANA zone. A
  # browser sending it is telling us it does not know, which is the same thing
  # as not telling us.
  @unknown_timezone "Etc/Unknown"

  @not_allowed {"is invalid", validation: :inclusion}

  defp fetch_days(params) do
    with {:ok, %{days: days}} <-
           {%{days: "7"}, %{days: :string}}
           |> Changeset.cast(params, [:days], empty_values: [])
           |> Changeset.validate_inclusion(:days, Map.keys(@days))
           |> Changeset.apply_action(:validate)
           |> Errors.refuse_parameters(),
         do: {:ok, Map.fetch!(@days, days)}
  end

  # The reader's timezone, because nothing in Lightning records one. The only
  # place a default is chosen: a browser that sends no header, or says it does
  # not know, gets UTC; anything else that is not a zone is a 400, because the
  # browser picked it and drawing someone else's clock would hide that.
  #
  # Validated before it reaches the cache key, so `:workflow_stats` is keyed on
  # the tz database rather than on anything a header can carry.
  defp fetch_timezone(conn) do
    case get_req_header(conn, "x-timezone") do
      [] ->
        {:ok, @default_timezone}

      [@unknown_timezone] ->
        {:ok, @default_timezone}

      [timezone] ->
        if Tzdata.zone_exists?(timezone),
          do: {:ok, timezone},
          else: refuse_timezone()

      _ ->
        refuse_timezone()
    end
  end

  defp refuse_timezone do
    {:error,
     Problem.new(:invalid_header,
       errors: [Errors.entry({:header, "x-timezone"}, @not_allowed)]
     )}
  end

  defp authorize(conn, %{"project_id" => project_id, "workflow_id" => id}) do
    Target.in_project(
      conn.assigns.current_user,
      project_id,
      {:project_users, :access_project},
      &fetch_workflow(&1, id)
    )
  end

  defp fetch_workflow(project, id) do
    case Workflows.get_workflow_for_project(project, id) do
      nil -> {:error, :not_found}
      workflow -> {:ok, workflow}
    end
  end
end
