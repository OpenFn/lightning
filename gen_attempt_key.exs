defmodule KeyGeneration do
  def call_openssl(args) do
    System.cmd("openssl", args, into: IO.stream(:stdio, :line))
    |> case do
      {_, 0} -> :ok
      {_, status} -> {:error, status}
    end
  end

  def create_private_key() do
    filename = "/tmp/jwtRSA256-private.pem"

    with :ok <- call_openssl(~w[genrsa -out #{filename} 2048]),
         {:ok, contents} <- File.read(filename),
         :ok <- File.rm(filename) do
      {:ok, contents}
    end
  end

  def abstract_public_key(private_key) do
    filename = "/tmp/jwtRSA256.pem"

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
end

with {:ok, private_key} <-
       KeyGeneration.create_private_key(),
     {:ok, public_key} <- KeyGeneration.abstract_public_key(private_key) do
  IO.puts("""
  Private Key:

  #{private_key |> Base.encode64(padding: false)}

  Public Key:

  #{public_key |> Base.encode64(padding: false)}
  """)
end
