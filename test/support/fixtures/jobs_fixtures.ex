defmodule Lightning.JobsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Jobs` context.
  """

  @doc """
  Generate a job.
  """
  def job_fixture(attrs \\ %{}) do
    {:ok, job} =
      attrs
      |> Enum.into(%{
        body: "some body",
        enabled: true,
        name: "some name",
        adaptor: "@openfn/language-common",
        trigger: %{},
        credential: %{name: "my credential", body: %{"credential" => "body"}}
      })
      |> Lightning.Jobs.create_job()

    job
  end
end
