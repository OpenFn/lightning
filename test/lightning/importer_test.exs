defmodule Lightning.ProjectsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects
  # alias Lightning.Projects.Project
  import Lightning.AccountsFixtures

  describe "import project.yaml" do
    test "import_project project and workflows if given valid object map" do
      user = user_fixture()

      project_data = %{
        name: "myproject",
        credentials: [
          %{
            key: "abc",
            name: "first credential",
            schema: "raw",
            body: %{"password" => "xxx"}
          },
          %{
            key: "xyz",
            name: "MY credential",
            schema: "raw",
            body: %{"password" => "xxx"}
          }
        ],
        workflows: [
          %{
            key: "workflow1",
            name: "workflow1",
            jobs: [
              %{
                name: "job1",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "xyz",
                body: "> fn(state => state)"
              },
              %{
                name: "job2",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "abc",
                body: "> fn(state => state)"
              }
            ]
          },
          %{
            name: "workflow2",
            jobs: [
              %{
                name: "job1",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "xyz",
                body: "> fn(state => state)"
              },
              %{
                name: "job2",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "xyz",
                body: "> fn(state => state)"
              }
            ]
          }
        ]
      }

      Projects.import_project(project_data, user) |> IO.inspect()

      # project = Repo.preload(project, workflows: [jobs: [:trigger, :credential]])

      # assert project.name == project_data.name
      # assert length(project.workflows) == length(project_data.workflows)

      # %{workflows: [expected_w1, expected_w2]} = project_data

      # workflow1 = Enum.find(project.workflows, fn w -> w.name == "workflow1" end)
      # workflow2 = Enum.find(project.workflows, fn w -> w.name == "workflow2" end)

      # assert_workflow(workflow1, expected_w1)
      # assert_workflow(workflow2, expected_w2)
    end
  end

  # defp assert_workflow(expected, actual) do
  #   %{jobs: [expected_j1, expected_j2]} = expected

  #   job1 = Enum.find(actual.jobs, fn j -> j.name == "job1" end)
  #   job2 = Enum.find(actual.jobs, fn j -> j.name == "job2" end)

  #   refute is_nil(actual)
  #   assert expected.name == actual.name

  #   assert_job(job1, expected_j1)
  #   assert_job(job2, expected_j2)
  # end

  # defp assert_job(expected, actual) do
  #   refute is_nil(actual)
  #   assert expected.name == actual.name
  #   assert expected.adaptor == actual.adaptor
  #   # assert expected.credential.body == actual.credential
  #   assert expected.body == actual.body
  #   assert expected.trigger.type == actual.trigger.type

  # end
end
