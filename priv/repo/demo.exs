# Script for
#
#     mix run priv/repo/demo.exs
#
# Deletes everything in the database including the superuser and creates a set
# of publicly available users for a demo site via a mix task.

Lightning.SetupUtils.tear_down(destroy_super: true)
Lightning.SetupUtils.setup_demo(create_super: true)
