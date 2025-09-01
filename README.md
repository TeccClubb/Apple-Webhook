# Apple Subscription Service

A production-ready Python service for handling Apple App Store Server Notifications (v2) for subscription events. This service provides a webhook endpoint for receiving Apple's server notifications, processes them, and provides REST APIs for querying user subscription statuses.

## Fresh VPS Installation Guide

If you're setting up on a newly reinstalled VPS, follow these steps for a complete installation:

1. Connect to your VPS:
   ```bash
   ssh user@your-vps-ip
   ```

2. Update your system:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

3. Install Git:
   ```bash
   sudo apt install git -y
   ```

4. Clone the repository:
   ```bash
   git clone https://github.com/TeccClubb/Apple-Webhook.git
   cd Apple-Webhook
   ```

5. Make the deployment scripts executable:
   ```bash
   chmod +x deploy.sh troubleshoot.sh check_system.py
   ```

6. Run the system compatibility checker to automatically install required dependencies:
   ```bash
   sudo python3 check_system.py --fix
   ```

7. Deploy the service:
   ```bash
   sudo ./deploy.sh
   ```

8. If you encounter any dependency issues, especially with PostgreSQL or psycopg2, run the troubleshooting script:
   ```bash
   sudo ./troubleshoot.sh
   ```

9. Copy your Apple private key to the server:
   ```bash
   # On your local machine:
   scp /path/to/AuthKey_XXXXX.p8 user@your-vps-ip:~/Apple-Webhook/keys/
   
   # On your VPS:
   sudo chmod 600 ~/Apple-Webhook/keys/AuthKey_XXXXX.p8
   sudo chown appuser:appuser ~/Apple-Webhook/keys/AuthKey_XXXXX.p8
   ```

10. Verify the deployment:
    ```bash
    curl https://apple.safeprovpn.com/api/v1/test-connection
    ```

## Quick Deployment with Script

For easy deployment to your VPS with domain `apple.safeprovpn.com`, use the included deployment script:

1. Connect to your VPS:
   ```bash
   ssh user@your-vps-ip
   ```

2. Upload the deploy.sh script to your server:
   ```bash
   scp deploy.sh user@your-vps-ip:~/
   ```

3. Make the script executable and run it:
   ```bash
   chmod +x deploy.sh
   sudo ./deploy.sh
   ```

This script will:
- Install all dependencies (Python, Nginx, PostgreSQL, etc.)
- Set up a PostgreSQL database
- Configure the environment with your Apple credentials
- Set up HTTPS with Let's Encrypt
- Configure Nginx as a reverse proxy
- Start the service using Supervisor

After deployment, test your connection to Apple's servers:
```bash
curl https://apple.safeprovpn.com/api/v1/test-connection
```

## Features

- Process Apple App Store Server Notifications via webhook
- Verify Apple's JWS signatures for security
- Store subscription data in a database
- Provide REST APIs to query user subscription status
- Process all App Store notification types (SUBSCRIBED, DID_RENEW, EXPIRED, etc.)
- Authentication for API endpoints
- Proper error handling and logging

## Technical Specifications

- **FastAPI**: Modern, high-performance web framework for API development
- **SQLAlchemy**: SQL toolkit and ORM
- **Pydantic**: Data validation and settings management
- **Python-dotenv**: Environment configuration
- **JWT**: Authentication and Apple JWS verification

## API Endpoints

- `POST /api/v1/webhook/apple`: Receives and processes Apple App Store Server Notifications
- `GET /api/v1/subscriptions/status/{user_id}`: Checks a user's subscription status
- `GET /api/v1/subscriptions/active/{user_id}`: Gets a user's active subscriptions
- `POST /api/v1/subscriptions/auth`: Obtains API authentication tokens

## Setup Instructions

### Prerequisites

- Python 3.8 or higher
- PostgreSQL (for production) or SQLite (for development)
- pip (Python package manager)

### Local Development Setup

1. Clone the repository:

```bash
git clone <repository-url>
cd apple-subscription-service
```

2. Create a virtual environment:

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

3. Install dependencies:

```bash
pip install -r requirements.txt
```

4. Set up environment variables:

```bash
cp example.env .env
```

Edit the `.env` file and set appropriate values for your environment.

5. Run the development server:

```bash
uvicorn main:app --reload
```

6. Access the API documentation at:

```
http://localhost:8000/api/docs
```

### Production Setup

#### Server Setup

1. Install Python and required packages on your Linux server:

```bash
sudo apt update
sudo apt install python3 python3-pip python3-dev libpq-dev postgresql postgresql-contrib nginx
```

2. Clone the repository:

```bash
git clone <repository-url>
cd apple-subscription-service
```

3. Create a virtual environment:

```bash
python3 -m venv venv
source venv/bin/activate
```

4. Install dependencies:

```bash
pip install -r requirements.txt
pip install gunicorn
```

5. Set up environment variables:

```bash
cp example.env .env
```

Edit the `.env` file with production values, particularly:
- Set `DEBUG=False`
- Set a strong `SECRET_KEY`
- Configure proper `DATABASE_URL` for PostgreSQL
- Set appropriate `APPLE_*` variables

#### Database Setup

1. Create a PostgreSQL database:

```bash
sudo -u postgres psql
```

```sql
CREATE DATABASE apple_subscriptions;
CREATE USER app_user WITH PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE apple_subscriptions TO app_user;
```

2. Update the `DATABASE_URL` in your `.env` file:

```
DATABASE_URL=postgresql://app_user:secure_password@localhost:5432/apple_subscriptions
```

#### Setting up Systemd Service

1. Create a systemd service file:

```bash
sudo nano /etc/systemd/system/apple-subscription.service
```

2. Add the following content:

```
[Unit]
Description=Apple Subscription Service
After=network.target

[Service]
User=ubuntu
Group=www-data
WorkingDirectory=/path/to/apple-subscription-service
Environment="PATH=/path/to/apple-subscription-service/venv/bin"
EnvironmentFile=/path/to/apple-subscription-service/.env
ExecStart=/path/to/apple-subscription-service/venv/bin/gunicorn -w 4 -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:8000

[Install]
WantedBy=multi-user.target
```

3. Enable and start the service:

```bash
sudo systemctl enable apple-subscription
sudo systemctl start apple-subscription
sudo systemctl status apple-subscription
```

#### Nginx Setup as Reverse Proxy

1. Create an Nginx site configuration:

```bash
sudo nano /etc/nginx/sites-available/apple-subscription
```

2. Add the following configuration:

```
server {
    listen 80;
    server_name your_domain.com;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /api/docs {
        proxy_pass http://localhost:8000/api/docs;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

3. Create a symbolic link and test the configuration:

```bash
sudo ln -s /etc/nginx/sites-available/apple-subscription /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

#### Setting up SSL/TLS with Certbot

1. Install Certbot:

```bash
sudo apt install certbot python3-certbot-nginx
```

2. Obtain and install a certificate:

```bash
sudo certbot --nginx -d your_domain.com
```

3. Follow the prompts to complete the certificate installation.

4. Certbot will automatically update your Nginx configuration to use HTTPS.

5. Test the automatic renewal:

```bash
sudo certbot renew --dry-run
```

## Usage

### Authentication

To access protected endpoints, obtain an authentication token:

```
POST /api/v1/subscriptions/auth

{
  "username": "user@example.com",
  "password": "password"
}
```

Use the returned token in the Authorization header:

```
Authorization: Bearer {token}
```

### Webhook Setup in App Store Connect

1. Log in to [App Store Connect](https://appstoreconnect.apple.com/)
2. Go to your app > App Information > App Store Server Notifications
3. Set the Production URL to: `https://your_domain.com/api/v1/webhook/apple`
4. Set the Sandbox URL to: `https://your_domain.com/api/v1/webhook/apple`
5. Select Version 2 for the notification format

## Troubleshooting Common Issues

### PostgreSQL and psycopg2 Installation Issues

If you encounter issues with PostgreSQL or psycopg2-binary installation:

1. Install PostgreSQL development packages:
   ```bash
   sudo apt-get update
   sudo apt-get install -y libpq-dev postgresql-server-dev-all build-essential python3-dev
   ```

2. Reinstall psycopg2 properly:
   ```bash
   cd /opt/apple-subscription-service
   source venv/bin/activate
   pip install --no-cache-dir --no-build-isolation psycopg2-binary
   ```

3. If the above doesn't work, try the source version:
   ```bash
   pip install --no-cache-dir psycopg2
   ```

### Database Connection Issues

If the application can't connect to the database:

1. Check PostgreSQL service status:
   ```bash
   sudo systemctl status postgresql
   ```

2. Verify that PostgreSQL is configured to accept connections:
   ```bash
   sudo nano /etc/postgresql/*/main/postgresql.conf
   # Ensure listen_addresses = 'localhost' is uncommented
   
   sudo nano /etc/postgresql/*/main/pg_hba.conf
   # Ensure there's a line like: "local all all peer"
   ```

3. Restart PostgreSQL after configuration changes:
   ```bash
   sudo systemctl restart postgresql
   ```

### Nginx Configuration Issues

If you can't access your API through HTTPS:

1. Check Nginx configuration:
   ```bash
   sudo nginx -t
   ```

2. Verify that your domain points to your server:
   ```bash
   nslookup apple.safeprovpn.com
   ```

3. Ensure Let's Encrypt certificates are properly set up:
   ```bash
   sudo certbot certificates
   ```

### Service Startup Issues

If the service doesn't start:

1. Check the service status:
   ```bash
   sudo supervisorctl status apple-subscription
   ```

2. Examine error logs:
   ```bash
   tail -n 100 /opt/apple-subscription-service/logs/gunicorn-error.log
   ```

3. Run the application directly to see immediate output:
   ```bash
   cd /opt/apple-subscription-service
   source venv/bin/activate
   python -m uvicorn main:app --host 127.0.0.1 --port 8080
   ```

## Monitoring and Maintenance

### Logs

View application logs:

```bash
sudo journalctl -u apple-subscription
```

### Supervisor Logs

View supervisor logs:

```bash
sudo supervisorctl tail -f apple-subscription
```

### VPS Service Management

Common commands for managing your service:

```bash
# Start the service
sudo supervisorctl start apple-subscription

# Stop the service
sudo supervisorctl stop apple-subscription

# Restart the service
sudo supervisorctl restart apple-subscription

# Check the status
sudo supervisorctl status apple-subscription

# View logs in real-time
sudo supervisorctl tail -f apple-subscription
```

### Nginx Management

Commands for managing Nginx:

```bash
# Test configuration
sudo nginx -t

# Reload configuration without downtime
sudo systemctl reload nginx

# Restart Nginx
sudo systemctl restart nginx

# Check status
sudo systemctl status nginx
```

### Database Management

Commands for managing PostgreSQL:

```bash
# Connect to PostgreSQL
sudo -u postgres psql

# Connect to the application database
sudo -u postgres psql -d apple_subscriptions

# Useful PostgreSQL commands:
# \dt - list tables
# \q - quit
# SELECT * FROM subscriptions LIMIT 10; - view recent subscriptions
```

### Updating the Application

1. Pull the latest code:

```bash
cd /opt/apple-subscription-service
sudo git pull
```

2. Install any new dependencies:

```bash
cd /opt/apple-subscription-service
sudo -u appuser bash -c "source venv/bin/activate && pip install -r requirements.txt"
```

3. Restart the service:

```bash
sudo supervisorctl restart apple-subscription
```

### Backup and Restore

Backup your PostgreSQL database:

```bash
# Create a backup
sudo -u postgres pg_dump apple_subscriptions > backup.sql

# Restore from backup
sudo -u postgres psql apple_subscriptions < backup.sql
```

## Security Considerations

- Always use HTTPS in production
- Rotate the `SECRET_KEY` periodically
- Keep dependencies updated
- Implement IP whitelisting for webhook endpoints if possible
- Monitor logs for unusual activity
- **Important:** Store private keys and secrets securely:
  - Avoid committing private keys directly to repositories
  - Consider using environment variables or secure secret management solutions
  - If you've already committed sensitive files, consider rotating those credentials and using `.gitignore`

## License

[MIT License](LICENSE)
