#!/bin/sh

/app/wait_for_postgresql.sh
/app/bin/migrate
/app/bin/lightning eval 'Lightning.KafkaTesting.Utils.seed_database()'
/app/bin/server
