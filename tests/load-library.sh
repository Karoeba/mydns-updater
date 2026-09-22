#!/bin/sh
# Test harness only: load production functions without starting the endless loop.
for TEST_MODULE in diagnostics health config network state runtime; do
    . "/source/lib/$TEST_MODULE.sh"
done
updater_defaults
initialize_runtime
