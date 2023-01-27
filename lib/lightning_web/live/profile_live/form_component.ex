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
     |> assign(:user, user)
     |> assign(assigns)}
  end

  @impl true
  def handle_event(
        "save_email",
        %{"user" => user} = user_params,
        socket
      ) do
    # IO.inspect("We are")

    changeset =
      socket.assigns.user
      |> Accounts.User.current_password_changeset(user)
      # |> Accounts.User.validate_current_password(user.password)
      |> IO.inspect()

    {:noreply, socket}

    # case Accounts.deliver_update_email_instructions(
    #        socket.assigns.user,
    #        email,
    #        &(Routes.user_confirmation_url(socket, :edit, &1) |> IO.inspect())
    #      ) do
    #   {:ok, user} ->
    #     {:noreply,
    #      socket
    #      |> put_flash(
    #        :info,
    #        "You will receive an email with instructions shortly."
    #      )}

    #   {:error, %Ecto.Changeset{} = changeset} ->
    #     {:noreply, assign(socket, :email_changeset, changeset)}
    # end
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
end
