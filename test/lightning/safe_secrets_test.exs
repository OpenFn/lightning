defmodule Lightning.SafeSecretsTest do
  use ExUnit.Case

  test "inspecting filters the configuration" do
    assert inspect(%Lightning.SafeSecrets{
             configuration: %{"username" => "asdf", "password" => "pass"}
           }) == inspect(%{"configuration" => "[FILTERED]"})
  end
end
