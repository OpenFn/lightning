defmodule Lightning.Extensions.Routing do
  @extensions Application.compile_env(
                :lightning,
                Lightning.Extensions
              )

  def init(opts), do: opts

  def call(conn, opts) do
    router = Keyword.get(@extensions, :router) |> dbg()

    if router do
      router.call(conn, opts)
    else
      conn
    end
  end
end
