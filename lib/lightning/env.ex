defmodule Lightning.Env do
  @moduledoc """
  Mapping between environment variables and configuration values.
  """
  use Vapor.Planner

  dotenv()

  config :workers,
         env([
           {:private_key, "WORKER_RUNS_PRIVATE_KEY",
            required: false, map: &decode_pem/1},
           {:worker_secret, "WORKER_SECRET",
            required: false, map: &String.replace(&1, "\"", "")}
         ])

  def decode_pem(str) do
    str
    |> String.replace("\"", "")
    |> Base.decode64(padding: false)
    |> case do
      {:ok, pem} -> pem
      :error -> raise "Could not decode PEM"
    end
  end
end
