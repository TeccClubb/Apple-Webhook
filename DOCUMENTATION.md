# Apple Subscription Service Documentation

## Overview

This service handles Apple App Store Server Notifications (v2) for subscription events, allowing your app to respond to events such as subscriptions, renewals, expirations, and refunds. It provides a webhook endpoint that Apple can send notifications to, stores these events in a database, and offers REST APIs for querying subscription status.

## Key Features

1. **Webhook Endpoint**: Receives and validates Apple App Store server notifications
2. **JWS Signature Verification**: Validates the authenticity of Apple's notifications
3. **Notification Processing**: Handles various subscription lifecycle events
4. **Database Storage**: Persists subscription data and notification history
5. **REST APIs**: Query subscription status and history

## Configuration Requirements

### Environment Variables

Configure the service using these environment variables in the `.env` file:

```
# Database settings
DATABASE_URL=sqlite:///./app.db

# Security settings
SECRET_KEY=your-secret-key-here
ACCESS_TOKEN_EXPIRE_MINUTES=60

# Apple App Store settings
APPLE_PRIVATE_KEY_ID=your-private-key-id
APPLE_PRIVATE_KEY_PATH=/path/to/private-key.p8
APPLE_BUNDLE_ID=your.app.bundle.id
APPLE_TEAM_ID=your-team-id
APPLE_ISSUER_ID=your-issuer-id

# Server settings
HOST=0.0.0.0
PORT=8000

# CORS settings
ALLOWED_ORIGINS=["http://localhost:8000", "http://localhost:3000"]
```

## Apple App Store Requirements

### 1. App Store Connect Configuration

1. **Register for App Store Server Notifications v2**:
   - Log in to [App Store Connect](https://appstoreconnect.apple.com)
   - Go to your app > App Information > App Store Server Notifications
   - Select "v2" for notification version
   - Set the production and sandbox URL endpoints for notifications
   - The endpoint will be `https://your-domain.com/api/v1/apple/webhook`

2. **Create API Keys**:
   - Go to App Store Connect > Users and Access > Keys
   - Create a new key with "App Store Connect API" access
   - Download the .p8 private key file and note the Key ID
   - Store this securely as it can only be downloaded once

### 2. Required Information

You'll need the following information from Apple to configure this service:

1. **Private Key (.p8 file)**: The private key downloaded from App Store Connect
2. **Private Key ID**: The ID of your App Store Connect API Key
3. **Team ID**: Your Apple Developer Team ID
4. **Bundle ID**: Your app's Bundle Identifier
5. **Issuer ID**: Your App Store Connect Issuer ID (found in API Keys section)

## API Endpoints

### Webhook Endpoint

```
POST /api/v1/apple/webhook
```
- Receives notifications from Apple's App Store Server
- Verifies JWS signature of the payload
- Processes the notification based on its type
- Responds with 200 OK when successfully received

### Query Subscription Status

```
GET /api/v1/subscriptions/status/{user_id}
```
- Returns current subscription status for a user
- Includes list of active subscriptions

### User Management

```
POST /api/v1/users/
```
- Create a new user

```
GET /api/v1/users/{user_id}
```
- Get user information

```
GET /api/v1/users/{user_id}/subscriptions
```
- Get all subscriptions for a user

## Running the Service

```bash
# Install dependencies
pip install -r requirements.txt

# Set up environment variables
cp example.env .env
# Edit .env with your specific configuration

# Run the service
python main.py
```

## Apple Server-to-Server Verification

This service implements the Apple App Store Server Notifications v2 protocol, which includes JWS (JSON Web Signature) verification to ensure notifications are authentic. It also supports verification of receipts and subscription status through the App Store Server API.

## Testing

To test the service with Apple's sandbox environment:

1. Configure the same service with sandbox URLs
2. Make test purchases in your app's sandbox environment
3. Verify notifications are received and processed correctly

## Deployment

For production deployment, ensure:

1. HTTPS is enabled for your webhook endpoint
2. Private keys are securely stored
3. Database is properly configured and backed up
4. Environment variables are set correctly

## Verifying Your Apple Connection

To verify that your connection with Apple is working properly, you can perform these tests:

### 1. Test the Webhook Endpoint

Apple provides a way to send test notifications from App Store Connect:

1. Log in to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to your app > App Information > App Store Server Notifications
3. Click on the "Send Test Notification" button
4. Check your service logs to confirm receipt of the test notification

You can also monitor your webhook endpoint logs when running the service:

```bash
python3 main.py
```

Look for log entries indicating received notifications and successful JWS verification.

### 2. Verify API Key Configuration

Test that your Apple API key is correctly configured by checking the logs for any JWS verification errors:

```bash
# Run with debug logging enabled
DEBUG=True python3 main.py
```

### 3. Use the Test Endpoint

The service includes a test endpoint to verify your Apple configuration:

```
GET /api/v1/apple/test-connection
```

This endpoint attempts to communicate with Apple's servers using your configured credentials and returns a success or error message.

### 4. Check Logs for Connection Issues

Common connection problems appear in the logs with these errors:
- "Invalid JWS signature" - Check your private key configuration
- "Connection error to Apple servers" - Check your network connection
- "Invalid API key" - Verify your key ID and issuer ID

### 5. Sandbox Testing

For a complete test:
1. Configure your app to use Apple's sandbox environment
2. Make a test purchase in the sandbox
3. Verify your service receives and processes the notification

## Additional Resources

- [Apple App Store Server Notifications v2 Documentation](https://developer.apple.com/documentation/appstoreservernotifications)
- [App Store Server API Documentation](https://developer.apple.com/documentation/appstoreserverapi)
- [JWS Signature Verification](https://developer.apple.com/documentation/appstoreservernotifications/responsebodyv2decodedpayload)
