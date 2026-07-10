
## Runtime Health

Generate machine-readable health data:

    scripts/runtime.sh json-summary

Display the current health status:

    scripts/runtime.sh health-status

Runtime health JSON:

    reports/summary/latest.json

Health levels:

- 90–100: HEALTHY
- 70–89: WARNING
- 0–69: CRITICAL
