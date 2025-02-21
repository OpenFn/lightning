defmodule LightningWeb.CredentialTransferController do
  use LightningWeb, :controller

  alias Lightning.Credentials

  def confirm(conn, %{
        "token" => token,
        "receiver_id" => receiver_id,
        "credential_id" => credential_id
      }) do
    %{assigns: %{current_user: %{id: owner_id}}} = conn

    case Credentials.confirm_transfer(
           credential_id,
           receiver_id,
           owner_id,
           token
         ) do
      {:ok, _credential} ->
        conn
        |> put_flash(:info, "Credential transfer confirmed successfully.")
        |> redirect(to: ~p"/projects")

      {:error, :not_owner} ->
        conn
        |> put_flash(:nav, :no_access_no_back)
        |> redirect(to: ~p"/projects")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Credential transfer couldn't be confirmed.")
        |> redirect(to: ~p"/projects")
    end
  end
end
