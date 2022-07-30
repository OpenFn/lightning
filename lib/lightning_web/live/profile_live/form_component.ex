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

  def handle_event("save", _params, _socket) do
    IO.inspect("Trying to save.....")
    # save_user(socket, socket.assigns.action, user_params)
  end

  @impl true
  def handle_event("validate", %{"user" => %{"id" => id}} = _params, socket) do
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
