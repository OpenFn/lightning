#!/bin/sh

/app/wait_for_postgresql.sh
/app/bin/migrate
/app/bin/server
