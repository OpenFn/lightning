defmodule LightningWeb.ProfileLive.FormComponent do
  @moduledoc """
  Form component for creating and editing users
  """
  use LightningWeb, :live_component

  alias Lightning.Accounts

  @impl true
  def update(%{user: user} = _assigns, socket) do
    {:ok,
     socket
     |> assign(:password_changeset, Accounts.change_user_password(user))
     |> assign(:id, user.id)}
  end

  @impl true
  def handle_event(
        "save",
        %{
          "user" => %{
            "current_password" => _current_password,
            "password" => password,
            "password_confirmation" => _password_confirmation,
            "id" => id
          }
        } = user_params,
        socket
      ) do
    user = Accounts.get_user!(id)

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, _user} ->
        IO.inspect(1)
        {:noreply,
         socket
         |> put_flash(:info, "Profile updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        IO.inspect(2)
        IO.inspect(changeset)
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => %{"id" => id}} = _user_params, socket) do
    changeset =
      id
      |> Accounts.get_user!()
      |> Accounts.change_user_password()

    {:noreply,
     socket
     |> assign(:password_changeset, changeset)
     |> Map.put(:action, :validate)
     |> assign(:id, id)}

    {:noreply, assign(socket, :changeset, changeset)}
  end
end
