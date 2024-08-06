defmodule Lightning.Mailer do
  @moduledoc false
  use Swoosh.Mailer, otp_app: :lightning

  defimpl Swoosh.Email.Recipient, for: Lightning.Accounts.User do
    def format(%Lightning.Accounts.User{} = user) do
      {user.email, "#{user.first_name} #{user.last_name}"}
    end
  end
end
