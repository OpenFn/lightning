defmodule Lightning.AuditingTest do
  use Lightning.DataCase, async: true

  alias Lightning.Auditing
  import Lightning.CredentialsFixtures

  describe "list_all/1" do
    test "" do
      %{id: credential_id} = credential_fixture()

      %{entries: [entry]} = Auditing.list_all()

      assert entry.row_id == credential_id
    end
  end
end
