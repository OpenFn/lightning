# Script for
#
#     mix run priv/repo/demo.exs
#
# Deletes everything in the database including the superuser and creates a set
# of publicly available users for a demo site via a mix task.

Lightning.Demo.reset_demo
