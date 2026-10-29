# Daniil Krivoshein - DevOps Engineering Portfolio

A collection of hands-on engineering projects focused on infrastructure automation, CI/CD, containerization, Kubernetes, Infrastructure as Code, performance optimization, and operational troubleshooting.

This monorepository consolidates six projects while preserving their original Git commit histories.

[![Demo Pipeline](https://github.com/owlildrownit-dev/DevOps-Portfolio/actions/workflows/ci-demo.yml/badge.svg)](https://github.com/owlildrownit-dev/DevOps-Portfolio/actions/workflows/ci-demo.yml)
[![Orders Platform](https://github.com/owlildrownit-dev/DevOps-Portfolio/actions/workflows/ci-orders.yml/badge.svg)](https://github.com/owlildrownit-dev/DevOps-Portfolio/actions/workflows/ci-orders.yml)
[![Kubernetes Flask](https://github.com/owlildrownit-dev/DevOps-Portfolio/actions/workflows/ci-kubernetes-flask.yml/badge.svg)](https://github.com/owlildrownit-dev/DevOps-Portfolio/actions/workflows/ci-kubernetes-flask.yml)
[![Infrastructure Validation](https://github.com/owlildrownit-dev/DevOps-Portfolio/actions/workflows/ci-infrastructure.yml/badge.svg)](https://github.com/owlildrownit-dev/DevOps-Portfolio/actions/workflows/ci-infrastructure.yml)

**[Live CI/CD Demo](https://owlildrownit-dev.github.io/DevOps-Portfolio/)** | **[GitHub Actions](https://github.com/owlildrownit-dev/DevOps-Portfolio/actions)**

## Technical Focus

| Area | Tools and technologies |
| --- | --- |
| Infrastructure as Code | Terraform, Ansible |
| Containers and orchestration | Docker, Kubernetes, Helm, kind, Minikube |
| CI/CD | GitHub Actions, GitHub Container Registry, GitHub Pages |
| Systems and scripting | Linux, Bash, Python |
| Applications and databases | Flask, FastAPI, PostgreSQL, JavaScript, Node.js |
| Quality and validation | ESLint, Vitest, Docker builds, Terraform validation, Helm linting |

## CI/CD and Infrastructure Automation

The repository includes four GitHub Actions workflows covering automated testing, container builds, artifact publishing, static site deployment, and infrastructure configuration validation.

Workflows support manual execution and use path filters to run automatically when relevant files change.

### Automated Workflows

| Workflow | Validation and delivery |
| --- | --- |
| [CI/CD - Demo Pipeline](.github/workflows/ci-demo.yml) | npm ci, ESLint, Vitest, Vite build, GitHub Pages deployment |
| [CI/CD - Orders Platform](.github/workflows/ci-orders.yml) | Docker build and GHCR publication |
| [CI/CD - Kubernetes Flask](.github/workflows/ci-kubernetes-flask.yml) | Docker build and GHCR publication |
| [CI - Infrastructure Validation](.github/workflows/ci-infrastructure.yml) | Terraform formatting and validation, Helm linting and template rendering |

### Container Image Publishing

Docker images are built and published to **GitHub Container Registry (GHCR)** after successful builds triggered by pushes to `main`.

| Project | GHCR image |
| --- | --- |
| Orders Platform | `ghcr.io/owlildrownit-dev/devops-portfolio-orders` |
| Kubernetes Flask | `ghcr.io/owlildrownit-dev/devops-portfolio-kubernetes-flask` |

Each image receives:

- `latest` - the most recently published version from `main`.
- `sha-<commit>` - an immutable reference to the source commit used for the build.

Pull access depends on the package visibility settings in GitHub Packages.

For pull requests, the Docker workflows validate builds without publishing images.

### Automated Deployment to GitHub Pages

The CI/CD Demo uses a build-and-deploy pipeline:

1. Install dependencies.
2. Run ESLint checks.
3. Execute Vitest tests.
4. Build the Vite application.
5. Upload the GitHub Pages artifact.
6. Deploy the site after successful validation on `main`.

Deployment is skipped for pull requests.

**Live application:** https://owlildrownit-dev.github.io/DevOps-Portfolio/

### Terraform and Helm Validation

The infrastructure validation workflow checks the Orders Platform configuration without provisioning resources.

**Terraform**

- `terraform fmt -check` verifies consistent formatting.
- `terraform init -backend=false` initializes providers without configuring a remote backend.
- `terraform validate` checks configuration syntax and internal consistency.

**Helm**

- `helm lint --strict` validates the `orders-api` chart.
- `helm template` renders Kubernetes manifests for inspection.

These checks do not execute `terraform apply`, `helm install`, or `kubectl apply`.

## Featured DevOps Projects

### 1. [Orders Platform - Infrastructure Automation and Kubernetes](devops/orders-platform/)

A practical DevOps environment built around a Flask API backed by PostgreSQL.

- Provisions network, storage, and database resources with **Terraform**.
- Automates database migrations, application deployment, rolling updates, Nginx configuration, and smoke checks with **Ansible**.
- Deploys the application on **Kubernetes** using Helm, including Deployment, Service, Ingress, HPA, and PDB resources.
- Includes infrastructure benchmarks, deployment measurements, incident notes, and supporting screenshots.
- Uses GitHub Actions to validate infrastructure configuration, build Docker images, and publish them to GHCR.

**Selected results from a synthetic GitHub Codespaces test environment:**

| Measurement | Before | After |
| --- | ---: | ---: |
| Docker image size | 704.2 MiB | 198.0 MiB (71.9% smaller) |
| PostgreSQL CPU time, 120-second test at 3 TPS | 125.09 s | 0.43 s (99.7% lower) |
| Horizontal Pod Autoscaler | 2 replicas | Scaled to 5 under load |

These measurements describe the documented test environment, not production performance.

See the [Orders Platform documentation](devops/orders-platform/README.md) for methodology, raw results, and limitations.

### 2. [CI/CD Demo - Automated Testing and Deployment](devops/ci-cd-demo/)

A JavaScript/Vite application demonstrating a GitHub Actions pipeline with automated quality gates and deployment.

- Installs dependencies using `npm ci`.
- Validates code with **ESLint**.
- Runs automated tests with **Vitest**.
- Builds a production-ready Vite distribution.
- Automatically deploys the application to **GitHub Pages** after successful validation on `main`.
- Preserves the original failing-test scenario in Git history to demonstrate CI failure handling.

**[Open Live Demo](https://owlildrownit-dev.github.io/DevOps-Portfolio/)** | **[Project Documentation](devops/ci-cd-demo/README.md)** | **[CI/CD Workflow](.github/workflows/ci-demo.yml)**

### 3. [Kubernetes Flask Deployment](devops/kubernetes-flask/)

A containerized Flask application deployed to a local Kubernetes cluster using **Minikube**.

- Builds the application with **Docker**.
- Defines Kubernetes Deployment and Service resources.
- Uses a two-replica Deployment and a LoadBalancer Service in the documented Minikube environment.
- Includes deployment diagrams, verification evidence, and Headlamp screenshots.
- Uses GitHub Actions for automated Docker builds and GHCR publishing.

[Project Documentation](devops/kubernetes-flask/README.md) | [CI/CD Workflow](.github/workflows/ci-kubernetes-flask.yml)

## Additional Engineering Projects

### [Red Light Detector](projects/red-light-detector/)

A Python application for analyzing images and video to identify vehicles crossing a stop line during a red traffic signal.

Built with **FastAPI, OpenCV, YOLOv8n (ONNX Runtime)**, and an optional desktop interface. Supports exporting analysis reports as PDF and Excel files.

[Project Documentation](projects/red-light-detector/README.md)

### [RailControl](projects/rail-control/)

An offline, browser-based railway station management application developed for academic practice.

Uses JavaScript and browser storage to demonstrate user roles and application workflows. The original application is included as an archive.

[Project Documentation](projects/rail-control/README.md)

### [DevOps Labs](devops/labs/)

An early-stage collection of DevOps notes and experiments. Documentation is still being developed.

## Repository Structure

```text
.github/
  workflows/
    ci-demo.yml
    ci-orders.yml
    ci-kubernetes-flask.yml
    ci-infrastructure.yml

devops/
  orders-platform/
  ci-cd-demo/
  kubernetes-flask/
  labs/

projects/
  red-light-detector/
  rail-control/
```

## Working with the Projects

Each project has its own directory and documentation. Follow the relevant project README for prerequisites, setup instructions, and verification procedures.

The repository does not provide a single command to run every project.

## Migration and Git History

Six repositories were consolidated into this monorepository using Git subtree operations without squashing their source commit histories.

The original project histories remain available in the monorepository's Git history.

After migration and verification, the temporary import workflow was removed. Active CI/CD workflows are maintained in the repository's root `.github/workflows/` directory.

Some original repository-specific configurations remain in their respective project directories for historical reference.

## Contact

- GitHub: [@owlildrownit-dev](https://github.com/owlildrownit-dev)
