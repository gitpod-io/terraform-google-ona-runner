# GCP Runner Circuit Breaker Open

## Alert Description
This alert fires when a circuit breaker in the GCP Runner opens to prevent cascading failures. It monitors:
- `gitpod_gcp_compute_circuit_breaker_state == 1`
- Triggers when circuit breaker remains open for more than 5 minutes

## Impact
**High Impact:** Reduced functionality to protect system stability
- Specific operations are temporarily disabled
- Prevents cascading failures to downstream systems
- Reduced system throughput for affected operations
- May affect user experience for specific features

## Debugging Steps

### 1. Identify Which Circuit Breaker is Open
```bash
# Check circuit breaker status
curl -s http://127.0.0.1:9090/metrics | \
  grep circuit_breaker_state

# Get details about open circuit breakers
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -E "circuit.*breaker.*open"
```

### 2. Check Circuit Breaker Trip Reasons
```bash
# Check trip count and reasons
curl -s http://127.0.0.1:9090/metrics | \
  grep circuit_breaker_trips_total

# Look for trip reasons in logs
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "circuit.*breaker.*trip" | \
  awk '{print $0}' | sort | uniq -c
```

### 3. Analyze Downstream Service Health
```bash
# Check the health of services protected by circuit breaker
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -E "downstream.*error\|service.*unavailable"

# Check GCP API status for affected services
curl -s https://status.cloud.google.com/incidents.json | \
  jq '.[] | select(.end == null)'
```

### 4. Check Error Patterns Leading to Trip
```bash
# Look for error patterns before circuit breaker opened
sudo journalctl -u gitpod-runner.service --since=2h | \
  grep -B10 -A5 "circuit.*breaker.*trip"

# Check error rates for specific operations
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "error.*rate\|failure.*rate" | tail -10
```

### 5. Verify Circuit Breaker Configuration
```bash
# Check circuit breaker configuration in environment
sudo cat /var/lib/gitpod/runner.env | grep -i circuit

# Look for configuration in logs
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -E "circuit.*breaker.*config"
```
