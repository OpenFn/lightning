defmodule LightningWeb.BackupCodesController do
  use LightningWeb, :controller
  alias Lightning.Accounts

  def print(conn, _params) do
    codes = Accounts.list_user_backup_codes(conn.assigns.current_user)

    render(conn, "print.html",
      backup_codes: codes,
      page_title: "Print Backup Codes"
    )
  end
end
