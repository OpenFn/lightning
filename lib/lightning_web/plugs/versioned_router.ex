defmodule LightningWeb.Plugs.VersionedRouter do
  @moduledoc """
  A reusable plug for header-based API versioning with explicit route
  definitions per version.

  Instead of a catch-all `match :*, "/*path"` in the Phoenix router, this
  plug is used with `forward` and delegates to version-specific route
  modules that pattern-match on `{method, path_segments}`.

  ## Usage

  Define a router module that `use`s this plug:

      defmodule LightningWeb.Collections.Router do
        use LightningWeb.Plugs.VersionedRouter,
          version_plug: LightningWeb.Plugs.ApiVersion,
          fallback: LightningWeb.FallbackController,
          versions: %{
            v1: LightningWeb.Collections.V1Routes,
            v2: LightningWeb.Collections.V2Routes
          }
      end

  Then in the Phoenix router:

      forward "/collections", LightningWeb.Collections.Router

  ## Route modules

  Each version module must implement the `c:route/3` callback:

      defmodule LightningWeb.Collections.V1Routes do
        @behaviour LightningWeb.Plugs.VersionedRouter

        @impl true
        def route(conn, "GET", [name]),
          do: MyController.stream(conn, %{"name" => name})

        def route(conn, _method, _path),
          do: {:error, :not_found}
      end

  Actions may return either a `%Plug.Conn{}` (rendered directly) or an
  error tuple like `{:error, :not_found}`, which is passed to the
  configured fallback controller.
  """

  @callback route(Plug.Conn.t(), String.t(), [String.t()]) ::
              Plug.Conn.t() | term()

  defmacro __using__(opts) do
    quote do
      @opts unquote(opts)

      def init(runtime_opts), do: Keyword.merge(@opts, runtime_opts)

      def call(conn, opts) do
        version_plug = Keyword.fetch!(opts, :version_plug)
        versions = Keyword.fetch!(opts, :versions)
        fallback = Keyword.fetch!(opts, :fallback)

        conn = version_plug.call(conn, version_plug.init([]))

        if conn.halted do
          conn
        else
          case Map.get(versions, conn.assigns[:api_version]) do
            nil ->
              Plug.Conn.send_resp(conn, 404, "Not found")

            handler ->
              case handler.route(conn, conn.method, conn.path_info) do
                %Plug.Conn{} = conn -> conn
                error -> fallback.call(conn, error)
              end
          end
        end
      end
    end
  end
end
