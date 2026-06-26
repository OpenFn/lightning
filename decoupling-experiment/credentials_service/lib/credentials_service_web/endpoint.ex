defmodule CredentialsServiceWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :credentials_service

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug CredentialsServiceWeb.Router
end
