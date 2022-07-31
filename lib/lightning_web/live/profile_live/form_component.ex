defmodule LightningWeb.ProfileLive.FormComponent do
  @moduledoc """
  Form component for creating and editing users
  """
  use LightningWeb, :live_component

  alias Lightning.Accounts

  @impl true
  def update(%{user: user} = _assigns, socket) do
    IO.inspect("update")
    IO.inspect(user)

    {:ok,
     socket
     |> assign(:password_changeset, Accounts.change_user_password(user))
     |> IO.inspect(label: "Changeset")
     |> assign(:id, user.id)}
  end

  @impl true
  def handle_event(
        "save",
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

    case Accounts.update_user_password(user, current_password, %{password: password}) do
      {:ok, _user} ->

        {:noreply,
         socket
         |> put_flash(:info, "Profile updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
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
