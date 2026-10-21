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
       return_to: return_to
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

  # The page sends the password or the code it was given; which one is on
  # show is the page's own state now (the old `toggle-option` event is gone).
  @impl true
  def handle_event("reauthenticate-user", %{"user" => params}, socket) do
    current_user = socket.assigns.current_user

    case valid_user_input?(current_user, params) do
      true ->
        token = Accounts.generate_sudo_session_token(current_user)
        return_to = append_token(socket.assigns.return_to, Base.encode64(token))

        {:reply, %{}, socket |> push_navigate(to: return_to, replace: true)}

      false ->
        reply_error(socket, error_msg(params))

      :unknown ->
        reply_error(socket, "Enter your password or your authentication code.")
    end
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Confirm access")
  end

  defp valid_user_input?(current_user, %{"code" => code}) when is_binary(code) do
    Accounts.valid_user_totp?(current_user, code)
  end

  defp valid_user_input?(current_user, %{"password" => password})
       when is_binary(password) do
    Accounts.User.valid_password?(current_user, password)
  end

  defp valid_user_input?(_current_user, _params), do: :unknown

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
