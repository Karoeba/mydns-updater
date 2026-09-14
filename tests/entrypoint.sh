#!/bin/sh
umask 022
{ sh /suite/run-tests.sh && sh /suite/test-diagnostics.sh && sh /suite/test-split-config.sh && sh /suite/test-healthcheck.sh; } > /reports/test.log 2>&1
result=$?
cat /reports/test.log
if [ "$result" -eq 0 ]; then
    echo 'ALL TESTS PASSED' > /reports/result.txt
else
    echo 'TESTS FAILED - see test.log' > /reports/result.txt
fi
exit "$result"
