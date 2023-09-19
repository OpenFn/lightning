defmodule Lightning.AuditingTest do
  use Lightning.DataCase, async: true

  alias Lightning.Auditing
  import Lightning.CredentialsFixtures

  describe "list_all/1" do
    test "When a credential is created, it should appear in the audit trail" do
      %{id: credential_id} = credential_fixture()

      %{entries: [entry]} = Auditing.list_all()

      assert entry.item_id == credential_id
    end
  end
end
