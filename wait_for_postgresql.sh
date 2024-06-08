# Based on https://gist.github.com/nicerobot/1136dcfba6ce3da67ce3ded5101a4078?permalink_comment_id=2759218#gistcomment-2759218
retry() {
  max_attempts="$1"; shift
  seconds="$1"; shift
  cmd="$@"
  attempt_num=1

  until $cmd
  do
    if [ $attempt_num -eq $max_attempts ]
    then
      echo "Attempt $attempt_num failed and there are no more attempts left!"
      return 1
    else
      echo "Attempt $attempt_num failed! Trying again in $seconds seconds..."
      attempt_num=`expr "$attempt_num" + 1`
      sleep "$seconds"
    fi
  done
}

retry 5 1 pg_isready --dbname=$DATABASE_URL

echo >&2 "$(date +%Y%m%dt%H%M%S) Postgres is up - executing command"
