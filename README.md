# n8n with nginx and PostgreSQL

This Docker Compose setup provides a complete n8n installation with:
- n8n workflow automation tool
- PostgreSQL database for data persistence
- nginx reverse proxy for web access
- SSL/HTTPS support (configurable)

## Quick Start

1. **Change the encryption key** in `.env` file:
   ```bash
   # Generate a random encryption key
   openssl rand -hex 32
   ```

2. **Start the services**:
   ```bash
   docker compose up -d
   ```

3. **Access n8n**:
   - Open your browser and go to: http://localhost
   - Or directly: http://localhost:5678

4. **Check status**:
   ```bash
   docker compose ps
   docker compose logs -f n8n
   ```

## Configuration

### Environment Variables
Edit the `.env` file to customize your installation:

- `N8N_ENCRYPTION_KEY`: **REQUIRED** - Change this to a secure random string
- `POSTGRES_PASSWORD`: Change the default database password
- `N8N_HOST`: Set your domain name for production
- `WEBHOOK_URL`: Set the webhook URL for external integrations

### SSL/HTTPS Setup
To enable HTTPS:

1. Place your SSL certificates in `nginx/ssl/`:
   - `cert.pem` - SSL certificate
   - `key.pem` - Private key

2. Update `nginx/conf.d/n8n.conf`:
   - Uncomment the HTTPS server block
   - Update `server_name` with your domain

3. Update the `.env` file:
   ```bash
   N8N_PROTOCOL=https
   WEBHOOK_URL=https://your-domain.com/
   ```

## Directory Structure

```
/opt/n8n/
├── docker-compose.yml       # Main compose file
├── .env                     # Environment variables
├── init-data.sh            # Database initialization script
├── nginx/                  # nginx configuration
│   ├── nginx.conf          # Main nginx config
│   ├── conf.d/
│   │   └── n8n.conf        # n8n proxy configuration
│   ├── ssl/                # SSL certificates (if using HTTPS)
│   └── logs/               # nginx logs
└── n8n/
    └── custom-nodes/       # Custom n8n nodes
```

## Useful Commands

```bash
# Start services
docker compose up -d

# Stop services
docker compose down

# View logs
docker compose logs -f n8n
docker compose logs -f nginx
docker compose logs -f postgres

# Restart a service
docker compose restart n8n

# Update n8n to latest version
docker compose pull n8n
docker compose up -d n8n

# Backup database
docker compose exec postgres pg_dump -U n8n n8n > n8n_backup.sql

# Restore database
docker compose exec -T postgres psql -U n8n -d n8n < n8n_backup.sql
```

## Security Notes

1. **Change the encryption key** in the `.env` file
2. **Change the database password** in the `.env` file
3. **Use HTTPS** in production
4. **Restrict access** using firewall rules
5. **Keep containers updated** regularly

## Troubleshooting

- **Port conflicts**: Make sure ports 80, 443, and 5678 are not in use
- **Database connection**: Check if PostgreSQL is healthy: `docker compose exec postgres pg_isready -U n8n`
- **nginx errors**: Check nginx logs: `docker compose logs nginx`
- **n8n startup issues**: Check n8n logs: `docker compose logs n8n`

## Volumes

- `postgres_data`: PostgreSQL database files
- `n8n_data`: n8n workflows and configuration
- `nginx/logs`: nginx access and error logs

Data is persisted in Docker volumes and will survive container restarts.
