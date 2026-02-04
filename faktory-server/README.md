# Faktory Server Setup

Personal job queue server running on your home Linux server, accessible only via Tailscale.

## Prerequisites

- Docker and docker-compose installed
- Tailscale installed and connected to your tailnet

## Setup

1. **Copy this directory to your home server:**
   ```bash
   scp -r faktory-server/ your-server:~/faktory-server/
   ```

2. **On your server, find your Tailscale IP:**
   ```bash
   tailscale ip -4
   # Example output: 100.64.0.10
   ```

3. **Create your `.env` file:**
   ```bash
   cd ~/faktory-server
   cp .env.example .env

   # Edit .env with your values:
   # - Set TAILSCALE_IP to your server's Tailscale IP
   # - Generate a password: openssl rand -hex 16
   ```

4. **Start Faktory:**
   ```bash
   docker-compose up -d
   ```

5. **Verify it's running:**
   ```bash
   docker-compose logs -f faktory
   ```

## Access

- **Web UI:** http://100.x.x.x:7420 (replace with your Tailscale IP)
- **Worker port:** tcp://100.x.x.x:7419

## Worker Connection URL

Workers connect using this URL format:
```
FAKTORY_URL=tcp://:your-password@100.x.x.x:7419
```

## Useful Commands

```bash
# View logs
docker-compose logs -f faktory

# Restart
docker-compose restart faktory

# Stop
docker-compose down

# Update to latest version
docker-compose pull && docker-compose up -d
```

## Security Notes

- Faktory only binds to your Tailscale IP, not public interfaces
- Traffic is encrypted via Tailscale's WireGuard
- Password authentication adds another layer of protection
- Web UI uses same password via HTTP Basic Auth
