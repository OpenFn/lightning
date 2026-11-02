defmodule LightningWeb.API.AiMessageController do
  @moduledoc """
  Sending a message to an AI assistant session, and retrying one that failed.

  Only a session token of Lightning's own app may use these routes, and any
  member of the session's project may, viewers included
  (`Lightning.Policies.AiAssistant`). Each answers 201 with the message,
  `pending` until the assistant answers it. The project's AI allowance is
  checked once the request is otherwise valid.
  """
  use LightningWeb, :controller

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.Limiter
  alias Lightning.Jobs
  alias LightningWeb.API.AiAssistantRequest
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction, {:ai_assistant, :chat}

  @chat {:ai_assistant, :chat}

  @doc """
  Adds a message to the session and queues it for the assistant, with the
  attachments and editor context it sends.
  """
  def create(conn, _params) do
    %{scope: %{actor: user}} = conn.assigns
    body = conn.body_params

    with {:ok, {project_id, session}} <- AiAssistantRequest.session(conn, @chat),
         :ok <- Request.check_object(body),
         {:ok, attrs} <- message(session, project_id, body, user),
         :ok <- Limiter.validate_quota(project_id),
         {:ok, message} <- AiAssistant.add_message(session, attrs) do
      conn
      |> put_status(:created)
      |> put_view(json: LightningWeb.API.AiSessionJSON)
      |> render("message.json",
        message: message,
        session_id: session.id,
        conn: conn
      )
    end
  end

  @doc """
  Asks the assistant again a message of the session that failed, with what the
  message sent the first time. Takes no body.
  """
  def retry(conn, _params) do
    body = conn.body_params

    with {:ok, {project_id, session}} <- AiAssistantRequest.session(conn, @chat),
         {:ok, message_id} <- Request.id(Request.param(conn, "message_id")),
         {:ok, message} <-
           AiAssistant.get_message_for_session(session.id, message_id),
         :ok <- retryable(message),
         :ok <- Request.check_object(body),
         :ok <- Errors.refuse(Request.unknown_keys(body, [], [])),
         :ok <- Limiter.validate_quota(project_id),
         {:ok, message} <- AiAssistant.retry_failed_message(message) do
      conn
      |> put_status(:created)
      |> put_view(json: LightningWeb.API.AiSessionJSON)
      |> render("message.json",
        message: message,
        session_id: session.id,
        conn: conn
      )
    end
  end

  defp retryable(message),
    do:
      if(AiAssistant.retryable?(message),
        do: :ok,
        else: {:error, :not_retryable}
      )

  defp message(session, project_id, body, user) do
    kind =
      if session.session_type == "job_code", do: "job_code", else: "workflow"

    {entries, message} = AiAssistantRequest.read(body, [], kind, project_id)

    with :ok <- Errors.refuse(entries) do
      meta =
        message.attach
        |> AiAssistantRequest.attach_meta()
        |> Map.merge(job_meta(session, message.context))

      {:ok, %{content: message.content, user: user, meta: meta}}
    end
  end

  # A saved job's editor text goes with this message only; a job not yet saved
  # goes with every message, since the assistant learns of it from the message.
  defp job_meta(%{session_type: "job_code", job_id: job_id}, context)
       when is_binary(job_id) do
    case Jobs.get_job(job_id) do
      {:ok, job} ->
        %{"runtime_context" => AiAssistantRequest.runtime_context(context, job)}

      {:error, :not_found} ->
        %{}
    end
  end

  defp job_meta(
         %{session_type: "job_code", meta: %{"unsaved_job" => held}},
         context
       )
       when is_map(held) do
    %{
      "unsaved_job" =>
        AiAssistantRequest.unsaved_job(
          context,
          held,
          held["id"],
          held["workflow_id"]
        )
    }
  end

  defp job_meta(_session, _context), do: %{}
end
