defmodule LightningWeb.DataclipController do
  use LightningWeb, :controller

  alias Lightning.DataclipScrubber
  alias Lightning.Invocation
  alias Lightning.Policies.Dataclips
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias LightningWeb.WorkflowLive.NewManualRun

  action_fallback LightningWeb.FallbackController

  @max_age 86_400

  def show(conn, %{"id" => dataclip_id}) do
    dataclip_without_body = Invocation.get_dataclip!(dataclip_id)

    if Permissions.can?(
         Dataclips,
         :view_dataclip,
         conn.assigns.current_user,
         dataclip_without_body
       ) do
      maybe_respond_with_body(conn, dataclip_without_body)
    else
      conn
      |> put_status(403)
      |> json(%{error: "You are not authorized to view this dataclip."})
    end
  end

  defp maybe_respond_with_body(conn, dataclip) do
    case get_req_header(conn, "if-modified-since") do
      [last_modified] ->
        if dataclip_is_modified?(dataclip, last_modified) do
          respond_with_body(conn, dataclip.id)
        else
          conn |> send_resp(304, "")
        end

      [] ->
        respond_with_body(conn, dataclip.id)
    end
  end

  defp scrubbed_body(dataclip) do
    dataclip_for_scrubbing = %{
      body: dataclip.body_json,
      type: dataclip.type,
      id: dataclip.id
    }

    DataclipScrubber.scrub_dataclip_body!(dataclip_for_scrubbing)
  end

  defp respond_with_body(conn, dataclip_id) do
    dataclip = Invocation.get_dataclip_with_body!(dataclip_id)

    # Only scrub step_result dataclips (most don't need scrubbing)
    # :http_request | :global | :step_result | :saved_input | :kafka
    body =
      case dataclip.type do
        # For some dataclips, we need to scrub credentials
        # Pass a minimal struct with just what scrubber needs
        :step_result -> scrubbed_body(dataclip)
        :http_request -> scrubbed_body(dataclip)
        # Else, no scrubbing needed
        _else -> dataclip.body_json
      end

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("vary", "Accept-Encoding, Cookie")
    |> put_resp_header("cache-control", "private, max-age=#{@max_age}")
    |> put_resp_header("last-modified", to_rfc1123!(dataclip.updated_at))
    |> send_resp(200, body || "null")
  end

  defp dataclip_is_modified?(dataclip, last_modified) do
    case from_rfc1123(last_modified) do
      {:ok, last_modified} ->
        dataclip.updated_at
        |> DateTime.truncate(:second)
        |> DateTime.after?(last_modified)

      _unknown_date ->
        true
    end
  end

  defp to_rfc1123!(datetime) do
    Timex.format!(datetime, "%a, %d %b %Y %H:%M:%S GMT", :strftime)
  end

  defp from_rfc1123(datetime) do
    with {:ok, naive_date} <-
           Timex.parse(datetime, "%a, %d %b %Y %H:%M:%S GMT", :strftime) do
      DateTime.from_naive(naive_date, "Etc/UTC")
    end
  end

  @doc """
  Search dataclips for a specific job with filters.

  Query params:
  - query: Search text (optional)
  - type: Dataclip type filter (optional)
  - before: Before date filter (optional)
  - after: After date filter (optional)
  - named_only: Show only named dataclips (optional)
  - limit: Max results (default: 10)
  """
  def search(conn, %{"project_id" => project_id, "job_id" => job_id} = params) do
    project = Projects.get_project!(project_id)

    with :ok <-
           Permissions.can(
             :project_users,
             :access_project,
             conn.assigns.current_user,
             project
           ) do
      # Build query string from params
      query_params =
        %{
          "query" => params["query"],
          "type" => params["type"],
          "before" => params["before"],
          "after" => params["after"],
          "named_only" => params["named_only"]
        }
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
        |> Enum.into(%{})

      query_string = URI.encode_query(query_params)
      limit = Map.get(params, "limit", "10") |> String.to_integer()

      case NewManualRun.search_selectable_dataclips(
             job_id,
             query_string,
             limit,
             0
           ) do
        {:ok,
         %{
           dataclips: dataclips,
           next_cron_run_dataclip_id: next_cron_run_dataclip_id
         }} ->
          # Check if user can edit dataclips
          can_edit_dataclip =
            Permissions.can?(
              :project_users,
              :edit_workflow,
              conn.assigns.current_user,
              project
            )

          json(conn, %{
            data: dataclips,
            next_cron_run_dataclip_id: next_cron_run_dataclip_id,
            can_edit_dataclip: can_edit_dataclip
          })

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Get dataclip for a specific run and job.

  Query params:
  - job_id: Job ID to get dataclip for
  """
  def show_for_run(
        conn,
        %{"project_id" => project_id, "run_id" => run_id, "job_id" => job_id}
      ) do
    project = Projects.get_project!(project_id)

    with :ok <-
           Permissions.can(
             :project_users,
             :access_project,
             conn.assigns.current_user,
             project
           ) do
      dataclip = Invocation.get_first_dataclip_for_run_and_job(run_id, job_id)
      run_step = Invocation.get_first_step_for_run_and_job(run_id, job_id)

      json(conn, %{
        dataclip: dataclip,
        run_step: run_step
      })
    end
  end

  @doc """
  Update dataclip name.

  Body:
  - name: New name for dataclip (or null to remove name)
  """
  def update_name(
        conn,
        %{
          "project_id" => project_id,
          "dataclip_id" => dataclip_id,
          "name" => name
        }
      ) do
    project = Projects.get_project!(project_id)
    dataclip = Invocation.get_dataclip!(dataclip_id)

    with :ok <-
           Permissions.can(
             :project_users,
             :edit_workflow,
             conn.assigns.current_user,
             project
           ),
         :ok <-
           Permissions.can(
             :dataclips,
             :view_dataclip,
             conn.assigns.current_user,
             dataclip
           ) do
      case Invocation.update_dataclip_name(
             dataclip,
             name,
             conn.assigns.current_user
           ) do
        {:ok, updated_dataclip} ->
          json(conn, %{data: updated_dataclip})

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end
end
