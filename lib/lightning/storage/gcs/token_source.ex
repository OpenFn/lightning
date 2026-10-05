defmodule Lightning.Storage.GCS.TokenSource do
  @moduledoc """
  Source of the OAuth bearer token used for Google Cloud Storage requests.

  `Lightning.Storage.GCS` needs a token on every call, but `Goth` is only
  started when `STORAGE_BACKEND=gcs` (see `Lightning.Application`), so it isn't
  running under test. This indirection lets the test suite supply a token
  without a live Goth process, in the same way `Lightning.Config` swaps its
  implementation for `Lightning.MockConfig`.
  """
  @callback fetch() :: {:ok, %{token: String.t()}} | {:error, term()}

  defmodule API do
    @moduledoc false
    @behaviour Lightning.Storage.GCS.TokenSource

    @impl true
    def fetch, do: Goth.fetch(Lightning.Google)
  end

  @doc """
  Fetches a bearer token for the Google Cloud Storage scopes.
  """
  @spec fetch() :: {:ok, %{token: String.t()}} | {:error, term()}
  def fetch, do: impl().fetch()

  defp impl do
    Application.get_env(:lightning, __MODULE__, API)
  end
end
