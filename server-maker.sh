#!/bin/bash

source .env # COMPARTMENT_ID, SUBNET_ID, WEBHOOK_URL, and DEVICE_NAME sourced from .env
IMAGE_ID="ocid1.image.oc1.us-chicago-1.aaaaaaaaoo4nzxuu6w5aty4ap6jjnfxebwwxhlfxj5gkzmtgtnsw24eksmia"
SSH_KEY_FILE="$HOME/.ssh/oci-server-backup.pub"
DISPLAY_NAME="server"
RETRY_DELAY=60
AVAILABILITY_DOMAINS=(
  "ibxy:US-CHICAGO-1-AD-1"
  "ibxy:US-CHICAGO-1-AD-2"
  "ibxy:US-CHICAGO-1-AD-3"
)

curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"content\": \"Starting to log from: $DEVICE_NAME on $(TZ='America/New_York' date '+%A, %b %d - %H:%M:%S')\"}" \
  "$WEBHOOK_URL"

attempt=0

while true; do
  attempt=$((attempt + 1))
  echo "[$(TZ='America/New_York' date '+%A, %b %d - %H:%M:%S')] Attempt #$attempt"

  echo "[$(TZ='America/New_York' date '+%A, %b %d - %H:%M:%S')] Attempt #$attempt" >> error.txt
  curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"content\": \"Attempt #$attempt\"}" \
    "$WEBHOOK_URL"

  for AD in "${AVAILABILITY_DOMAINS[@]}"; do
    echo "Trying $AD..."

    RESULT=$(oci compute instance launch \
      --availability-domain "$AD" \
      --compartment-id "$COMPARTMENT_ID" \
      --shape "VM.Standard.A1.Flex" \
      --shape-config '{"ocpus": 3, "memoryInGBs": 20}' \
      --subnet-id "$SUBNET_ID" \
      --image-id "$IMAGE_ID" \
      --display-name "$DISPLAY_NAME" \
      --assign-public-ip true \
      --ssh-authorized-keys-file "$SSH_KEY_FILE" \
      2>&1)

    STATUS=$(echo "$RESULT" | grep -oP '"status":\s*\K[0-9]+')
    CODE=$(echo "$RESULT" | grep -oP '"code":\s*"\K[^"]+')
    MESSAGE=$(echo "$RESULT" | grep -oP '"message":\s*"\K[^"]+')

    if echo "$RESULT" | grep -q '"lifecycle-state"'; then
      echo "[$(TZ='America/New_York' date '+%A, %b %d - %H:%M:%S')] Attempt #$attempt" >> success.txt

      curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"content\": \"<@1005536927388291133> ✅ Success $AD — $STATUS $CODE: $MESSAGE\"}" \
        "$WEBHOOK_URL"

      echo -e "✅ Success $AD:\n$RESULT" >> success.txt
      exit 0
    else
      curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"content\": \"❌ Failed $AD — $STATUS $CODE: $MESSAGE\"}" \
        "$WEBHOOK_URL"

      echo -e "❌ Failed $AD:\n$RESULT\n" >> error.txt
    fi
  done

  echo "All 3 ADs failed. Waiting ${RETRY_DELAY}s..."
  sleep $RETRY_DELAY
done
