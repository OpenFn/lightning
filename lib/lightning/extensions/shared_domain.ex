defmodule Lightning.Extensions.SharedDomain do
  @moduledoc """
  Initializes shared entities with other apps.
  """

  @callback register_user(attrs :: map()) ::
              {:ok, map()} | {:error, any()}

  @callback register_superuser(attrs :: map()) ::
              {:ok, map()} | {:error, any()}

  @callback create_user(attrs :: map()) ::
              {:ok, map()} | {:error, any()}

  @callback create_project(attrs :: map()) ::
              {:ok, map()} | {:error, any()}
end
