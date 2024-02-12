defmodule Mix.Tasks.Lightning.GenWorkerKeys do
  @shortdoc "Generate a set of worker keys"
  @moduledoc """
  Helper to generate the private and public keys for worker authentication
  """

  use Mix.Task

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
    try do
      with {:ok, private_key} <- create_private_key(),
           {:ok, public_key} <- abstract_public_key(private_key) do
        IO.puts("""
        WORKER_RUNS_PRIVATE_KEY="#{private_key |> Base.encode64(padding: false)}"

        WORKER_SECRET="#{generate_hs256_key()}"

        WORKER_LIGHTNING_PUBLIC_KEY="#{public_key |> Base.encode64(padding: false)}"


        #{@footer}
        """)
      end
    rescue
      e ->
        case e do
          %{original: :enoent} ->
            IO.puts("openssl not found in PATH")

          e ->
            IO.puts("Error: #{inspect(e)}")
        end

        exit({:shutdown, 1})
    end
  end

  defp call_openssl(args) do
    System.cmd("openssl", args, stderr_to_stdout: true)
    |> case do
      {_, 0} ->
        :ok

      {stdout, status} ->
        {:error, status, stdout}
    end
  end

  defp create_private_key do
    filename = Path.join(System.tmp_dir!(), "jwtRSA256-private.pem")

    with :ok <- call_openssl(~w[genrsa -out #{filename} 2048]),
         {:ok, contents} <- File.read(filename),
         :ok <- File.rm(filename) do
      {:ok, contents}
    end
  end

  defp abstract_public_key(private_key) do
    filename = Path.join(System.tmp_dir!(), "jwtRSA256.pem")

    with :ok <- File.write(filename, private_key),
         :ok <-
           call_openssl(
             ~w[rsa -in #{filename} -pubout -outform PEM -out #{filename}]
           ),
         {:ok, contents} <- File.read(filename),
         :ok <- File.rm(filename) do
      {:ok, contents}
    end
  end

  defp generate_hs256_key do
    32 |> :crypto.strong_rand_bytes() |> Base.encode64()
  end
end
