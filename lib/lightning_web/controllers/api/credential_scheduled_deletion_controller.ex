defmodule LightningWeb.API.CredentialScheduledDeletionController do
  @moduledoc """
  Schedules a credential's deletion, and cancels it, at
  `/api/credentials/:id/scheduled_deletion`.

  Scheduling unlinks the credential from every project at once, revokes its
  OAuth tokens and emails the owner. Lightning deletes it after the instance's
  retention period. `DELETE /api/credentials/:id` already deletes at once, so
  scheduling is a `PUT` on the deletion rather than a `DELETE`.

  Only the owner and the service account may do either, so only the service
  account hears 404 `not_found` for an id that names no credential, or 400
  `invalid_parameter` for one that isn't a UUID. Everyone else hears 403
  `forbidden` for both, as for a credential they may not schedule.
  """
  use LightningWeb, :controller

  alias Lightning.Credentials
  alias LightningWeb.API.CredentialController
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction, {:credentials, :schedule_credential_deletion}

  @doc """
  Schedules the credential's deletion, answering 200 with the credential. One
  already scheduled answers the same, and nothing changes: the date doesn't
  move and the owner isn't emailed again. The route takes no body, so any key
  sent is refused as `unknown_key`.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    with {:ok, credential} <- target(conn),
         :ok <- Request.check_object(conn.body_params),
         :ok <- Errors.refuse(Request.unknown_keys(conn.body_params, [], [])) do
      if credential.scheduled_deletion,
        do: CredentialController.render_credential(conn, credential),
        else: schedule(conn, credential)
    end
  end

  defp schedule(conn, credential) do
    case Credentials.schedule_credential_deletion(
           credential,
           conn.assigns.current_resource
         ) do
      {:ok, credential} ->
        CredentialController.render_credential(conn, credential)

      # Another request scheduled it since the lookup. Rerun the request,
      # which now finds it scheduled.
      {:error, :scheduled_for_deletion} ->
        update(conn, conn.params)

      error ->
        error
    end
  end

  @doc """
  Cancels the credential's scheduled deletion, answering 200 with the
  credential. The project links removed when it was scheduled are not
  restored. A credential that isn't scheduled answers 404 `not_found`.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    with {:ok, credential} <- target(conn),
         :ok <- scheduled(credential),
         {:ok, credential} <-
           Credentials.cancel_scheduled_deletion(
             credential,
             conn.assigns.current_resource
           ) do
      CredentialController.render_credential(conn, credential)
    end
  end

  defp scheduled(%{scheduled_deletion: nil}), do: {:error, :not_found}
  defp scheduled(_credential), do: :ok

  defp target(conn),
    do:
      Target.record(
        conn.assigns.scope,
        Request.param(conn, "id"),
        {:credentials, :schedule_credential_deletion},
        &CredentialController.fetch_credential/1
      )
end
