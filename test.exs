import Ecto.Query
alias Lightning.Repo
alias Lightning.Jobs.Job

user = %Lightning.Accounts.User{id: "c5f5583e-3633-4479-9a3b-47fb599d3af7"}

# Repo.all(Ecto.assoc(%Lightning.Accounts.User{id: "c5f5583e-3633-4479-9a3b-47fb599d3af7"}, :project_users))
from(j in Job,
  join: pc in subquery(Ecto.assoc(user, [:credentials, :project_credentials])),
  on: pc.id == j.project_credential_id
)
|> Repo.update_all(set: [project_credential_id: nil])
