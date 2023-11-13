defmodule Lightning.Repo.Migrations.DropFkAttemptsWorkorders do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE attempts                                                                            
    DROP CONSTRAINT attempts_work_order_id_fkey                                                     
    """)
  end

  def down do
    execute("""
    ALTER TABLE attempts                                                                     
    ADD CONSTRAINT attempts_work_order_id_fkey                                                      
    FOREIGN KEY (work_order_id)                                                                     
    REFERENCES work_orders(id)                                                               
    ON DELETE CASCADE                                                                               
    """)
  end
end
