defmodule LightningWeb.RequestContext do
  def put_sentry_context(conn_or_socket, _opts \\ []) do
    conn_or_socket
    |> put_request_context()
    |> put_user_context()
  end

  defp put_request_context(%Plug.Conn{} = conn) do
    Sentry.Context.set_request_context(%{
      url: Plug.Conn.request_url(conn),
      method: conn.method,
      headers: %{
        "User-Agent":
          Plug.Conn.get_req_header(conn, "user-agent") |> List.first()
      },
      query_string: conn.query_string,
      env: %{
        REQUEST_ID:
          Plug.Conn.get_resp_header(conn, "x-request-id") |> List.first(),
        SERVER_NAME: conn.host
      }
    })

    conn
  end

  defp put_request_context(%Phoenix.LiveView.Socket{} = socket) do
    request_context = %{
      host: socket.host_uri.host
    }

    request_id = Phoenix.LiveView.get_connect_info(socket, :request_id)
    user_agent = Phoenix.LiveView.get_connect_info(socket, :user_agent)

    extras = %{
      headers: %{
        "User-Agent": user_agent
      },
      env: %{
        REQUEST_ID: request_id
      }
    }

    Sentry.Context.set_request_context(Map.merge(request_context, extras))
    socket
  end

  defp put_user_context(conn_or_socket) do
    user = conn_or_socket.assigns[:current_user]

    if user do
      Sentry.Context.set_user_context(%{
        id: user.id,
        email: user.email
      })
    end

    conn_or_socket
  end
end
