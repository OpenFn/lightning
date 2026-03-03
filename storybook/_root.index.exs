defmodule Storybook.Root do
  @moduledoc false
  # See https://hexdocs.pm/phoenix_storybook/PhoenixStorybook.Index.html for full index
  # documentation.

  use PhoenixStorybook.Index

  def folder_name, do: "Storybook"
  def folder_icon, do: {:fa, "book-open", :light, "lsb-mr-1"}
  def folder_open?, do: true
  def folder_index, do: 0

  def entry("welcome") do
    [
      name: "Welcome Page",
      icon: {:fa, "hand-wave", :thin}
    ]
  end
end
