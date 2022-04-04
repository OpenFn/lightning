defmodule Lightning.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    adaptor_registry_childspec =
      {Lightning.AdaptorRegistry, Application.get_env(:lightning, Lightning.AdaptorRegistry, [])}

    adaptor_service_childspec =
      {Engine.Adaptor.Service, [name: :adaptor_service, adaptors_path: "./priv/openfn"]}

    children = [
      # Start the Ecto repository
      Lightning.Repo,
      # Start the Telemetry supervisor
      LightningWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Lightning.PubSub},
      # Start the Endpoint (http/https)
      LightningWeb.Endpoint,
      adaptor_registry_childspec,
      adaptor_service_childspec
      # Start a worker by calling: Lightning.Worker.start_link(arg)
      # {Lightning.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Lightning.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LightningWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
