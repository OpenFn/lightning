defmodule LightningWeb.API.ApiDocRoutesTest do
  use ExUnit.Case, async: true

  @api_md Path.expand("../../../API.md", __DIR__)

  defp documented_routes do
    ~r/^\| `([A-Z]+)` +\| `(\/api[^`]*)` +\|/m
    |> Regex.scan(File.read!(@api_md), capture: :all_but_first)
    |> MapSet.new(fn [verb, path] -> {verb, path} end)
  end

  defp router_routes do
    LightningWeb.Router
    |> Phoenix.Router.routes()
    |> Enum.filter(&String.starts_with?(&1.path, "/api"))
    # The catch-all that answers 404 for any other /api path is not a route.
    |> Enum.reject(&(&1.verb == :*))
    |> MapSet.new(&{&1.verb |> Atom.to_string() |> String.upcase(), &1.path})
  end

  test "API.md's route table lists every /api route in the router, and no other" do
    documented = documented_routes()
    routed = router_routes()

    assert MapSet.difference(routed, documented) == MapSet.new(),
           "routes missing from API.md"

    assert MapSet.difference(documented, routed) == MapSet.new(),
           "routes in API.md that the router doesn't have"
  end
end
