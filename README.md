# ZITADEL Docker Compose Setup

This repository contains a Docker Compose setup for ZITADEL configured to work at `zitadel-7f000001.nip.io`.

## Features

- ZITADEL accessible at `http://zitadel-7f000001.nip.io:8080` from both Docker containers and host
- Multi-architecture support (AMD64 and ARM64)
- Bootstrap service for automatic project/app/user creation
- PostgreSQL database backend

## Quick Start

1. Start the services:
```bash
docker-compose up -d
```

2. Access ZITADEL Console:
- URL: http://zitadel-7f000001.nip.io:8080/ui/console
- Default admin login: `zitadel-admin@zitadel.zitadel-7f000001.nip.io`
- Default password: `Password1!`

http://zitadel-7f000001.nip.io:8080/ui/console?login_hint=zitadel-admin@zitadel.zitadel-7f000001.nip.io

http://zitadel-7f000001.nip.io:8080/ui/console?login_hint=bob@example.com
http://zitadel-7f000001.nip.io:8080/ui/console?login_hint=alice@example.com

3. Run the bootstrap (optional - requires admin PAT):
```bash
docker-compose run --rm zitadel-bootstrap
```

## Bootstrap Configuration

The bootstrap service automatically creates:
- A project named "local-dev"
- An OIDC application named "go-web-app"
- Test users: alice and bob

**Note:** The bootstrap requires an admin Personal Access Token (PAT). To generate one:

1. Log into the ZITADEL console
2. Create a service user with IAM_OWNER role
3. Generate a PAT for the service user
4. Save it as `admin.pat` in the project root
5. Update `docker-compose.yaml` to use `admin.pat` instead of `login-client.pat` in the bootstrap service

## Network Configuration

The setup uses `zitadel-7f000001.nip.io` which resolves to 127.0.0.1, making it accessible from:
- The Docker host at `http://zitadel-7f000001.nip.io:8080`
- Docker containers using the same hostname (via network alias)

## Architecture Support

The bootstrap container supports both AMD64 and ARM64 architectures automatically.

## Services

- **zitadel**: Main ZITADEL instance
- **login**: ZITADEL login UI v2
- **db**: PostgreSQL database
- **zitadel-bootstrap**: Bootstrap service for initial setup

## Ports

- `8080`: ZITADEL API and Console
- `3000`: Login UI v2
- `5432`: PostgreSQL database