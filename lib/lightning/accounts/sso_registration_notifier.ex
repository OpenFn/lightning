defmodule Lightning.Accounts.SsoRegistrationNotifier do
  @moduledoc """
  Fire-and-forget notification to the OpenFn registration workflow trigger when
  a user signs up via SSO.

  The webhook expects a `multipart/form-data` body with string values; missing
  fields are sent as empty strings so the downstream mapping stays stable.
  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  alias Lightning.Accounts.User
  alias Tesla.Multipart

  require Logger

  @doc """
  Enqueues a registration notification for the given user.

  No-op (returns `:ok`) when `OPENFN_TRIGGER_URL` is not configured, so
  self-hosted instances are unaffected.
  """
  @spec enqueue(User.t()) :: :ok
  def enqueue(%User{} = user) do
    if Lightning.Config.openfn_trigger_url() do
      changeset =
        new(%{
          "new_user_id" => user.id,
          "email" => user.email,
          "first_name" => user.first_name,
          "last_name" => user.last_name
        })

      Oban.insert(Lightning.Oban, changeset)
    end

    :ok
  rescue
    error ->
      Logger.warning(
        "Could not enqueue SSO registration notify: #{inspect(error)}"
      )

      :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case Lightning.Config.openfn_trigger_url() do
      url when is_binary(url) and url != "" ->
        post(url, args)

      _ ->
        Logger.info(
          "OPENFN_TRIGGER_URL not set; skipping SSO registration notify"
        )

        :ok
    end
  end

  defp post(url, args) do
    multipart = build_multipart(args)

    case Tesla.post(client(), url, multipart) do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Tesla.Env{status: status}} ->
        Logger.warning("OpenFn registration notify returned status #{status}")

        {:error, :unexpected_status}

      {:error, reason} ->
        Logger.warning("OpenFn registration notify failed: #{inspect(reason)}")

        {:error, reason}
    end
  end

  # All values are strings; fields we don't have are sent as empty strings.
  defp build_multipart(args) do
    first_name = Map.get(args, "first_name")
    last_name = Map.get(args, "last_name")

    name =
      [first_name, last_name]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")

    [
      {"type", "registration"},
      {"email", Map.get(args, "email")},
      {"name", name},
      {"firstName", first_name},
      {"lastName", last_name},
      {"new_user_id", Map.get(args, "new_user_id")},
      {"project_id", ""},
      {"contactPreference", ""},
      {"industry", ""},
      {"phone", ""},
      {"organization", ""},
      {"role", ""},
      {"websiteUrl", ""},
      {"intention", ""},
      {"adaptors", ""}
    ]
    |> Enum.reduce(Multipart.new(), fn {key, value}, mp ->
      Multipart.add_field(mp, key, to_string(value || ""))
    end)
  end

  defp client do
    Tesla.client([], adapter())
  end

  defp adapter do
    Application.get_env(:tesla, __MODULE__, [])[:adapter]
  end
end
