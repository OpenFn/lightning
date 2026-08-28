defmodule Lightning.AdaptorRegistry do
  @moduledoc """
  Holds `local_adaptors_enabled?/0`, still read by
  `mix lightning.install_schemas` to decide whether to read credential
  schemas from a local adaptors repo instead of npm.
  """

  @doc """
  Whether `Lightning.Config.adaptor_registry/0` has at least one local
  adaptors repo configured (`LOCAL_ADAPTORS`/`OPENFN_ADAPTORS_REPO`).
  """
  @spec local_adaptors_enabled?() :: boolean()
  def local_adaptors_enabled? do
    case Lightning.Config.adaptor_registry()[:local_adaptors_repos] do
      [_ | _] -> true
      _ -> false
    end
  end
end
