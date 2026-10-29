# DevOps Labs - Engineering Notes and Experiments

A workspace for small, reproducible DevOps exercises, technical notes, and troubleshooting experiments.

The goal of this directory is to maintain practical documentation that explains not only which commands were used, but also why they were used, how results were verified, and what limitations were encountered.

> **Status:** Documentation scaffold. No completed laboratory reports or executable exercises have been published in this directory yet.

## Planned Topics

The following areas are candidates for future exercises:

| Area | Potential exercises |
| --- | --- |
| Linux | Process management, permissions, system diagnostics |
| Networking | DNS, TCP/IP, connectivity testing, routing |
| Docker | Images, containers, volumes, networking |
| Kubernetes | Workloads, Services, troubleshooting |
| Automation | Bash scripts and repeatable administrative tasks |
| Infrastructure as Code | Terraform configuration and validation |
| CI/CD | Automated testing and build pipelines |

These are planned topics, not completed implementations.

## Documentation Approach

Each completed lab should contain:

1. **Objective** - the problem being investigated.
2. **Environment** - software versions and prerequisites.
3. **Implementation** - commands and configuration.
4. **Verification** - tests and expected results.
5. **Findings** - observations and technical conclusions.
6. **Cleanup** - how to safely remove temporary resources.
7. **Limitations** - known issues or conditions affecting the results.

## Current Structure

```text
labs/
  README.md
  docs/
    commands.md
    troubleshooting.md
```

The documents under `docs/` are currently placeholders for future material.

## Related Projects

Completed technical implementations and their documentation are available elsewhere in the portfolio:

- [Orders Platform](../orders-platform/) - Terraform, Ansible, Docker, Kubernetes, and performance measurements.
- [CI/CD Demo](../ci-cd-demo/) - GitHub Actions, automated tests, and GitHub Pages deployment.
- [Kubernetes Flask](../kubernetes-flask/) - Docker containerization and local Kubernetes deployment.

## Repository History

This directory was migrated from the original [devops-labs repository](https://github.com/owlildrownit-dev/devops-labs) into the [DevOps Engineering Portfolio](../../README.md), preserving its Git history.
