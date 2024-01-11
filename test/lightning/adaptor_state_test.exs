defmodule Lightning.AdaptorStateTest do
  use ExUnit.Case

  test "inspecting filters the configuration" do
    assert inspect(%Lightning.AdaptorState{
             configuration: %{"username" => "asdf", "password" => "pass"}
           }) == inspect(%{"configuration" => "[FILTERED]"})
  end
end
