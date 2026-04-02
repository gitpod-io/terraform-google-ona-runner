# GCP Runner High Memory Usage

## Alert Description
This alert fires when the GCP Runner process consumes excessive memory. It monitors:
- `(process_resident_memory_bytes / (1024^3)) > 0.8`
- Triggers when memory usage exceeds 80% of allocated memory for 15 minutes

## Impact
**Info Impact:** Potential performance degradation
- Increased garbage collection frequency
- Slower response times
- Risk of out-of-memory (OOM) kills
- Potential service instability if memory exhaustion occurs

## Debugging Steps

### 1. Check Current Memory Usage
```bash
# Check process memory usage
ps aux | grep gcp-runner | awk '{print $2, $4, $6, $11}' | sort -k3 -nr

# Get detailed memory metrics
curl -s http://127.0.0.1:9090/metrics | \
  grep -E "process_resident_memory_bytes|go_memstats"

# Check system memory usage
free -h
cat /proc/meminfo | grep -E "(MemTotal|MemAvailable|MemFree)"
```

### 2. Analyze Memory Growth Patterns
```bash
# Look for memory-related messages in logs
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "(memory|gc|heap|oom)"

# Check for memory allocation patterns
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "(alloc|malloc|new)"
```

### 3. Check for Memory Leaks
```bash
# Monitor goroutine count (potential leak indicator)
curl -s http://127.0.0.1:9090/metrics | \
  grep go_goroutines

# Check for increasing object counts
curl -s http://127.0.0.1:9090/metrics | \
  grep -E "go_memstats.*objects|go_memstats.*alloc"

# Look for leak indicators in logs
sudo journalctl -u gitpod-runner.service --since=2h | \
  grep -E "(leak|growing|increasing.*memory)"
```

### 4. Analyze Garbage Collection
```bash
# Check GC metrics
curl -s http://127.0.0.1:9090/metrics | \
  grep -E "go_gc_duration_seconds|go_memstats_gc"

# Look for GC pressure in logs
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "(gc|garbage.*collect)"
```

### 5. Check Workload Patterns
```bash
# Check for high workload that might cause memory usage
curl -s http://127.0.0.1:9090/metrics | \
  grep -E "workqueue_depth|active_goroutines"

# Look for concurrent operations
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -E "(concurrent|parallel|batch)" | wc -l
```

### 6. Examine Cache Usage
```bash
# Check cache metrics if available
curl -s http://127.0.0.1:9090/metrics | \
  grep -E "cache.*size|cache.*entries"

# Look for cache-related messages
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "(cache|buffer|store)"
```
