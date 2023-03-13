defmodule Lightning.FailureEmail do
  @moduledoc false
  use Phoenix.Swoosh, view: Lightning.FailureNotifierView

  import Lightning.Helpers, only: [ms_to_human: 1]

  alias Lightning.Mailer

  defp failure_subject(%{name: name}, failure_count, time_scale) do
    if failure_count < 2 do
      "\"#{name}\" failed."
    else
      "\"#{name}\" has failed #{failure_count} times in the last #{ms_to_human(time_scale)}."
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
        failure_subject(
          %{name: body_data[:workflow_name]},
          body_data[:count],
          body_data[:time_scale]
        )
      )
      |> render_body(
        "failure_alert.html",
        Map.put(
          body_data,
          :duration,
          ms_to_human(body_data[:time_scale])
        )
      )

    Mailer.deliver(email)
  end
end
