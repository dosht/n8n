# 🏛️ Archon OS SSL Deployment

This is a production-ready deployment of [Archon OS](https://github.com/coleam00/Archon) with SSL/TLS support using Docker Compose, Nginx reverse proxy, and Let's Encrypt certificates.

## 🎯 What is Archon?

Archon is a **knowledge and task management backbone** for AI coding assistants. It provides:

- **Knowledge Base Management**: Crawl websites, upload PDFs/docs
- **Smart Search**: Advanced RAG (Retrieval Augmented Generation) strategies  
- **Task Management**: Integrated with your knowledge base
- **MCP Server**: Model Context Protocol for AI assistants (Claude Code, Cursor, etc.)
- **Real-time Updates**: Collaborate with AI on tasks and context

## 🏗️ Architecture

```
Internet → Nginx (SSL) → Docker Network → Archon Services
                                        ├── Frontend (3737) → UI
                                        ├── Backend (8181) → API
                                        ├── MCP Server (8051) → AI Agents
                                        └── Agents (8052) → Task Management
```

**Domains:**
- Frontend: `https://archon.transgate.ai`
- API: `https://api.archon.transgate.ai`

## 🚀 Quick Start

### Prerequisites

1. **Ubuntu/Debian server** with root access
2. **Docker & Docker Compose** installed
3. **Domain names** pointing to your server:
   - `archon.transgate.ai`
   - `api.archon.transgate.ai`
4. **Supabase account** (free tier works)
5. **OpenAI API key** (optional, can configure via UI)

### Step 1: Configure Environment

```bash
# Copy and configure environment file
cp .env.archon .env.archon.local
nano .env.archon.local
```

**Required configuration:**

```bash
# Supabase (Required)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

# Domains
DOMAIN=archon.transgate.ai
ARCHON_API_DOMAIN=api.archon.transgate.ai

# Email for SSL certificates
LETSENCRYPT_EMAIL=your-email@example.com

# Optional: AI API Keys (can set via UI later)
OPENAI_API_KEY=sk-...
```

### Step 2: Set Up SSL Certificates

```bash
# Run SSL setup (interactive)
./setup-archon-ssl.sh
```

This will:
- Check if domains point to your server
- Request SSL certificates from Let's Encrypt
- Set up auto-renewal

### Step 3: Deploy Archon

```bash
# Deploy with SSL
./deploy-archon.sh
```

### Step 4: Access Your Installation

- **Frontend**: https://archon.transgate.ai
- **API**: https://api.archon.transgate.ai

## 📋 Management Commands

```bash
# View deployment status
./deploy-archon.sh --status

# View logs
./deploy-archon.sh --logs

# Stop services
./deploy-archon.sh --stop

# Restart deployment
./deploy-archon.sh

# Renew SSL certificates
./certbot-renew.sh
```

## 🔧 Configuration

### Environment Variables

| Variable | Description | Required | Example |
|----------|-------------|----------|---------|
| `SUPABASE_URL` | Your Supabase project URL | ✅ | `https://xxx.supabase.co` |
| `SUPABASE_SERVICE_KEY` | Supabase service role key | ✅ | `eyJhbGciOiJIUzI1NiIs...` |
| `OPENAI_API_KEY` | OpenAI API key | ❌ | `sk-proj-...` |
| `LETSENCRYPT_EMAIL` | Email for SSL certificates | ✅ | `admin@example.com` |
| `ARCHON_FRONTEND_DOMAIN` | Frontend domain | ✅ | `archon.transgate.ai` |
| `ARCHON_API_DOMAIN` | API domain | ✅ | `api.archon.transgate.ai` |

### Supabase Setup

1. Create a free Supabase project at https://supabase.com
2. Go to **Settings > API** in your Supabase dashboard
3. Copy your **Project URL** and **service_role key** (NOT the anon key!)

⚠️ **CRITICAL**: Use the **service_role** key, not the anon key! The anon key will cause permission errors.

### Port Configuration

Default ports (internal Docker network):
- Frontend: `3737`
- Backend API: `8181`  
- MCP Server: `8051`
- Agents: `8052`

External access is via Nginx reverse proxy on ports 80/443.

## 🔐 SSL/HTTPS

### Automatic Certificate Management

SSL certificates are automatically:
- Requested from Let's Encrypt during setup
- Renewed every 12 hours via cron job
- Validated using HTTP-01 challenge

### Manual Certificate Operations

```bash
# Check certificate status
openssl x509 -in ./certbot/conf/live/archon.transgate.ai/fullchain.pem -text -noout

# Force certificate renewal
./setup-archon-ssl.sh

# Test certificate renewal
./certbot-renew.sh
```

### Setting Up Auto-Renewal

Add to crontab for automatic renewal:

```bash
crontab -e

# Add this line:
0 */12 * * * /opt/n8n/certbot-renew.sh >> /var/log/certbot-renewal.log 2>&1
```

## 🐳 Docker Management

### Container Overview

| Service | Container Name | Purpose |
|---------|----------------|---------|
| Frontend | `archon-frontend` | React UI application |
| Backend | `archon-server` | FastAPI + Socket.IO server |
| MCP | `archon-mcp` | Model Context Protocol server |
| Agents | `archon-agents` | AI agents service |
| Nginx | `archon_nginx` | Reverse proxy with SSL |
| Certbot | `archon_certbot` | SSL certificate management |

### Useful Commands

```bash
# View all containers
docker ps

# View specific service logs
docker compose --env-file .env.archon -f docker-compose.archon.yml logs archon-server

# Restart specific service
docker compose --env-file .env.archon -f docker-compose.archon.yml restart archon-server

# Execute shell in container
docker exec -it archon-server /bin/bash

# View resource usage
docker stats

# Clean up unused containers/images
docker system prune -f
```

### Health Checks

All services have built-in health checks:

```bash
# Check service health
docker ps --format "table {{.Names}}\t{{.Status}}"

# View health check logs
docker inspect archon-server | grep Health -A 10
```

## 📊 Monitoring & Logging

### Log Locations

```bash
# Application logs
docker compose --env-file .env.archon -f docker-compose.archon.yml logs

# Nginx logs
tail -f nginx/logs/access.log
tail -f nginx/logs/error.log

# SSL renewal logs  
tail -f /var/log/certbot-renewal.log
```

### Monitoring Service Health

```bash
# Test frontend
curl -I https://archon.transgate.ai

# Test API
curl -I https://api.archon.transgate.ai

# Test internal services
curl -f http://localhost:8181/health  # (from server)
```

## 🔧 Troubleshooting

### Common Issues

#### 1. SSL Certificate Errors

```bash
# Check if domains point to your server
dig +short archon.transgate.ai
curl -I http://archon.transgate.ai/.well-known/acme-challenge/test

# Re-run SSL setup
./setup-archon-ssl.sh
```

#### 2. Services Won't Start

```bash
# Check logs
./deploy-archon.sh --logs

# Check specific service
docker logs archon-server

# Check environment variables
docker exec archon-server env | grep SUPABASE
```

#### 3. Database Connection Issues

- Verify `SUPABASE_URL` is correct
- Ensure you're using `service_role` key, not `anon` key
- Check Supabase project is active

#### 4. Port Conflicts

```bash
# Check what's using ports
netstat -tulnp | grep :80
netstat -tulnp | grep :443

# Stop conflicting services
sudo systemctl stop apache2  # or nginx
```

#### 5. Memory/Resource Issues

```bash
# Check resource usage
docker stats

# Check server resources
free -h
df -h

# Increase Docker memory limits if needed
```

### Debugging Steps

1. **Check service status**
   ```bash
   ./deploy-archon.sh --status
   ```

2. **View recent logs**
   ```bash
   docker compose --env-file .env.archon -f docker-compose.archon.yml logs --tail=50
   ```

3. **Test individual components**
   ```bash
   # Test Supabase connection
   curl -H "apikey: $SUPABASE_SERVICE_KEY" "$SUPABASE_URL/rest/v1/"
   
   # Test internal network
   docker exec archon-server curl -f http://archon-mcp:8051/health
   ```

4. **Check firewall**
   ```bash
   ufw status
   iptables -L
   ```

## 🔄 Updates & Maintenance

### Updating Archon

```bash
# Pull latest images and restart
./deploy-archon.sh

# Or manually pull updates
docker compose --env-file .env.archon -f docker-compose.archon.yml pull
./deploy-archon.sh
```

### Backup & Recovery

#### What to Backup

```bash
# Configuration files
tar -czf archon-config-backup.tar.gz \
    .env.archon \
    docker-compose.archon.yml \
    nginx/conf.d/archon-ssl.conf \
    certbot/conf/

# Data volumes (if using local volumes)
docker run --rm -v archon_data:/data -v $(pwd):/backup ubuntu \
    tar czf /backup/archon-data-backup.tar.gz /data
```

#### Restore Process

```bash
# Restore configuration
tar -xzf archon-config-backup.tar.gz

# Restore data
docker run --rm -v archon_data:/data -v $(pwd):/backup ubuntu \
    bash -c "cd /data && tar xzf /backup/archon-data-backup.tar.gz --strip 1"

# Restart services
./deploy-archon.sh
```

### System Maintenance

```bash
# Clean up Docker resources
docker system prune -f --volumes

# Update system packages
sudo apt update && sudo apt upgrade -y

# Check disk space
df -h
du -sh /var/lib/docker/

# Rotate logs
sudo logrotate -f /etc/logrotate.conf
```

## 🌐 Networking & Security

### Firewall Configuration

```bash
# Allow HTTP/HTTPS
sudo ufw allow 80
sudo ufw allow 443

# Allow SSH (if needed)
sudo ufw allow 22

# Enable firewall
sudo ufw enable
```

### Security Headers

The Nginx configuration includes security headers:
- `Strict-Transport-Security` (HSTS)
- `X-Frame-Options`
- `X-Content-Type-Options`
- `X-XSS-Protection`

### CORS Configuration

API endpoints are configured for CORS with the frontend domain. Modify in `nginx/conf.d/archon-ssl.conf` if needed.

## 🆘 Support

### Getting Help

1. **Check logs first**
   ```bash
   ./deploy-archon.sh --logs
   ```

2. **Archon Community**
   - [GitHub Discussions](https://github.com/coleam00/Archon/discussions)
   - [GitHub Issues](https://github.com/coleam00/Archon/issues)

3. **This deployment**
   - Check this README
   - Review configuration files
   - Test individual components

### Useful Resources

- [Archon GitHub Repository](https://github.com/coleam00/Archon)
- [Supabase Documentation](https://supabase.com/docs)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)

---

## 📝 Files Overview

| File | Purpose |
|------|---------|
| `.env.archon` | Environment configuration |
| `docker-compose.archon.yml` | Docker services definition |
| `nginx/conf.d/archon-ssl.conf` | Nginx reverse proxy config |
| `setup-archon-ssl.sh` | SSL certificate setup script |
| `deploy-archon.sh` | Main deployment script |
| `certbot-renew.sh` | Certificate renewal script |
| `README-ARCHON.md` | This documentation |

**Happy building with Archon! 🏛️**
