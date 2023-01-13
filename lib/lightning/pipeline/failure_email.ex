defmodule Lightning.FailureEmail do
  use Phoenix.Swoosh, view: Sample.EmailView, layout: {Sample.LayoutView, :email}



  defp failure_subject(%{name: name}, failure_count) do
    "#{failure_count}th failure for workflow #{name}"
  end

  defp failure_body do
    "body"
  end

  def deliver_failure_email(users, _run) do
    recipients = Enum.map(users, & &1.email)

    email =
      new()
      |> to(recipients)
      |> from({"Lightning", admin()})
      |> subject(failure_subject(%{name: "workflow"}, 1))
      |> render_body("welcome.html", %{username: user.username})

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end

  end

end
