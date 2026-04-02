# GCP Runner High Goroutine Count

## Alert Description
This alert fires when the GCP Runner has an unusually high number of active goroutines. It monitors:
- `go_goroutines > 1000`
- Triggers when goroutine count exceeds 1000 for more than 15 minutes

## Impact
**Info Impact:** Potential performance issues and resource leaks
- Increased memory usage due to goroutine stack overhead
- Potential goroutine leaks affecting long-term stability
- Reduced performance due to scheduler overhead
- Risk of hitting system limits for threads/processes

## Debugging Steps

### 1. Check Current Goroutine Count
```bash
# Get current goroutine count
curl -s http://127.0.0.1:9090/metrics | \
  grep go_goroutines

# Check goroutine-related metrics
curl -s http://127.0.0.1:9090/metrics | \
  grep -E "goroutine|go_threads"
```

### 2. Analyze Goroutine Growth Patterns
```bash
# Look for goroutine-related messages in logs
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "(goroutine|go.*routine|concurrent)"

# Check for goroutine creation patterns
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "(start.*goroutine|launch.*goroutine|spawn)"
```

### 3. Check for Blocking Operations
```bash
# Look for operations that might block goroutines
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "(block|wait|timeout|deadlock)"

# Check for long-running operations
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "(duration|elapsed|took.*seconds)" | \
  awk '$NF > 10' # Operations taking more than 10 seconds
```

### 4. Analyze Workload Patterns
```bash
# Check concurrent operations
curl -s http://127.0.0.1:9090/metrics | \
  grep -E "workqueue_depth|active.*operations"

# Look for high concurrency in logs
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -E "(concurrent|parallel|batch)" | wc -l
```

### 5. Check for Resource Contention
```bash
# Look for mutex contention or channel blocking
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "(mutex|channel|lock|contention)"

# Check for API rate limiting that might cause goroutine buildup
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "(rate.*limit|throttl|429)"
```

### 6. Examine Error Patterns
```bash
# Check for errors that might prevent goroutine cleanup
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "(error|failed|panic)" | \
  grep -E "(goroutine|concurrent|async)"
```

## Advanced Debugging

### Goroutine Profiling
1. **Enable goroutine profiling:**
   ```bash
   # Port forward to access pprof
   # Access pprof directly from the runner instance
   gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
     --command="curl -s http://127.0.0.1:9090/debug/pprof/goroutine?debug=1"
   
   # Get goroutine profile
   curl http://127.0.0.1:6060/debug/pprof/goroutine > goroutine.prof
   
   # Analyze with go tool
   go tool pprof goroutine.prof
   ```

2. **Get goroutine stack traces:**
   ```bash
   # Get current goroutine stacks
   curl http://127.0.0.1:6060/debug/pprof/goroutine?debug=1 > goroutine-stacks.txt
   
   # Analyze stack traces for patterns
   grep -E "goroutine [0-9]+" goroutine-stacks.txt | wc -l
   ```

### Runtime Analysis
1. **Check runtime metrics:**
   ```bash
   # Get detailed runtime information
   curl http://127.0.0.1:6060/debug/pprof/runtime > runtime.prof
   
   # Check scheduler information
   curl http://127.0.0.1:6060/debug/vars | jq '.runtime'
   ```
