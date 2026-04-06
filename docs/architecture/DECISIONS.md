# Architecture Decision Records (ADRs)

This directory tracks important architectural decisions made during the project.

## Format

Each ADR follows this template:

```markdown
# ADR-NNN: Title

## Status
- [x] Proposed
- [x] Accepted
- [ ] Deprecated
- [ ] Superseded by ADR-XXX

## Context
Problem description, forces at play.

## Decision
Chosen solution and rationale.

## Consequences
Positive: what improves?
Negative: trade-offs, drawbacks
Risks: what could go wrong
```

---

## Current ADRs

### ADR-001: Blue-Green Deployment Strategy

**Status**: Accepted

**Context**:
- Need zero-downtime deployments
- Raspberry Pi limited resources (can't run multiple full copies simultaneously)
- Must be able to rollback quickly

**Decision**:
Implement blue-green deployment with two parallel container slots (blue, green). Only one slot is active at a time, determined by nginx upstream configuration. Deploy to inactive slot, validate with health checks, then atomically switch upstream and reload nginx.

**Consequences**:
- Positive: Zero-downtime deployments; instant rollback; test new version in production-like environment before switch
- Negative: Doubles resource usage during deployment (both slots running briefly); complexity of managing two slots; manual slot switching (until automated)
- Risks: If deployment script fails mid-way, could leave both slots partially deployed; need careful cleanup
- Mitigations: Health checks before switch; automated script with rollback; monitor both slots

---

### ADR-002: Nginx as API Gateway with Cloudflare Tunnel

**Status**: Accepted

**Context**:
- Raspberry Pi at home behind NAT/firewall
- Need external HTTPS access
- Want DDoS protection, SSL offload
- Multiple domains on single IP (port 80)

**Decision**:
Use Cloudflare Tunnel (cloudflared) to expose local services without opening firewall ports. Nginx acts as internal reverse proxy handling multiple hostnames. Cloudflare provides SSL termination, DDoS protection, and caching.

**Consequences**:
- Positive: No open firewall ports; Cloudflare security features; automatic SSL; works behind any NAT
- Negative: Dependency on Cloudflare (single point of failure); tunnel could disconnect; no direct IP access
- Risks: Cloudflare outage; tunnel credentials compromised
- Mitigations: Health monitoring; auto-reconnect; backup DNS records; quick tunnel regeneration

---

### ADR-003: Self-Hosted Docker Registry

**Status**: Accepted

**Context**:
- Need to store Docker images for ARM64 (Raspberry Pi)
- Want fast local pulls (no Docker Hub rate limits)
- May have private images

**Decision**:
Run self-hosted Docker registry on Pi (port 5000). Push images from CI/CD to registry, then pull from Pi during deployment.

**Consequences**:
- Positive: No rate limits; fast intra-network pulls; no external dependencies; full control
- Negative: Consumes Pi storage (images can be large); must secure registry; need backup strategy
- Risks: Registry disk fills up; registry hacked; images lost if Pi fails
- Mitigations: Image pruning; authentication; regular backups; consider separate storage

---

### ADR-004: Environment Files for Slot Configuration

**Status**: Accepted

**Context**:
- Blue and green slots need same application config except container image tag
- Need to inject different database credentials? (No – both connect to same DB)
- Environment variables per slot for flexibility

**Decision**:
Use separate `.env` files per slot (blue.env, green.env) mounted as read-only volumes. These live in `/home/applepie/server/releases/dynamic/app/{web,api}/` on the Pi (outside Git). Container image tag is controlled by docker-compose, not env file.

**Consequences**:
- Positive: Slot-specific configuration possible; visible current slot config; can swap slots without changing files
- Negative: Must maintain two env files (though usually identical except maybe for debugging flags)
- Risks: Env files out of sync; human error when updating
- Mitigations: Automate env file creation; use diff tool; keep in version control? (No – secrets)

---

### ADR-005: Persistent Uploads via Shared Volume

**Status**: Accepted

**Context**:
- User uploads must persist across container restarts and deployments
- Both old and new slot need access to same uploads
- Uploads should be served by nginx for performance

**Decision**:
Store uploads on host (`/home/applepie/server/data/uploads/app`) mounted as volume into `app_api` containers. Also mount into nginx for serving via `/uploads/` alias.

**Consequences**:
- Positive: Uploads survive container lifecycle; shared between slots; served efficiently by nginx
- Negative: Host directory must have correct permissions; backup required; can't scale horizontally (single volume)
- Risks: Disk fills up; permission issues; data corruption
- Mitigations: Regular backups; log rotation; disk monitoring; set quotas

---

### ADR-006: No Database per Slot

**Status**: Accepted

**Context**:
- Blue-green deployment could benefit from separate databases (test new schema)
- But would require data migration/sync between slots
- Single database simplifies architecture

**Decision**:
Use single PostgreSQL instance shared by both blue and green slots. Both connect to same database.

**Consequences**:
- Positive: Simple; data consistent across slots; no migration overhead
- Negative: New code must be backward-compatible with old database schema (or forward-compatible with old code); can't test schema changes in isolation
- Risks: Schema change breaks old slot before switch; data corruption
- Mitigations: Test schema changes thoroughly in dev; use migrations with rollback; keep both slots on compatible schema versions

---

### ADR-007: ARM64-Only Images

**Status**: Accepted

**Context**:
- Raspberry Pi uses ARM64 architecture
- Docker Desktop defaults to amd64
- CI/CD needs to build for Pi

**Decision**:
Build all Docker images for `linux/arm64` platform only. Multi-arch builds (including amd64) not needed.

**Consequences**:
- Positive: Simpler builds; smaller image size; optimized for Pi
- Negative: Can't run same images on x86 servers without buildx; limits flexibility
- Risks: Need to rebuild for other architectures if needed
- Mitigations: Document build process for other arch; use buildx if multi-arch needed later

---

### ADR-008: Health Checks via HTTP Endpoint

**Status**: Accepted

**Context**:
- Need to know when containers are ready
- Docker has built-in healthcheck but needs endpoint
- Want to verify app is fully initialized (DB connected, etc.)

**Decision**:
Implement `/health` endpoint in both web and API apps that returns 200 OK only when:
- Database connection healthy
- All required services reachable
- Caches warmed (if applicable)

Docker healthcheck uses `curl -f http://localhost:3000/health` with timeout and interval.

**Consequences**:
- Positive: Accurate readiness detection; prevents traffic before app ready; enables blue-green automation
- Negative: Extra development work to implement endpoint
- Risks: Health check flapping; resource contention on health checks
- Mitigations: Proper retry logic; debounce thresholds; cache health results

---

## Future ADRs (to be written)

- ADR-009: Logging strategy (centralized vs. container logs)
- ADR-010: Monitoring and alerting approach (Prometheus vs. simple)
- ADR-011: Configuration management tool (Ansible vs. manual)
- ADR-012: Backup retention policy (daily vs. hourly, offsite location)
- ADR-013: Security hardening measures (firewall, fail2ban, auth)

---

## How to Propose a New ADR

1. Copy the template below into a new file: `docs/architecture/ADR-XXX-title.md`
2. Fill in all sections (Context, Decision, Consequences)
3. Discuss with team/yourself
4. Update status to "Accepted" after review
5. Update this index

## Template

```markdown
# ADR-XXX: Title

## Status
- [ ] Proposed
- [ ] Accepted
- [ ] Deprecated
- [ ] Superseded by ADR-XXX

## Context
<!-- Describe the problem, forces, and constraints -->

## Decision
<!-- What decision was made and why -->

## Consequences
<!-- Positive: what improves? -->
<!-- Negative: trade-offs -->
<!-- Risks: what could go wrong? -->
<!-- Mitigations: how to address risks? -->
```
