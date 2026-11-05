defmodule LightningWeb.API.ErrorsTest do
  use Lightning.DataCase, async: true

  import Lightning.AdaptorTestHelpers
  import Lightning.Factories
  import Mox, only: [stub: 3]

  alias Lightning.Accounts.User
  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectUser
  alias Lightning.Projects.Provisioner
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Workflow
  alias LightningWeb.API.Errors
  alias LightningWeb.API.Problem

  @adaptor "@openfn/language-common@latest"

  setup :isolated_adaptors

  setup do
    stub(MockUsageLimiter, :limit_action, fn _, _ -> :ok end)
    :ok
  end

  defp job(id, name) do
    %{"id" => id, "name" => name, "adaptor" => @adaptor, "body" => "fn(s => s)"}
  end

  defp provision(jobs) do
    workflow = %{"id" => Ecto.UUID.generate(), "name" => "w", "jobs" => jobs}
    %{"id" => Ecto.UUID.generate(), "name" => "p", "workflows" => [workflow]}
  end

  @one_owner "Every project must have exactly one owner."

  defp project_with(name \\ "members", roles) do
    Project.project_with_users_changeset(%Project{}, %{
      "name" => name,
      "project_users" =>
        for(
          role <- roles,
          do: %{"user_id" => insert(:user).id, "role" => "#{role}"}
        )
    })
  end

  defp entry_at(pointer, code, detail),
    do: %{pointer: pointer, code: code, detail: detail}

  defp decode_pointer("#" <> path) do
    path
    |> URI.decode()
    |> String.split("/", trim: true)
    |> Enum.map(fn key ->
      key |> String.replace("~1", "/") |> String.replace("~0", "~")
    end)
  end

  describe "where an entry is placed" do
    setup do
      seed_ready_catalogue()
      ensure_adaptor(@adaptor)
      :ok
    end

    test "counts a provisioned child's position among the items the request sent, with one marked delete: true mid-list" do
      [kept, deleted, left_out, blank, last] =
        for _ <- 1..5, do: Ecto.UUID.generate()

      document =
        provision([
          job(kept, "kept"),
          job(deleted, "deleted"),
          job(left_out, "left out")
        ])

      {:ok, project} =
        Provisioner.import_document(%Project{}, insert(:user), document)

      changeset =
        Provisioner.parse_document(
          project,
          put_in(document, ["workflows", Access.at(0), "jobs"], [
            job(kept, "kept"),
            %{"id" => deleted, "delete" => true},
            job(blank, ""),
            job(last, "last")
          ])
        )

      assert Errors.from_changeset(changeset) == [
               entry_at(
                 "#/workflows/0/jobs/2/name",
                 :required,
                 "job name can't be blank"
               )
             ]
    end

    test "keeps a list's own error and its items' errors, under the names the request used" do
      changeset = project_with([:editor, :boss])

      assert Errors.from_changeset(changeset, %{
               project_users: :members,
               owner: :members
             }) == [
               entry_at("#/members", :one_owner, @one_owner),
               entry_at("#/members/1/role", :not_allowed, "is invalid")
             ]
    end

    test "names the path segment for a top-level key the request sent in its path, and only there" do
      changeset = project_with("", [:boss])

      assert Errors.from_changeset(changeset, %{}, path: [:name, :role]) == [
               %{path: "name", code: :required, detail: "can't be blank"},
               entry_at("#/owner", :one_owner, @one_owner),
               entry_at("#/project_users/0/role", :not_allowed, "is invalid")
             ]
    end

    test "points a duplicate at the later of two provisioned children with one id, naming the earlier" do
      id = Ecto.UUID.generate()
      document = provision([job(id, "first"), job(id, "second")])
      changeset = Provisioner.parse_document(%Project{}, document)

      assert Errors.from_changeset(changeset) == [
               entry_at(
                 "#/workflows/0/jobs/1/id",
                 :duplicate,
                 "names the same id as #/workflows/0/jobs/0"
               )
             ]
    end

    test "places an error at the keys and positions its key: option lists" do
      changeset =
        Ecto.Changeset.add_error(
          Ecto.Changeset.change({%{}, %{bodies: {:array, :map}}}),
          :bodies,
          "can't be blank",
          code: :required,
          key: [:credential_bodies, 1, :body, "host"]
        )

      assert Errors.from_changeset(changeset) == [
               entry_at(
                 "#/credential_bodies/1/body/host",
                 :required,
                 "can't be blank"
               )
             ]
    end
  end

  describe "which code an Ecto error gets" do
    test "a value outside an enum's set is not_allowed, and a failed cast to any other type is type" do
      user_id = Ecto.UUID.generate()

      for {changeset, entry} <- [
            {ProjectUser.changeset(%ProjectUser{}, %{
               "user_id" => user_id,
               "role" => "boss"
             }), entry_at("#/role", :not_allowed, "is invalid")},
            {Project.changeset(%Project{}, %{
               "name" => "enum",
               "retention_policy" => "keep_forever"
             }), entry_at("#/retention_policy", :not_allowed, "is invalid")},
            {Project.changeset(%Project{}, %{
               "name" => "type",
               "concurrency" => "x"
             }), entry_at("#/concurrency", :type, "is invalid")}
          ] do
        assert Errors.from_changeset(changeset) == [entry]
      end
    end

    test "codes an assoc_constraint error not_found at the foreign key the request sent" do
      {:error, changeset} =
        %Workflow{}
        |> Workflow.changeset(%{
          name: "orphan",
          project_id: Ecto.UUID.generate()
        })
        |> Repo.insert()

      assert Errors.from_changeset(changeset) == [
               entry_at("#/project_id", :not_found, "does not exist")
             ]

      assert [%{pointer: "#/parent"}] =
               Errors.from_changeset(changeset, %{project: :parent})
    end

    test "raises on an error with no code" do
      changeset =
        Ecto.Changeset.add_error(
          Ecto.Changeset.change({%{}, %{id: :binary_id}}),
          :id,
          "is not a UUID"
        )

      assert_raise ArgumentError,
                   ~r/"is not a UUID" at \[:id\] has no code/,
                   fn -> Errors.from_changeset(changeset) end
    end
  end

  describe "pointer/1" do
    test "escapes a key holding / and ~ so a client decodes it back, and is # alone for the whole body" do
      key = "a/b~c d%é"
      pointer = Errors.pointer([:workflows, 0, key])

      assert pointer == "#/workflows/0/a~1b~0c%20d%25%C3%A9"
      assert decode_pointer(pointer) == ["workflows", "0", key]
      assert Errors.pointer([]) == "#"
    end
  end

  describe "which status a refused changeset gets" do
    test "answers 503 not_ready, with no entries, when the adaptor catalogue isn't loaded" do
      changeset =
        Job.changeset(%Job{}, %{
          name: "waiting",
          adaptor: "@openfn/language-unseeded@1.0.0",
          body: "fn(s => s)"
        })

      assert Errors.problem(changeset) == %Problem{
               status: 503,
               code: :not_ready,
               headers: [{"retry-after", "5"}]
             }
    end

    test "answers 500 internal, with no entries, when stored files couldn't be deleted" do
      changeset =
        Ecto.Changeset.add_error(
          Ecto.Changeset.change(%Project{}),
          :project_files,
          "1 stored file(s) could not be deleted from storage",
          code: :storage_failed
        )

      {problem, log} =
        ExUnit.CaptureLog.with_log(fn -> Errors.problem(changeset) end)

      assert problem == %Problem{status: 500, code: :internal}
      assert log =~ "could not delete stored files"
    end

    test "answers 402 when every error is a plan limit" do
      changeset =
        %Project{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:id, "would exceed a limit of your plan",
          code: :exceeds_limit
        )

      assert Errors.problem(changeset) ==
               %Problem{
                 status: 402,
                 code: :exceeds_limit,
                 errors: [
                   entry_at(
                     "#/id",
                     :exceeds_limit,
                     "would exceed a limit of your plan"
                   )
                 ]
               }
    end

    test "answers 422 invalid with a taken entry when the only error is taken, whether a unique constraint or an application check found it" do
      seed_ready_catalogue()
      ensure_adaptor(@adaptor)
      job = insert(:job, name: "taken", adaptor: @adaptor)

      {:error, constraint} =
        %Job{}
        |> Job.changeset(%{
          name: "taken",
          adaptor: @adaptor,
          body: "fn(s => s)",
          workflow_id: job.workflow_id
        })
        |> Repo.insert()

      check =
        User.changeset(%User{}, %{
          first_name: "Ada",
          last_name: "Lovelace",
          email: insert(:user).email,
          password: "a long enough password"
        })

      for {changeset, entry} <- [
            {constraint,
             entry_at("#/name", :taken, "job name has already been taken")},
            {check, entry_at("#/email", :taken, "has already been taken")}
          ] do
        assert Errors.problem(changeset) ==
                 %Problem{status: 422, code: :invalid, errors: [entry]}
      end
    end
  end

  describe "refuse/1 and parameters/1" do
    test "passes no entries and refuses any as one 422 invalid" do
      entry = entry_at("#/name", :required, "can't be blank")

      assert Errors.refuse([]) == :ok

      assert Errors.refuse([entry]) ==
               {:error, %Problem{status: 422, code: :invalid, errors: [entry]}}
    end

    test "parameters/1 raises on a changeset with no errors" do
      changeset = Ecto.Changeset.cast({%{}, %{state: :string}}, %{}, [:state])

      assert_raise ArgumentError, fn -> Errors.parameters(changeset) end
    end
  end
end
