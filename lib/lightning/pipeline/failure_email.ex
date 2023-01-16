defmodule Lightning.FailureEmail do
  @moduledoc false
  use Phoenix.Swoosh, view: Lightning.FailureNotifierView

  alias Lightning.Mailer

  defp failure_subject(%{name: name}, failure_count) do
    "#{failure_count}th failure for workflow #{name}"
  end

  def deliver_failure_email(recipients, body_data) do
    email =
      new()
      |> to(recipients)
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
