defmodule Lightning.ProjectsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects
  alias Lightning.Projects.Project

  describe "import project.yaml" do
    test "import_project project and workflows if given valid object map" do
      data = %{
        name: "myproject",
        workflows: [
          %{
            name: "workflow1",
            jobs: [
              %{
                name: "job11",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "credential",
                body: "> fn(state => state)"
              },
              %{
                name: "job12",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "credential",
                body: "> fn(state => state)"
              }
            ]
          },
          %{
            name: "workflow2",
            jobs: [
              %{
                name: "job21",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "credential",
                body: "> fn(state => state)"
              },
              %{
                name: "job22",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "credential",
                body: "> fn(state => state)"
              }
            ]
          }
        ]
      }

      {:ok, %Project{}} = Projects.import_project(data)

      # project = Repo.preload(project, [workflows: [jobs: [:trigger]]])
    end
  end
end
