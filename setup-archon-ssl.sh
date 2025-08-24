#!/bin/bash
# ============================================================================
# ARCHON SSL CERTIFICATE SETUP SCRIPT
# Sets up SSL certificates for archon.transgate.ai and api.archon.transgate.ai
# ============================================================================

set -e

# Load environment variables
if [ -f .env.archon ]; then
    source .env.archon
else
    echo "Error: .env.archon file not found!"
    echo "Please copy .env.archon.example and configure it first."
    exit 1
fi

# Configuration
DOMAINS=("archon.transgate.ai" "api.archon.transgate.ai")
EMAIL="${LETSENCRYPT_EMAIL:-mou.abdelhamid@gmail.com}"

echo "============================================================================"
echo "🔐 ARCHON SSL CERTIFICATE SETUP"
echo "============================================================================"
echo "Setting up SSL certificates for:"
for domain in "${DOMAINS[@]}"; do
    echo "  - $domain"
done
echo "Email: $EMAIL"
echo ""

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Error: Docker is not running!"
    exit 1
fi

# Function to check if domain is reachable
check_domain() {
    local domain=$1
    echo "🌐 Checking if $domain points to this server..."
    
    # Get this server's public IP
    SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "unknown")
    
    # Get domain's IP
    DOMAIN_IP=$(dig +short $domain | tail -n1)
    
    echo "   Server IP: $SERVER_IP"
    echo "   Domain IP: $domain_ip"
    
    if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
        echo "⚠️  Warning: $domain may not point to this server"
        echo "   Make sure DNS is configured correctly before proceeding"
        read -p "   Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "✅ $domain correctly points to this server"
    fi
}

# Function to request certificate
request_certificate() {
    local domain=$1
    echo ""
    echo "📜 Requesting SSL certificate for $domain..."
    
    # Create certificate directory
    mkdir -p "./certbot/conf/live/$domain"
    
    # Check if certificate already exists
    if [ -f "./certbot/conf/live/$domain/fullchain.pem" ]; then
        echo "   Certificate already exists for $domain"
        read -p "   Overwrite existing certificate? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "   Skipping $domain"
            return
        fi
    fi
    
    # Request certificate using HTTP-01 challenge
    docker run --rm \
        -v "$PWD/certbot/www:/var/www/certbot" \
        -v "$PWD/certbot/conf:/etc/letsencrypt" \
        certbot/certbot:latest \
        certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        -d "$domain"
        
    if [ $? -eq 0 ]; then
        echo "✅ Certificate successfully obtained for $domain"
    else
        echo "❌ Failed to obtain certificate for $domain"
        echo "   Make sure:"
        echo "   1. Domain points to this server"
        echo "   2. Port 80 is accessible (HTTP challenge)"
        echo "   3. No firewall blocking access"
        return 1
    fi
}

# Function to set up certificate auto-renewal
setup_renewal() {
    echo ""
    echo "🔄 Setting up certificate auto-renewal..."
    
    # Create renewal script
    cat > certbot-renew.sh << 'RENEWAL_EOF'
#!/bin/bash
# Auto-renewal script for Archon SSL certificates

echo "$(date): Checking for certificate renewals..."

# Run certbot renewal
docker run --rm \
    -v "$PWD/certbot/www:/var/www/certbot" \
    -v "$PWD/certbot/conf:/etc/letsencrypt" \
    certbot/certbot:latest \
    renew --quiet

# Reload nginx if certificates were renewed
if [ $? -eq 0 ]; then
    echo "$(date): Certificates checked/renewed successfully"
    # Reload nginx in docker container
    docker exec archon_nginx nginx -s reload 2>/dev/null || echo "Nginx not running"
else
    echo "$(date): Certificate renewal failed"
fi
RENEWAL_EOF

    chmod +x certbot-renew.sh
    
    echo "✅ Renewal script created: certbot-renew.sh"
    echo "   Add this to crontab to run twice daily:"
    echo "   0 */12 * * * $PWD/certbot-renew.sh >> /var/log/certbot-renewal.log 2>&1"
}

# Main execution
main() {
    echo "🚀 Starting SSL certificate setup..."
    
    # Create necessary directories
    mkdir -p certbot/{www,conf}
    mkdir -p nginx/logs
    
    # Check domain DNS configuration
    for domain in "${DOMAINS[@]}"; do
        check_domain "$domain"
    done
    
    echo ""
    echo "📋 Starting certificate requests..."
    echo "   This process requires:"
    echo "   1. Nginx running with HTTP (port 80) accessible"
    echo "   2. Domain(s) pointing to this server"
    echo ""
    read -p "🔄 Start Nginx temporarily for certificate validation? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "🌐 Starting temporary Nginx for certificate validation..."
        
        # Create temporary nginx config for certificate validation
        cat > nginx/conf.d/temp-ssl.conf << 'TEMP_EOF'
server {
    listen 80;
    server_name archon.transgate.ai api.archon.transgate.ai;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 200 'SSL setup in progress...';
        add_header Content-Type text/plain;
    }
}
TEMP_EOF
        
        # Start temporary nginx
        docker run -d --name temp_nginx_archon \
            -p 80:80 \
            -v "$PWD/nginx/conf.d:/etc/nginx/conf.d" \
            -v "$PWD/certbot/www:/var/www/certbot" \
            nginx:alpine
        
        # Wait for nginx to start
        sleep 5
    fi
    
    # Request certificates for each domain
    for domain in "${DOMAINS[@]}"; do
        request_certificate "$domain"
    done
    
    # Clean up temporary nginx
    if docker ps | grep -q "temp_nginx_archon"; then
        echo "🧹 Cleaning up temporary Nginx..."
        docker stop temp_nginx_archon >/dev/null 2>&1
        docker rm temp_nginx_archon >/dev/null 2>&1
        rm -f nginx/conf.d/temp-ssl.conf
    fi
    
    # Set up auto-renewal
    setup_renewal
    
    echo ""
    echo "============================================================================"
    echo "✅ SSL CERTIFICATE SETUP COMPLETE!"
    echo "============================================================================"
    echo "Certificates obtained for:"
    for domain in "${DOMAINS[@]}"; do
        if [ -f "./certbot/conf/live/$domain/fullchain.pem" ]; then
            echo "  ✅ $domain"
            echo "     Certificate: ./certbot/conf/live/$domain/fullchain.pem"
            echo "     Private key: ./certbot/conf/live/$domain/privkey.pem"
        else
            echo "  ❌ $domain (failed)"
        fi
    done
    echo ""
    echo "Next steps:"
    echo "1. Verify your .env.archon configuration"
    echo "2. Run: ./deploy-archon.sh"
    echo "3. Set up crontab for automatic renewal:"
    echo "   crontab -e"
    echo "   Add: 0 */12 * * * $PWD/certbot-renew.sh >> /var/log/certbot-renewal.log 2>&1"
    echo ""
}

# Run main function
main "$@"
