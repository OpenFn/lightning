defmodule LightningWeb.UserLive.FormComponent do
  @moduledoc """
  Form component for creating and editing users
  """
  use LightningWeb, :live_component

  alias Lightning.Accounts

  @impl true
  def update(%{user: user} = assigns, socket) do
    changeset = Accounts.change_user(user, %{})

    {_source, role} = Ecto.Changeset.fetch_field(changeset, :role)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:role, role)
     |> assign(:is_support_user, user.support_user)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user(user_params)
      |> Map.put(:action, :validate)

    {_source, role} = Ecto.Changeset.fetch_field(changeset, :role)

    {:noreply,
     socket
     |> assign(:role, role)
     |> assign(:changeset, changeset)}
  end

  def handle_event("support_heads_up", params, socket) do
    {:noreply,
     socket
     |> assign(:is_support_user, Map.get(params, "value", false))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    save_user(socket, socket.assigns.action, user_params)
  end

  def user_options do
    Accounts.User.RolesEnum.__valid_values__()
    |> Enum.filter(&is_binary(&1))
    |> Enum.sort()
    |> Enum.map(fn role -> {String.capitalize(role), role} end)
  end

  defp save_user(socket, :edit, user_params) do
    case Accounts.update_user_details(socket.assigns.user, user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:is_support_user, user.support_user)
         |> put_flash(:info, "User updated successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_user(socket, :new, user_params) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            socket.assigns.current_user,
            user
          )

        {:noreply,
         socket
         |> assign(:is_support_user, user.support_user)
         |> put_flash(:info, "User created successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
