defmodule Lightning.Actor do
  @moduledoc """
  Whoever a context function records as having done something: a person or a
  service account.
  """

  @type t :: Lightning.Accounts.User.t() | Lightning.ServiceAccount.t()
end
