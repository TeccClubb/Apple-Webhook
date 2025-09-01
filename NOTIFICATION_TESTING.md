# Apple App Store Notifications Testing Guide

This guide will help you verify that Apple App Store notifications are working correctly with your subscription service.

## Monitoring Notifications

### 1. Use the Notification Monitor

Run the notification monitoring script to check notifications in real-time:

```bash
sudo ./monitor_notifications.sh
```

This script provides:
- Webhook configuration checks
- Database record verification
- Real-time log monitoring for notifications

### 2. Test Purchase Flow

To properly test the notification system:

1. **Make a test purchase** from your iOS app
   - Use a sandbox account for testing (Apple provides test accounts in App Store Connect)
   - Complete the in-app purchase flow

2. **Monitor logs in real-time** during the purchase:
   ```bash
   supervisorctl tail -f apple-subscription
   ```

3. **Look for these key events** in the logs:
   - Receipt of webhook notification from Apple
   - Successful verification of the notification signature
   - Processing of the notification data
   - Database updates for the user's subscription status

### 3. Check Database Records Manually

After making a test purchase, verify records in the database:

```bash
# Connect to the PostgreSQL database
sudo -u postgres psql apple_subscriptions

# Check subscriptions table
SELECT * FROM subscriptions ORDER BY purchase_date DESC LIMIT 5;

# Check notification history
SELECT * FROM notification_history ORDER BY created_at DESC LIMIT 5;

# Check specific user's subscription
SELECT u.id, u.email, s.original_transaction_id, s.status, s.purchase_date, s.expires_date 
FROM users u 
JOIN subscriptions s ON u.id = s.user_id 
WHERE u.email = 'test@example.com';
```

### 4. Common Notification Types to Expect

- `SUBSCRIBED`: Initial subscription purchase
- `DID_RENEW`: Successful subscription renewal
- `DID_FAIL_TO_RENEW`: Failed renewal attempt
- `EXPIRED`: Subscription has ended
- `PRICE_INCREASE`: Price change notification

## Troubleshooting

If notifications aren't working:

1. **Verify webhook URL** in App Store Connect:
   - Should be: `https://apple.safeprovpn.com/api/v1/webhook/apple`
   - Check for any typos or configuration issues

2. **Check server logs** for errors:
   - `supervisorctl tail -f apple-subscription`
   - Look for authentication or verification failures

3. **Verify Apple credentials** in your .env file:
   - `APPLE_TEAM_ID`
   - `APPLE_BUNDLE_ID`
   - `APPLE_ISSUER_ID`
   - `APPLE_PRIVATE_KEY_ID`

4. **Confirm network connectivity**:
   - Make sure your server can reach Apple's servers
   - Check for any firewall issues

5. **Test with the diagnostic endpoint**:
   - `curl https://apple.safeprovpn.com/api/v1/test-connection`
   - Should return successful connection to Apple's servers

## Testing in Sandbox Mode

Always use Apple's sandbox environment for testing:

1. Make sure `APPLE_ENVIRONMENT` is set to:
   - `Sandbox` for testing
   - `Production` only for live app

2. Use test accounts created in App Store Connect

3. Remember that sandbox subscription periods are accelerated:
   - Monthly subscriptions renew in ~3 minutes
   - Annual subscriptions renew in ~3 hours

## Additional Resources

- [Apple App Store Server Notifications Documentation](https://developer.apple.com/documentation/appstoreservernotifications)
- [App Store Server API Documentation](https://developer.apple.com/documentation/appstoreserverapi)
