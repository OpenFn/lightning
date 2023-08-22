defmodule LightningWeb.ReAuthenticateLive.New do
  @moduledoc """
  LiveView for re-authentication page.
  """
  use LightningWeb, :live_view
  alias Lightning.Accounts

  @impl true
  def mount(_params, %{"user_return_to" => return_to}, socket) do
    {:ok,
     assign(socket,
       authentication_options: [:password, :totp],
       active_option: :password,
       return_to: return_to,
       error_message: nil
     ), layout: {LightningWeb.Layouts, :app}}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     apply_action(
       socket,
       socket.assigns.live_action,
       params
     )}
  end

  @impl true
  def handle_event("toggle-option", %{"option" => option}, socket) do
    {:noreply, assign(socket, active_option: String.to_existing_atom(option))}
  end

  @impl true
  def handle_event("reauthenticate-user", %{"user" => params}, socket) do
    current_user = socket.assigns.current_user

    if valid_user_input?(current_user, params) do
      token = Accounts.generate_sudo_session_token(current_user)
      return_to = append_token(socket.assigns.return_to, Base.encode64(token))

      {:noreply, socket |> push_navigate(to: return_to, replace: true)}
    else
      {:noreply, assign(socket, error_message: error_msg(params))}
    end
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Confirm access")
  end

  defp valid_user_input?(current_user, %{"code" => code}) do
    Accounts.valid_user_totp?(current_user, code)
  end

  defp valid_user_input?(current_user, %{"password" => password}) do
    Accounts.User.valid_password?(current_user, password)
  end

  defp error_msg(%{"password" => _password}) do
    "Invalid password! Try again."
  end

  defp error_msg(%{"code" => _code}) do
    "Invalid OTP code! Try again."
  end

  defp append_token(nil, _token), do: "/"

  defp append_token(path, token) do
    uri = URI.new!(path)
    current_query = URI.decode_query(uri.query || "")
    updated_query = Map.merge(current_query, %{"sudo_token" => token})

    uri = %{uri | query: URI.encode_query(updated_query)}
    URI.to_string(uri)
  end
end
