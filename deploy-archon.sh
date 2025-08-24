#!/bin/bash
# ============================================================================
# ARCHON DEPLOYMENT SCRIPT
# Deploys Archon OS with SSL support using Docker Compose + Nginx + Certbot
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.archon.yml"
ENV_FILE=".env.archon"
REQUIRED_DOMAINS=("archon.transgate.ai" "api.archon.transgate.ai")

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "🔍 Checking prerequisites..."
    
    # Check if Docker is installed and running
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed!"
        echo "Please install Docker first: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        error "Docker is not running!"
        echo "Please start Docker service"
        exit 1
    fi
    
    # Check if Docker Compose is available
    if ! docker compose version >/dev/null 2>&1; then
        error "Docker Compose is not available!"
        echo "Please install Docker Compose v2"
        exit 1
    fi
    
    # Check if environment file exists
    if [ ! -f "$ENV_FILE" ]; then
        error "Environment file $ENV_FILE not found!"
        echo "Please create and configure $ENV_FILE first"
        echo "You can copy from .env.archon and modify the values"
        exit 1
    fi
    
    # Check if compose file exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "Docker compose file $COMPOSE_FILE not found!"
        exit 1
    fi
    
    success "All prerequisites met ✅"
}

# Function to validate environment variables
validate_environment() {
    log "🔧 Validating environment configuration..."
    
    source "$ENV_FILE"
    
    # Check required variables
    if [ -z "$SUPABASE_URL" ]; then
        error "SUPABASE_URL is not set in $ENV_FILE"
        exit 1
    fi
    
    if [ -z "$SUPABASE_SERVICE_KEY" ]; then
        error "SUPABASE_SERVICE_KEY is not set in $ENV_FILE"
        exit 1
    fi
    
    # Check if SSL certificates exist
    local missing_certs=()
    for domain in "${REQUIRED_DOMAINS[@]}"; do
        if [ ! -f "./certbot/conf/live/$domain/fullchain.pem" ]; then
            missing_certs+=("$domain")
        fi
    done
    
    if [ ${#missing_certs[@]} -gt 0 ]; then
        error "SSL certificates missing for: ${missing_certs[*]}"
        echo ""
        echo "Please run the SSL setup first:"
        echo "  ./setup-archon-ssl.sh"
        echo ""
        echo "Or if you want to deploy without SSL, use HTTP mode:"
        echo "  docker compose --env-file $ENV_FILE -f docker-compose.archon-http.yml up -d"
        exit 1
    fi
    
    success "Environment configuration valid ✅"
}

# Function to pull latest images
pull_images() {
    log "📥 Pulling latest Archon images..."
    
    # Note: Using the original repository structure
    # These would need to be built images or available on Docker Hub
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull || {
        warn "Failed to pull some images - they may need to be built locally"
        warn "Building images instead..."
        
        # If images don't exist, we need to clone and build
        if [ ! -d "Archon" ]; then
            log "📂 Cloning Archon repository..."
            git clone https://github.com/coleam00/Archon.git
        fi
        
        # Use the original docker-compose from the repo for building
        if [ -f "Archon/docker-compose.yml" ]; then
            log "🔨 Building Archon images..."
            cd Archon
            docker compose --profile full build
            cd ..
            
            # Tag images for our deployment
            docker tag archon-archon-server:latest coleam00/archon-server:latest || true
            docker tag archon-archon-mcp:latest coleam00/archon-mcp:latest || true  
            docker tag archon-archon-agents:latest coleam00/archon-agents:latest || true
            docker tag archon-archon-frontend:latest coleam00/archon-frontend:latest || true
        fi
    }
}

# Function to stop existing deployment
stop_existing() {
    log "🛑 Stopping existing Archon deployment..."
    
    # Stop the deployment gracefully
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" down --remove-orphans || true
    
    # Clean up any orphaned containers
    docker container prune -f || true
    
    success "Previous deployment stopped ✅"
}

# Function to start services
start_services() {
    log "🚀 Starting Archon services..."
    
    # Create necessary directories
    mkdir -p nginx/logs
    mkdir -p certbot/{www,conf}
    
    # Start all services
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d
    
    if [ $? -eq 0 ]; then
        success "Archon services started ✅"
    else
        error "Failed to start services!"
        exit 1
    fi
}

# Function to wait for services to be healthy
wait_for_health() {
    log "⏳ Waiting for services to become healthy..."
    
    local services=("archon-server" "archon-mcp" "archon-agents" "archon-frontend")
    local max_wait=180 # 3 minutes
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        local healthy_count=0
        
        for service in "${services[@]}"; do
            if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$service.*healthy"; then
                ((healthy_count++))
            fi
        done
        
        if [ $healthy_count -eq ${#services[@]} ]; then
            success "All services are healthy ✅"
            return 0
        fi
        
        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    echo ""
    error "Services failed to become healthy within $max_wait seconds"
    echo ""
    echo "Service status:"
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps
    
    echo ""
    echo "Recent logs:"
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" logs --tail=20
    
    return 1
}

# Function to test endpoints
test_endpoints() {
    log "🧪 Testing service endpoints..."
    
    local endpoints=(
        "https://archon.transgate.ai:Frontend"
        "https://api.archon.transgate.ai:API"
    )
    
    for endpoint_info in "${endpoints[@]}"; do
        local endpoint=$(echo "$endpoint_info" | cut -d: -f1)
        local service=$(echo "$endpoint_info" | cut -d: -f2)
        
        echo -n "Testing $service ($endpoint)... "
        
        if curl -sf --max-time 10 "$endpoint" >/dev/null 2>&1; then
            echo "✅"
        else
            echo "❌"
            warn "$service endpoint not responding at $endpoint"
        fi
    done
}

# Function to show deployment info
show_deployment_info() {
    source "$ENV_FILE"
    
    echo ""
    echo "============================================================================"
    success "🎉 ARCHON DEPLOYMENT COMPLETE!"
    echo "============================================================================"
    echo ""
    echo "🌐 Service URLs:"
    echo "   Frontend (UI):  https://archon.transgate.ai"
    echo "   Backend API:    https://api.archon.transgate.ai"
    echo ""
    echo "📋 Service Status:"
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    echo "📁 Persistent Data:"
    echo "   Archon Data:    ./archon_data"
    echo "   Cache:          ./archon_cache"
    echo "   SSL Certs:      ./certbot/conf"
    echo "   Nginx Logs:     ./nginx/logs"
    echo ""
    echo "🔧 Management Commands:"
    echo "   View logs:      docker compose --env-file $ENV_FILE -f $COMPOSE_FILE logs -f"
    echo "   Stop services:  docker compose --env-file $ENV_FILE -f $COMPOSE_FILE down"
    echo "   Restart:        ./deploy-archon.sh"
    echo "   SSL renewal:    ./certbot-renew.sh"
    echo ""
    echo "⚙️  Configuration:"
    echo "   Environment:    $ENV_FILE"
    echo "   Compose file:   $COMPOSE_FILE"
    echo "   Nginx config:   ./nginx/conf.d/archon-ssl.conf"
    echo ""
    echo "📖 Next Steps:"
    echo "1. Access https://archon.transgate.ai to set up your knowledge base"
    echo "2. Configure AI API keys in the settings (if not set in env file)"
    echo "3. Set up automatic certificate renewal in crontab"
    echo "4. Consider setting up monitoring and backups"
    echo ""
    echo "🆘 Troubleshooting:"
    echo "   Check logs:     docker compose --env-file $ENV_FILE -f $COMPOSE_FILE logs [service-name]"
    echo "   Health check:   docker ps"
    echo "   Test SSL:       curl -I https://archon.transgate.ai"
    echo ""
}

# Main execution function
main() {
    echo "============================================================================"
    echo "🚀 ARCHON OS DEPLOYMENT"
    echo "============================================================================"
    echo ""
    
    # Run all deployment steps
    check_prerequisites
    validate_environment
    pull_images
    stop_existing
    start_services
    
    # Wait for services and test
    if wait_for_health; then
        test_endpoints
        show_deployment_info
        
        echo ""
        success "Deployment completed successfully! 🎉"
        echo ""
        echo "Visit https://archon.transgate.ai to get started!"
        
    else
        error "Deployment failed - services did not start properly"
        echo ""
        echo "Check the logs for more details:"
        echo "  docker compose --env-file $ENV_FILE -f $COMPOSE_FILE logs"
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --stop         Stop running services"
        echo "  --logs         Show service logs"
        echo "  --status       Show service status"
        echo ""
        echo "Environment file: $ENV_FILE"
        echo "Compose file: $COMPOSE_FILE"
        ;;
        
    --stop)
        log "Stopping Archon deployment..."
        docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" down
        success "Services stopped ✅"
        ;;
        
    --logs)
        docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" logs -f
        ;;
        
    --status)
        echo "Service Status:"
        docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps
        ;;
        
    "")
        main
        ;;
        
    *)
        error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
