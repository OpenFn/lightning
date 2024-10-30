defmodule Mix.Tasks.Lightning.GenWorkerKeys do
  @shortdoc "Generate a set of worker keys"
  @moduledoc """
  Helper to generate the private and public keys for worker authentication
  """

  use Mix.Task

  alias Lightning.Utils

  @footer """
  To use these keys, use the above output to set the environment variables.

  Lightning expects the following environment variables to be set:

  - WORKER_RUNS_PRIVATE_KEY
  - WORKER_SECRET

  And the workers expect:

  - WORKER_LIGHTNING_PUBLIC_KEY
  - WORKER_SECRET
  """

  @impl Mix.Task
  def run(_) do
    # looks like we may need "try" with this "with"
    # https://hexdocs.pm/credo/Credo.Check.Readability.PreferImplicitTry.html
    # credo:disable-for-next-line
    {private_key, public_key} = Utils.Crypto.generate_rsa_key_pair()

    IO.puts("""
    WORKER_RUNS_PRIVATE_KEY="#{private_key |> Base.encode64(padding: false)}"

    WORKER_SECRET="#{Utils.Crypto.generate_hs256_key()}"

    WORKER_LIGHTNING_PUBLIC_KEY="#{public_key |> Base.encode64(padding: false)}"


    #{@footer}
    """)
  rescue
    e ->
      IO.puts("Error: #{inspect(e)}")
      exit({:shutdown, 1})
  end
end
