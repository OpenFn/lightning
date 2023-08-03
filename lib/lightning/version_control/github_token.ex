defmodule Lightning.VersionControl.GithubToken do
  @moduledoc """
  A module that `uses` Joken to handle building and signing application 
  tokens for communicating with github
  """
  use Joken.Config
end
