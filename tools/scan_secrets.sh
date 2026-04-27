#!/bin/bash
# tools/scan_secrets.sh
# Called by PostToolUse hook after every file edit.
# Usage: tools/scan_secrets.sh <filepath>

FILE="$1"

if [ -z "$FILE" ]; then
  echo "Usage: scan_secrets.sh <filepath>"
  exit 1
fi

# Patterns that must never appear in source
PATTERNS=(
  "AIza[0-9A-Za-z\-_]{35}"         # Firebase API key
  "serviceAccountKey"               # Service account JSON reference
  "AAAA[A-Za-z0-9_-]{7}:"          # FCM server key
  "\"private_key\""                 # GCP private key in JSON
  "client_secret"
  "password\s*=\s*['\"][^'\"]{6}"  # Hardcoded password
)

FOUND=0
for PATTERN in "${PATTERNS[@]}"; do
  if grep -qP "$PATTERN" "$FILE" 2>/dev/null; then
    echo "SECRET SCAN FAIL: Potential secret found in $FILE (pattern: $PATTERN)"
    FOUND=1
  fi
done

if [ $FOUND -eq 1 ]; then
  exit 1
fi

exit 0
