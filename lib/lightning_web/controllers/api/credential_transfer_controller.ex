defmodule LightningWeb.API.CredentialTransferController do
  @moduledoc """
  Gives a credential to another user, at `/api/credentials/:id/transfer`. The
  owner starts a transfer, Lightning emails them a link to confirm it, and
  ownership moves once they follow it.

  Only the owner may start or cancel one, on a person's token, so the service
  account and a repo connection are refused before any credential is read.
  Nobody learns whether an id names a credential: anyone but its owner hears
  403 `forbidden` for it, an unknown id and one that isn't a UUID alike. A
  credential scheduled for deletion answers 409 `scheduled_for_deletion`.
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Credentials
  alias LightningWeb.API.CredentialController
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Problem
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction, {:credentials, :transfer_credential}

  @no_access "is not a member of every project the credential is linked to"

  @doc """
  Starts a transfer to the user with the body's `recipient` email, answering
  200 with the credential, `transfer_status` `pending`. The recipient must be
  a member of every project the credential is linked to.

  An instance that doesn't allow transfers answers 501 `not_implemented`.
  Starting again while a transfer is pending sends the owner a new link, as
  the app does, because Lightning keeps no record of whom a pending transfer
  is for.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    owner = conn.assigns.current_resource
    body = conn.body_params

    with :ok <- transfers_allowed(),
         {:ok, credential} <- target(conn),
         :ok <- Request.check_object(body),
         {:ok, recipient} <- check_recipient(body, owner, credential),
         :ok <-
           Credentials.initiate_credential_transfer(owner, recipient, credential),
         {:ok, credential} <- reload(credential) do
      CredentialController.render_credential(conn, credential)
    end
  end

  @doc """
  Cancels the pending transfer, answering 200 with the credential. A
  credential with no pending transfer answers 404 `not_found`.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    with {:ok, credential} <- target(conn),
         {:ok, credential} <- revoke(credential, conn.assigns.current_resource) do
      CredentialController.render_credential(conn, credential)
    end
  end

  defp revoke(credential, owner) do
    case Credentials.revoke_transfer(credential, owner) do
      {:error, :not_pending} -> {:error, :not_found}
      result -> result
    end
  end

  defp transfers_allowed do
    if Lightning.Config.allow_credential_transfer?(),
      do: :ok,
      else: {:error, Problem.new(:not_implemented)}
  end

  defp check_recipient(body, owner, credential) do
    key_entries = Request.unknown_keys(body, [], [:recipient])

    case body["recipient"] do
      email when is_binary(email) ->
        changeset =
          email
          |> Credentials.credential_transfer_changeset()
          |> Credentials.validate_credential_transfer(owner, credential)
          |> without_project_names()

        entries =
          key_entries ++
            Errors.from_changeset(changeset, %{email: :recipient})

        with :ok <- Errors.refuse(entries),
             do:
               {:ok,
                changeset
                |> Ecto.Changeset.get_field(:email)
                |> Accounts.get_user_by_email()}

      nil ->
        Errors.refuse(
          key_entries ++
            [Errors.entry([:recipient], {"can't be blank", code: :required})]
        )

      _other ->
        Errors.refuse(
          key_entries ++
            [Errors.entry([:recipient], {"must be an email", code: :type})]
        )
    end
  end

  # The context names the projects the recipient isn't in. An entry never
  # describes another record, so it says only that some are missing.
  defp without_project_names(changeset) do
    errors =
      Enum.map(changeset.errors, fn
        {field, {_message, opts}} = error ->
          if opts[:code] == :no_access,
            do: {field, {@no_access, opts}},
            else: error
      end)

    %{changeset | errors: errors}
  end

  defp reload(credential) do
    case CredentialController.fetch_credential(credential.id) do
      {:error, :not_found} -> {:error, :concurrent_edit}
      found -> found
    end
  end

  defp target(conn),
    do:
      Target.record(
        conn.assigns.scope,
        Request.param(conn, "id"),
        {:credentials, :transfer_credential},
        &CredentialController.fetch_credential/1
      )
end
