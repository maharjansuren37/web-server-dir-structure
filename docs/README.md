# Documentation

This directory contains all project documentation, runbooks, and operational guides for the Raspberry Pi web server infrastructure.

## Structure

```
docs/
├── project/              # Project management
│   ├── TODO.md          # Master task list with priorities
│   └── DECISIONS.md     # Architecture decision records (ADRs)
├── architecture/        # System design
│   ├── OVERVIEW.md      # High-level architecture
│   ├── diagrams/        # Architecture diagrams (draw.io, mermaid)
│   └── deployment.md    # Deployment strategy details
├── operations/          # Day-to-day operations
│   ├── RUNBOOK.md       # Troubleshooting guide
│   ├── RECOVERY.md      # Disaster recovery procedures
│   ├── backups.md       # Backup and restore procedures
│   └── monitoring.md    # Monitoring setup and alerting
├── development/         # Developer guide
│   ├── setup.md         # Local development environment
│   ├── testing.md       # Testing strategies and commands
│   └── contributing.md  # Contribution guidelines
└── reference/           # Reference material
    ├── configs/         # Configuration explanations
    ├── variables.md     # Environment variables reference
    └── ports.md         # Network ports and services
```

## Key Documents

- **[TODO.md](project/TODO.md)** - Start here. Complete task list with priorities and dependencies.
- **[RUNBOOK.md](operations/RUNBOOK.md)** - For troubleshooting when things break.
- **[RECOVERY.md](operations/RECOVERY.md)** - For disaster recovery (data loss, server failure).
- **[OVERVIEW.md](architecture/OVERVIEW.md)** - For understanding the system architecture.

## Keeping Documentation Updated

- Update `TODO.md` when completing tasks or adding new ones
- Document design decisions in `DECISIONS.md` (what, why, alternatives)
- Update runbooks when you discover new troubleshooting steps
- Keep configuration explanations in sync with actual configs
