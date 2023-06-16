defmodule Lightning.Factories do
  use ExMachina.Ecto, repo: Lightning.Repo

  def project_factory do
    %Lightning.Projects.Project{}
  end

  def workflow_factory do
    %Lightning.Workflows.Workflow{project: build(:project)}
  end

  def job_factory do
    %Lightning.Jobs.Job{
      workflow: build(:workflow),
      body: "console.log('hello!');"
    }
  end

  def trigger_factory do
    %Lightning.Jobs.Trigger{workflow: build(:workflow)}
  end

  def edge_factory do
    %Lightning.Workflows.Edge{workflow: build(:workflow)}
  end

  def dataclip_factory do
    %Lightning.Invocation.Dataclip{project: build(:project)}
  end

  def run_factory do
    %Lightning.Invocation.Run{
      job: build(:job),
      input_dataclip: build(:dataclip)
    }
  end

  def attempt_factory do
    %Lightning.Attempt{}
  end

  def reason_factory do
    %Lightning.InvocationReason{}
  end

  def credential_factory do
    %Lightning.Credentials.Credential{}
  end

  def project_credential_factory do
    %Lightning.Projects.ProjectCredential{
      project: build(:project),
      credential: build(:credential)
    }
  end

  def workorder_factory do
    %Lightning.WorkOrder{workflow: build(:workflow)}
  end

  def user_factory do
    %Lightning.Accounts.User{
      email: sequence(:email, &"email-#{&1}@example.com"),
      password: "hello world!",
      first_name: "anna",
      hashed_password: Bcrypt.hash_pwd_salt("hello world!")
    }
  end
end
