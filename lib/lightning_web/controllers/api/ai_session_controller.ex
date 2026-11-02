defmodule LightningWeb.API.AiSessionController do
  @moduledoc """
  The AI assistant's sessions: listing a project's, starting one with its first
  message, and reading one with its messages.

  Only a session token of Lightning's own app may use these routes, and any
  member of the session's project may, viewers included
  (`Lightning.Policies.AiAssistant`). A session's `kind` is `job_code` (about
  one job, saved or not yet saved) or `workflow` (about a workflow, saved, not
  yet saved, or none yet), which Lightning stores as `workflow_template`.

  The disclaimer isn't checked yet, so there is no 422 `must_accept`: Lightning
  keeps no record of a person accepting it (migration 20260707080205 removed
  the last one), and recording it is `PATCH /api/users/:id`, which isn't here.
  """
  use LightningWeb, :controller

  alias Ecto.Changeset
  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.Limiter
  alias Lightning.Jobs
  alias Lightning.Workflows
  alias LightningWeb.API.AiAssistantRequest
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:ai_assistant, :read_ai_sessions} when action in [:index, :show]

  plug AuthorizeAction, {:ai_assistant, :chat} when action == :create

  @read {:ai_assistant, :read_ai_sessions}
  @chat {:ai_assistant, :chat}

  @kinds ["job_code", "workflow"]
  @not_a_uuid {"is not a UUID", validation: :cast, type: :binary_id}

  @doc """
  Lists the project's sessions about the job `job_id` or the workflow
  `workflow_id`, one of which must be sent, newest activity first, paged.
  An id from another project lists nothing.
  """
  def index(conn, params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @read
           ),
         {:ok, {key, id}} <- about(params) do
      page =
        AiAssistant.page_sessions(project.id, {key, id}, Filters.page(params))

      render(conn, "index.json", page: page, filters: %{key => id}, conn: conn)
    end
  end

  @doc """
  Reads a session with its messages, oldest first.
  """
  def show(conn, _params) do
    with {:ok, {_project_id, session}} <- AiAssistantRequest.session(conn, @read) do
      render(conn, "show.json", session: session, conn: conn)
    end
  end

  @doc """
  Starts a session in the project with its first message, `pending` until the
  assistant answers it. The project's AI allowance is checked first, once the
  body is valid.
  """
  def create(conn, _params) do
    %{scope: %{actor: user} = scope} = conn.assigns
    body = conn.body_params

    with {:ok, project} <-
           Target.project(scope, Request.param(conn, "project_id"), @chat),
         :ok <- Request.check_object(body),
         {:ok, start} <- start(project, body),
         :ok <- Limiter.validate_quota(project.id),
         {:ok, session} <- start_session(start, project, user) do
      conn
      |> put_status(:created)
      |> render("show.json", session: session, conn: conn)
    end
  end

  defp about(params) do
    entries =
      for key <- ["job_id", "workflow_id"],
          Map.has_key?(params, key),
          Request.id({{:parameter, key}, params[key]}) |> elem(0) == :error,
          do: Errors.entry({:parameter, key}, @not_a_uuid)

    case {entries, params} do
      {[_ | _], _params} ->
        refuse_parameters(entries)

      {[], %{"job_id" => _, "workflow_id" => _}} ->
        refuse_parameters([
          Errors.entry(
            {:parameter, "workflow_id"},
            {"can't be sent with %{other}", code: :exclusive, other: "job_id"}
          )
        ])

      {[], %{"job_id" => id}} ->
        {:ok, {:job_id, String.downcase(id)}}

      {[], %{"workflow_id" => id}} ->
        {:ok, {:workflow_id, String.downcase(id)}}

      {[], _params} ->
        refuse_parameters([
          Errors.entry(
            {:parameter, "job_id"},
            {"can't be blank unless workflow_id is sent", code: :required}
          )
        ])
    end
  end

  defp refuse_parameters(entries),
    do:
      {:error, LightningWeb.API.Problem.new(:invalid_parameter, errors: entries)}

  # Reads the body into what starting the session needs, refusing every
  # problem with it at once.
  defp start(project, body) do
    {kind_entries, kind} = kind(body)
    {id_entries, ids} = ids(body)

    {message_entries, message} =
      case Map.fetch(body, "message") do
        {:ok, message} ->
          AiAssistantRequest.read(message, ["message"], kind, project.id)

        :error ->
          {[Errors.entry(["message"], {"can't be blank", code: :required})], nil}
      end

    {about_entries, about} =
      if id_entries == [],
        do: about_target(project, kind, ids, message),
        else: {[], nil}

    entries =
      Request.unknown_keys(body, [], [:kind, :job_id, :workflow_id, :message]) ++
        kind_entries ++ id_entries ++ about_entries ++ message_entries

    with :ok <- Errors.refuse(entries),
         do: {:ok, %{about: about, message: message}}
  end

  defp kind(body) do
    changeset =
      {%{}, %{kind: :string}}
      |> Changeset.cast(body, [:kind])
      |> Changeset.validate_required([:kind])
      |> Changeset.validate_inclusion(:kind, @kinds)

    entries =
      Enum.map(Enum.reverse(changeset.errors), fn {field, error} ->
        Errors.entry([field], error)
      end)

    {entries, if(changeset.valid?, do: Changeset.get_change(changeset, :kind))}
  end

  defp ids(body) do
    Enum.reduce(["job_id", "workflow_id"], {[], %{}}, fn key, {entries, ids} ->
      case Map.fetch(body, key) do
        :error ->
          {entries, ids}

        {:ok, value} ->
          case Request.id({[key], value}) do
            {:ok, id} ->
              {entries, Map.put(ids, key, id)}

            {:error, _invalid} ->
              {entries ++ [Errors.entry([key], @not_a_uuid)], ids}
          end
      end
    end)
  end

  defp about_target(_project, nil, _ids, _message), do: {[], nil}

  defp about_target(_project, "job_code", ids, _message)
       when not is_map_key(ids, "job_id"),
       do: {[Errors.entry(["job_id"], {"can't be blank", code: :required})], nil}

  defp about_target(project, "job_code", ids, message) do
    case Jobs.get_job_for_project(project.id, ids["job_id"]) do
      {:ok, job} -> saved_job(job, ids)
      {:error, :not_found} -> unsaved_job(project, ids, message)
    end
  end

  defp about_target(_project, "workflow", %{"job_id" => _}, _message),
    do:
      {[
         Errors.entry(
           ["job_id"],
           {"can't be sent with a workflow session", code: :not_allowed}
         )
       ], nil}

  defp about_target(_project, "workflow", ids, _message)
       when not is_map_key(ids, "workflow_id"),
       do: {[], {:workflow, nil}}

  # An id saved in no workflow of this project is a workflow not yet saved, as
  # the editor names one before its first save. Another project's workflow is
  # treated the same, so the answer says nothing about it.
  defp about_target(project, "workflow", %{"workflow_id" => id}, _message) do
    case Workflows.get_workflow_for_project(project.id, id) do
      {:ok, workflow} -> {[], {:workflow, workflow}}
      {:error, :not_found} -> {[], {:unsaved_workflow, id}}
    end
  end

  defp saved_job(job, %{"workflow_id" => workflow_id})
       when workflow_id != job.workflow_id,
       do:
         {[
            Errors.entry(
              ["workflow_id"],
              {"is not the job's workflow", code: :mismatch}
            )
          ], nil}

  defp saved_job(job, _ids), do: {[], {:job, job}}

  # A job not yet saved needs the saved workflow it is in, and a name.
  defp unsaved_job(project, ids, message) do
    {workflow_entries, workflow} =
      case Map.fetch(ids, "workflow_id") do
        :error ->
          {[Errors.entry(["workflow_id"], {"can't be blank", code: :required})],
           nil}

        {:ok, id} ->
          case Workflows.get_workflow_for_project(project.id, id) do
            {:ok, workflow} ->
              {[], workflow}

            {:error, :not_found} ->
              {[Errors.entry(["workflow_id"], Errors.not_visible())], nil}
          end
      end

    name_entries =
      case message do
        %{context: %{"name" => name}} when is_binary(name) ->
          []

        %{context: _context} ->
          [
            Errors.entry(
              ["message", "context", "name"],
              {"can't be blank for a job not yet saved", code: :required}
            )
          ]

        nil ->
          []
      end

    {workflow_entries ++ name_entries,
     workflow && {:unsaved_job, ids["job_id"], workflow}}
  end

  defp start_session(%{about: about, message: message}, project, user) do
    attach_meta = AiAssistantRequest.attach_meta(message.attach)

    case about do
      {:job, job} ->
        meta =
          Map.put(
            attach_meta,
            "runtime_context",
            AiAssistantRequest.runtime_context(message.context, job)
          )

        AiAssistant.create_session(job, user, message.content,
          message_meta: meta
        )

      {:unsaved_job, id, workflow} ->
        unsaved_job =
          AiAssistantRequest.unsaved_job(message.context, %{}, id, workflow.id)

        AiAssistant.create_session_for_unsaved_job(
          user,
          message.content,
          %{"unsaved_job" => unsaved_job},
          message_meta: Map.put(attach_meta, "unsaved_job", unsaved_job)
        )

      {:workflow, workflow} ->
        AiAssistant.create_workflow_session(
          project,
          nil,
          workflow,
          user,
          message.content,
          message_meta: attach_meta
        )

      {:unsaved_workflow, id} ->
        AiAssistant.create_workflow_session(
          project,
          nil,
          nil,
          user,
          message.content,
          meta: %{"unsaved_workflow" => %{"id" => id, "is_new" => true}},
          message_meta: attach_meta
        )
    end
  end
end
