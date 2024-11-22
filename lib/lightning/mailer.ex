defmodule Lightning.Mailer do
  @moduledoc false
  use Swoosh.Mailer, otp_app: :lightning

  defimpl Swoosh.Email.Recipient, for: Lightning.Accounts.User do
    def format(%Lightning.Accounts.User{} = user) do
      {[user.first_name, user.last_name] |> Enum.join(" ") |> String.trim(),
       user.email}
    end
  end

  defmodule EventHandler do
    @moduledoc false
    require Logger

    def handle_event([:swoosh, :deliver, :stop], _, metadata, _) do
      case metadata do
        %{error: error} ->
          Logger.error("Failed to send email: #{inspect(error)}")

        %{result: result} ->
          Logger.info("Email sent: #{inspect(result)}")

        _ ->
          :ok
      end
    end
  end
end
