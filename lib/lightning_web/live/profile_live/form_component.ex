defmodule LightningWeb.ProfileLive.FormComponent do
  @moduledoc """
  Form component update profile email and password
  """
  use LightningWeb, :live_component

  alias Lightning.Accounts

  @impl true
  def update(%{user: user} = _assigns, socket) do
    {:ok,
     socket
     |> assign(:password_changeset, Accounts.change_user_password(user))
     |> assign(:email_changeset, Accounts.change_user_email(user))
     |> assign(:id, user.id)}
  end

  @impl true
  def handle_event(
        "save_password",
        %{
          "user" => %{
            "current_password" => current_password,
            "password" => password,
            "id" => id
          }
        } = _user_params,
        socket
      ) do
    user = Accounts.get_user!(id)

    case Accounts.update_user_password(user, current_password, %{
           password: password
         }) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Profile password updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :password_changeset, changeset)}
    end
  end

  @impl true
  def handle_event(
        "save_email",
        %{
          "user" => %{
            "current_password" => _current_password,
            "email" => _email,
            "id" => id
          }
        } = _user_params,
        socket
      ) do
    user = Accounts.get_user!(id)

    case Accounts.update_user_email(
           user,
           "todo: implement token functionality in seperate PR"
         ) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Profile email updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :email_changeset, changeset)}
    end
  end

  @impl true
  def handle_event(
        "validate_password",
        %{"user" => %{"id" => id}} = _user_params,
        socket
      ) do
    changeset =
      id
      |> Accounts.get_user!()
      |> Accounts.change_user_password()

    {:noreply,
     socket
     |> assign(:password_changeset, changeset)
     |> Map.put(:action, :validate)
     |> assign(:id, id)}

    {:noreply, assign(socket, :password_changeset, changeset)}
  end

  @impl true
  def handle_event(
        "validate_email",
        %{"user" => %{"id" => id}} = _user_params,
        socket
      ) do
    changeset =
      id
      |> Accounts.get_user!()
      |> Accounts.change_user_email()

    {:noreply,
     socket
     |> assign(:email_changeset, changeset)
     |> Map.put(:action, :validate)
     |> assign(:id, id)}

    {:noreply, assign(socket, :email_changeset, changeset)}
  end
end
