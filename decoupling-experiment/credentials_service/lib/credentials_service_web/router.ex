defmodule CredentialsServiceWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
    plug CredentialsServiceWeb.AuthPlug
  end

  scope "/api/v1", CredentialsServiceWeb do
    pipe_through :api

    get "/credentials", CredentialController, :index
    get "/credentials/:id", CredentialController, :show
    post "/credentials", CredentialController, :create
    delete "/credentials/:id", CredentialController, :delete
  end
end
