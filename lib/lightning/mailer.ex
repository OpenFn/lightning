defmodule Lightning.Mailer do
  @moduledoc false
  use Swoosh.Mailer, otp_app: :lightning

  defimpl Swoosh.Email.Recipient, for: Lightning.Accounts.User do
    def format(%Lightning.Accounts.User{} = user) do
      {[user.first_name, user.last_name] |> Enum.join(" ") |> String.trim(),
       user.email}
    end
  end
end
