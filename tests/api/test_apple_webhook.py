"""
Tests for the Apple webhook API.
"""
import json
import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock

from app.core.apple_jws import AppleJWSVerifier
from main import app


client = TestClient(app)


@pytest.fixture
def mock_jws_verification():
    """Mock JWS verification."""
    with patch.object(AppleJWSVerifier, 'verify_jws') as mock:
        mock.return_value = {
            "notificationType": "SUBSCRIBED",
            "notificationUUID": "test-uuid",
            "data": {
                "signedTransactionInfo": "test-transaction-info"
            }
        }
        yield mock


@pytest.fixture
def mock_notification_processor():
    """Mock notification processor."""
    with patch('app.api.routes.apple_webhook.NotificationProcessor') as mock:
        processor_instance = MagicMock()
        mock.return_value = processor_instance
        yield processor_instance


def test_apple_webhook(mock_jws_verification, mock_notification_processor):
    """Test the Apple webhook endpoint."""
    payload = {
        "signedPayload": "test-signed-payload"
    }
    
    response = client.post("/api/v1/webhook/apple", json=payload)
    
    # Check that the response is as expected
    assert response.status_code == 200
    assert response.json() == {"received": True}
    
    # Verify JWS verification was called
    mock_jws_verification.assert_called_once_with("test-signed-payload")
    
    # Verify notification processor was called
    mock_notification_processor.process_notification.assert_called_once()


def test_apple_webhook_jws_verification_error(mock_jws_verification):
    """Test the Apple webhook endpoint with JWS verification error."""
    # Setup JWS verification to raise an error
    mock_jws_verification.side_effect = ValueError("Invalid JWS")
    
    payload = {
        "signedPayload": "test-signed-payload"
    }
    
    response = client.post("/api/v1/webhook/apple", json=payload)
    
    # Check that the response is still 200 OK (Apple expects this)
    assert response.status_code == 200
    assert response.json() == {"received": True}
