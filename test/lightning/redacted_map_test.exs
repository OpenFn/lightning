defmodule Lightning.RedactedMapTest do
  use ExUnit.Case

  test "inspecting filters the configuration" do
    assert inspect(%Lightning.RedactedMap{
             value: %{"username" => "asdf", "password" => "pass"}
           }) == "[REDACTED]"
  end
end
