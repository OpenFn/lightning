We want to start working on issue #$ARGUMENTS, use the gh cli to fetch the issue
information, and write a new markdown file under the .context directory.

If there are any referenced issues, get the title of those issues and turn those
references into markdown links in the format:
[#<number> <title of issue>](<github url>)

Write into a file .context/shared/issues/issue-<number>-<short-hypenated-name>.md
