defmodule LightningWeb.FirstSetupLive.Superuser do
  @moduledoc """
  Superuser setup liveview

  Allows the creation on the first user in the system.

  It has only one action: `:show`
  """
  use LightningWeb, :live_view
  import LightningWeb.Components.Form

  alias Lightning.Accounts

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
      Accounts.change_superuser_registration(registration_params)
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
    case Accounts.register_superuser(registration_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Superuser account created.")
         |> redirect(
           to:
             Routes.user_session_path(
               socket,
               :exchange_token,
               Accounts.generate_auth_token(user) |> Base.url_encode64()
             )
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp apply_action(socket, :show, _params) do
    if Lightning.Accounts.has_one_superuser?() do
      socket
      |> put_flash(:warn, "Superuser account already exists.")
      |> push_redirect(to: Routes.dashboard_index_path(socket, :index))
    else
      registration = %Accounts.User{}

      socket
      |> assign(:registration, registration)
      |> assign(:changeset, Accounts.change_superuser_registration())
    end
  end
end
