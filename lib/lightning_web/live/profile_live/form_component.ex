defmodule LightningWeb.ProfileLive.FormComponent do
  @moduledoc """
  Form component update profile email and password
  """
  use LightningWeb, :live_component

  alias Lightning.Accounts

  @impl true
  def update(%{user: user, action: action}, socket) do
    {:ok,
     socket
     |> assign(
       user: user,
       action: action,
       email_changeset: Accounts.validate_change_user_email(user),
       password_changeset: Accounts.change_user_password(user),
       user_info_changeset: Accounts.change_user_info(user)
     )}
  end

  @impl true
  def handle_event("change_email", %{"user" => user_params}, socket) do
    socket.assigns.user
    |> Accounts.validate_change_user_email(user_params, true)
    |> Ecto.Changeset.apply_action(:validate)
    |> case do
      {:ok, _} ->
        Accounts.deliver_update_email_instructions(
          socket.assigns.user,
          user_params["email"],
          &Routes.user_confirmation_url(socket, :confirm_email, &1)
        )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "You will receive an email with instructions shortly."
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :email_changeset, changeset)}
    end
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
  def handle_event("update_basic_info", %{"user" => user_params}, socket) do
    case Accounts.update_user_info(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User information updated successfully")
         |> push_navigate(to: ~p"/profile")}

      {:error, changeset} ->
        {:noreply, assign(socket, :user_info_changeset, changeset)}
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
      |> Accounts.validate_change_user_email(user_params, false)
      |> Map.put(:action, :validate_email)

    {:noreply, assign(socket, :email_changeset, changeset)}
  end

  @impl true
  def handle_event("validate_basic_info", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_info(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :user_info_changeset, changeset)}
  end

  def enum_options(module, field) do
    value_label_map = %{
      critical: "Critical",
      any: "Anytime"
    }

    module
    |> Ecto.Enum.values(field)
    |> Enum.map(&{Map.get(value_label_map, &1, to_string(&1)), &1})
  end
end
