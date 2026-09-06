defmodule LightningWeb.UserSocket do
  use Phoenix.Socket

  # A Socket handler
  #
  # It's possible to control the websocket connection and
  # assign values that can be accessed by your channel topics.

  ## Channels

  channel "workflow:*", LightningWeb.WorkflowChannel
  channel "run:*", LightningWeb.RunChannel
  channel "ai_assistant:*", LightningWeb.AiAssistantChannel

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error` or `{:error, term}`. To control the
  # response the client receives in that case, [define an error handler in the
  # websocket
  # configuration](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html#socket/3-websocket-configuration).
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    # max_age: 1209600 is equivalent to two weeks in seconds. The token wraps the
    # user's DB session token, so a deleted session (logout, password reset,
    # disabled account) makes get_user_by_session_token return nil and the
    # connection is refused.
    #
    # Refusing here rather than at each join covers every channel on this socket,
    # including ones added later. A socket opened before the confirmation
    # deadline is not re-checked, so it keeps working until it reconnects.
    with {:ok, session_token} <-
           Phoenix.Token.decrypt(socket, "user socket", token,
             max_age: 1_209_600
           ),
         %Lightning.Accounts.User{} = user <-
           Lightning.Accounts.get_user_by_session_token(session_token),
         false <- Lightning.Accounts.locked_out?(user) do
      {:ok, assign(socket, :current_user, user)}
    else
      _ -> :error
    end
  end

  @impl true
  def id(socket),
    do: LightningWeb.UserAuth.user_socket_topic(socket.assigns.current_user)

  def handle_error(conn, :unauthorized) do
    Plug.Conn.send_resp(conn, 401, "Unauthorized")
  end
end
