defmodule Lightning.InvocationFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Invocation` context.
  """

  @doc """
  Generate a dataclip.
  """
  def dataclip_fixture(attrs \\ []) when is_list(attrs) do
    {:ok, dataclip} =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn ->
        Lightning.ProjectsFixtures.project_fixture().id
      end)
      |> Enum.into(%{
        body: %{},
        type: :http_request
      })
      |> Lightning.Invocation.create_dataclip()

    dataclip
  end
end
