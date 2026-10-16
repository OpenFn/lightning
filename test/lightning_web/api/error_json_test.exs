defmodule LightningWeb.API.ErrorJSONTest do
  use ExUnit.Case, async: true

  alias LightningWeb.API.ErrorJSON
  alias LightningWeb.API.Problem

  defp render(path, status) do
    conn = Plug.Test.conn(:get, path)
    ErrorJSON.render("#{status}.json", %{conn: conn, status: status})
  end

  test "an unexpected failure on an API path is 500 internal" do
    assert render("/api/jobs", 500) == Problem.body(Problem.new(:internal))
  end

  test "a status with no response code keeps ErrorView's answer" do
    assert render("/api/jobs", 409) == %{"error" => "Conflict"}
  end

  test "a path the format doesn't cover keeps ErrorView's answer" do
    assert render("/i/abc", 500) == %{"error" => "Internal Server Error"}
    assert render("/api/oauth/token", 404) == %{"error" => "Not Found"}
  end
end
