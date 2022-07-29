defmodule LightningWeb.ProfileLive.FormComponent do
  @moduledoc """
  Form component for creating and editing users
  """
  use LightningWeb, :live_component


  def handle_event("save", _params, _socket) do
    IO.inspect("Trying to save.....")
    # save_user(socket, socket.assigns.action, user_params)
  end
end
