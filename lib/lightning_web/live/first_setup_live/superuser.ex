defmodule LightningWeb.FirstSetupLive.Superuser do
  @moduledoc """
  Superuser setup liveview

  Allows the creation on the first user in the system.

  It has only one action: `:show`
  """
  use LightningWeb, :live_view
  import LightningWeb.Components.Form

  alias Lightning.Users

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:is_first_setup, true)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event(
        "validate",
        %{"superuser_registration" => registration_params},
        socket
      ) do
    changeset =
      socket.assigns.registration
      |> Users.change_user(registration_params)
      |> Ecto.Changeset.validate_confirmation(:password)
      |> Ecto.Changeset.validate_length(:password, min: 8)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event(
        "save",
        %{"superuser_registration" => registration_params},
        socket
      ) do
    case Users.create_user(registration_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Superuser account created.")
         |> push_redirect(to: Routes.dashboard_index_path(socket, :index))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp apply_action(socket, :show, _params) do
    if Lightning.Users.has_one_superuser?() do
      socket
      |> put_flash(:warn, "Superuser account already exists.")
      |> push_redirect(to: Routes.dashboard_index_path(socket, :index))
    else
      registration = %Users.User{}

      socket
      |> assign(:registration, registration)
      |> assign(:changeset, registration |> Users.change_user())
    end
  end
end
