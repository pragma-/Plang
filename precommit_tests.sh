git stash -q --keep-index
perl test/unit_tests.pl
RESULT=$?
git stash pop -q
exit $RESULT
