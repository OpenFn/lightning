defmodule Lightning.Extensions.CreateProject do
  @moduledoc """
  Initializes a project for Lightning API endpoints.
  """

  @callback create_project(attrs :: map()) ::
              {:ok, map()} | {:error, any()}
end
