# GCP Runner PubSub Backlog

## Alert Description
This alert fires when the GCP Runner PubSub subscription accumulates too many unprocessed messages. It monitors:
- `gitpod_gcp_pubsub_subscription_backlog_messages > 1000`
- Triggers when message backlog exceeds 1000 messages for 10 minutes

## Impact
**High Impact:** Delayed event processing and state inconsistencies
- Delayed environment state updates
- Eventual consistency issues
- Potential data loss if messages expire
- Degraded real-time responsiveness
- Cascading effects on dependent systems

## Prerequisites

Set up the required environment variables before running debugging commands:

```bash
# Set these variables based on your Terraform deployment
export PROJECT_ID="your-gcp-project-id"
export REGION="your-region"  # e.g., us-central1
export RUNNER_ID="your-runner-id"  # The runner ID from your Terraform configuration

# Get runner instance details
INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances ${RUNNER_ID}-runner-mig \
  --region=${REGION} --project=${PROJECT_ID} --format="value(instance)" | head -1)

ZONE=$(gcloud compute instances describe $INSTANCE_NAME \
  --project=${PROJECT_ID} --format="value(zone)" | sed 's|.*/||')

echo "Instance: $INSTANCE_NAME, Zone: $ZONE"
```

## Debugging Steps

### 1. Check Backlog Size and Growth
```bash
# Check current backlog metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep pubsub_subscription_backlog_messages"

# Monitor backlog growth over time
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -E 'backlog.*messages' | tail -10"
```

### 2. Verify Subscriber Health
```bash
# Check PubSub subscriber status
sudo journalctl -u gitpod-runner.service --since="10 minutes ago" | \
  grep -E "pubsub.*error\|subscription.*error"

# Check connection health
curl -s http://127.0.0.1:9090/metrics | \
  grep pubsub_connection_health
```

### 3. Analyze Message Processing Rate
```bash
# Check message processing metrics
curl -s http://127.0.0.1:9090/metrics | \
  grep -E "pubsub_messages_total|message_processing_duration"

# Look for processing patterns in logs
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -E "pubsub.*processed\|message.*ack" | tail -20
```

### 4. Check for Processing Errors
```bash
# Look for message processing failures
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -E "pubsub.*nack\|message.*failed\|message.*error"

# Check error patterns
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "pubsub.*error" | \
  awk '{print $0}' | sort | uniq -c | sort -nr
```

### 5. Verify Subscription Configuration
```bash
# Check subscription settings
gcloud pubsub subscriptions describe YOUR_SUBSCRIPTION

# Check topic publishing rate
gcloud pubsub topics list-subscriptions YOUR_TOPIC
```

### 6. Check Resource Constraints
```bash
# Check if runner container is resource constrained
sudo docker stats --no-stream gitpod-runner

# Check container resource usage
sudo docker exec gitpod-runner ps aux
sudo docker exec gitpod-runner free -h
```
