defmodule Lightning.MailerTest do
  use ExUnit.Case, async: true

  alias Lightning.Accounts.User

  test "correctly formats User models" do
    user = %User{email: "test@example.com", first_name: "John", last_name: "Doe"}

    assert Swoosh.Email.Recipient.format(user) ==
             {"John Doe", "test@example.com"}
  end
end
