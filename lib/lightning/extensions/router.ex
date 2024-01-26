defmodule Lightning.Extensions.RouterStub do
  import Phoenix.Router, only: [get: 4]
  import Phoenix.LiveView.Router, only: [live: 4]

  defmacro live_services(_path, _opts) do
    quote do
      get "/" do
        live "/", LightningWeb.DashboardLive.Index, :index
      end
    end
  end
end
