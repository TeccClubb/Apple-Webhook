# Apple App Store Server Notification Handling

## Overview

This document explains how our system handles Apple App Store Server Notifications for subscription management.

## Notification Flow

1. Apple sends a signed JWT (JWS) notification to our webhook endpoint
2. The system verifies the signature using Apple's public keys
3. The payload is decoded and processed
4. The subscription database is updated based on the notification type

## Key Components

### 1. JWS Verification (`app/core/apple_jws.py`)

The `AppleJWSVerifier` class handles verification of Apple's signed JWS tokens with several fallback mechanisms:

- **Standard Verification**: Uses the key ID (kid) in the header to select the appropriate public key
- **Multi-Key Verification**: When no key ID is provided, tries verification with all available keys
- **Direct Payload Extraction**: For notifications that can't be verified through standard methods
- **Key Type Detection**: Automatically selects the proper algorithm based on key type (RSA vs EC)

### 2. Webhook Handler (`app/api/routes/apple_webhook.py`)

The webhook endpoint receives notifications and:
- Attempts to verify the JWS signature
- Falls back to direct payload extraction if verification fails
- Passes the notification to the processor
- Always returns 200 OK to Apple (as required by their API)

### 3. Notification Processor (`app/services/notification_processor.py`)

The processor handles business logic:
- Extracts transaction and renewal info from the notification
- Updates subscription status based on notification type
- Records notification history
- Creates or updates subscriptions

## Troubleshooting

### Common Issues

1. **Signature Verification Fails**:
   - Check if the notification has a key ID in the header
   - Ensure Apple's public keys are being fetched correctly
   - Look for algorithm mismatch (EC vs RSA keys)

2. **Missing Transaction Info**:
   - Check if payload extraction is working
   - Verify the notification format (v1 vs v2)
   - Check logs for specific extraction errors

3. **Subscription Not Updated**:
   - Verify the notification type is being correctly identified
   - Check if originalTransactionId is being extracted
   - Look for database errors in logs

### Verification Script

Use the `verify_changes.sh` script to ensure all necessary changes are correctly implemented.

### Testing

To test notifications:
1. Run `./monitor_notifications.sh` and select option 3
2. Make a purchase in the app
3. Watch the logs for notification processing
4. Verify that the subscription is created/updated in the database

## Recent Updates

- Added support for EC (Elliptic Curve) keys in addition to RSA keys
- Implemented direct payload extraction for notifications that can't be verified
- Added more robust error handling and fallback mechanisms
