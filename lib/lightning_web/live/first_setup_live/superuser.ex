defmodule LightningWeb.FirstSetupLive.Superuser do
  @moduledoc """
  Superuser setup liveview

  Allows the creation on the first user in the system.

  It has only one action: `:show`
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts

  @impl true
  def mount(_params, _session, socket) do
    # BlockRoutes refuses the HTTP request, but a live navigation from another
    # LiveView in the :default live_session reaches this without any plug.
    if Lightning.Config.check_flag?(:allow_first_setup) do
      {:ok, socket |> assign(:is_first_setup, true)}
    else
      {:ok, redirect(socket, to: ~p"/projects")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  # The page sends its five fields once, on Save; it checks them as it goes.
  # The server checks them again: the changeset's own rules plus the
  # confirmation the old validate event added.
  @impl true
  def handle_event("save", params, socket) do
    registration_params = %{
      "first_name" => params["firstName"],
      "last_name" => params["lastName"],
      "email" => params["email"],
      "password" => params["password"],
      "password_confirmation" => params["passwordConfirmation"]
    }

    changeset =
      Accounts.change_superuser_registration(registration_params)
      |> Ecto.Changeset.validate_confirmation(:password)

    with true <- changeset.valid?,
         {:ok, user} <- Accounts.register_superuser(registration_params) do
      {:reply, %{},
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
    else
      false -> reply_error(socket, changeset)
      {:error, %Ecto.Changeset{} = changeset} -> reply_error(socket, changeset)
    end
  end

  defp apply_action(socket, :show, _params) do
    if Lightning.Accounts.has_one_superuser?() do
      socket
      |> put_flash(:warn, "Superuser account already exists.")
      |> push_navigate(to: Routes.dashboard_index_path(socket, :index))
    else
      socket
    end
  end
end
