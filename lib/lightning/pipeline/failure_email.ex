defmodule Lightning.FailureEmail do
  @moduledoc false
  use Phoenix.Swoosh, view: Lightning.FailureNotifierView

  alias Lightning.Mailer

  defp failure_subject(%{name: name}, failure_count) do
    if failure_count < 2 do
      "#{name} failed."
    else
      "#{name} has failed #{failure_count} times in the last 24 hours."
    end
  end

  def deliver_failure_email(email, body_data) do
    email =
      new()
      |> to(email)
      |> from(
        {"Lightning", Application.get_env(:lightning, :email_addresses)[:admin]}
      )
      |> subject(
        failure_subject(%{name: body_data[:workflow_name]}, body_data[:count])
      )
      |> render_body("failure_alert.html", body_data)

    Mailer.deliver(email)
  end
end
