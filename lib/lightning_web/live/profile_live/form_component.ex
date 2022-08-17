defmodule LightningWeb.ProfileLive.FormComponent do
  @moduledoc """
  Form component update profile email and password
  """
  use LightningWeb, :live_component

  alias Lightning.Accounts

  @impl true
  def update(%{user: user} = assigns, socket) do
    {:ok,
     socket
     |> assign(:password_changeset, Accounts.change_user_password(user))
     |> assign(:email_changeset, Accounts.change_user_email(user))
     |> assign(
       :scheduled_deletion_changeset,
       Accounts.change_user_scheduled_deletion(user)
     )
     |> assign(assigns)}
  end

  @impl true
  def handle_event(
        "save_password",
        %{"user" => %{"current_password" => current_password} = user_params},
        socket
      ) do
    case Accounts.update_user_password(
           socket.assigns.user,
           current_password,
           user_params
         ) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password changed successfully.")
         |> redirect(
           to:
             Routes.user_session_path(
               socket,
               :exchange_token,
               Accounts.generate_auth_token(user) |> Base.url_encode64()
             )
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :password_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("validate_password", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate_password)

    {:noreply, assign(socket, :password_changeset, changeset)}
  end

  @impl true
  def handle_event("validate_email", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate_email)

    {:noreply, assign(socket, :email_changeset, changeset)}
  end

  @impl true
  def handle_event(
        "validate_scheduled_deletion",
        %{"user" => _user_params},
        socket
      ) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_scheduled_deletion()
      |> Map.put(:action, :validate_scheduled_deletion)

    {:noreply, assign(socket, :scheduled_deletion_changeset, changeset)}
  end

  @impl true
  def handle_event(
        "save_scheduled_deletion",
        %{"user" => %{"email" => _email} = _user_params},
        socket
      ) do
    case Accounts.schedule_user_deletion(socket.assigns.user) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User scheduled for deletion")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :scheduled_deletion_changeset, changeset)}
    end
  end
end
