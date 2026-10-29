# Daniil Krivoshein — DevOps Engineering Portfolio

A collection of hands-on projects focused on infrastructure automation, containerization, Kubernetes, CI/CD, performance analysis, and operational troubleshooting.

This monorepository brings together six projects while preserving their original Git commit histories. Each project remains self-contained and has its own documentation.

## Technical Focus

| Area | Tools and technologies |
| --- | --- |
| Infrastructure as Code | Terraform, Ansible |
| Containers and orchestration | Docker, Kubernetes, Helm, kind, Minikube |
| CI/CD | GitHub Actions, automated linting, testing, builds, and deployment |
| Systems and scripting | Linux, Bash, Python |
| Applications and data | Flask, FastAPI, PostgreSQL, JavaScript, Node.js |

## Featured DevOps Projects

### 1. [Orders Platform — Infrastructure Automation and Kubernetes](devops/orders-platform/)

A practical DevOps environment built around a Flask API backed by PostgreSQL.

- Provisions network, storage, and database resources with **Terraform**.
- Automates application deployment, database migrations, rolling updates, Nginx configuration, and smoke checks with **Ansible**.
- Runs the application on **Kubernetes** using a Helm chart with Deployment, Service, Ingress, HPA, and PDB resources.
- Includes repeatable benchmarks, deployment measurements, incident notes, and screenshots.

**Selected results from a synthetic GitHub Codespaces test environment:**

| Measurement | Before | After |
| --- | ---: | ---: |
| Docker image size | 704.2 MiB | 198.0 MiB (71.9% smaller) |
| PostgreSQL CPU time, 120-second test at 3 TPS | 125.09 s | 0.43 s (99.7% lower) |
| Horizontal Pod Autoscaler | 2 replicas | Scaled to 5 under load |

These figures describe the documented test setup, not production performance. See the [project README](devops/orders-platform/README.md) for methodology, raw results, and limitations.

### 2. [CI/CD Demo — Automated Quality Gates and Deployment](devops/ci-cd-demo/)

A JavaScript/Vite application used to demonstrate a GitHub Actions CI/CD pipeline.

- Installs dependencies using `npm ci`.
- Runs **ESLint** checks and **Vitest** tests before building.
- Produces a Vite distribution artifact and deploys the standalone demonstration to **GitHub Pages**.
- Includes a deliberate failing-test scenario showing that deployment is skipped when the CI job fails.

[Project documentation](devops/ci-cd-demo/README.md) · [Original CI/CD run history](https://github.com/owlildrownit-dev/demopipeline/actions)

### 3. [Kubernetes Flask Deployment](devops/kubernetes-flask/)

A containerized Flask service deployed to a local Kubernetes cluster with **Minikube**.

- Builds and runs the application with **Docker**.
- Defines Kubernetes Deployment and Service resources.
- Uses a two-replica Deployment and a LoadBalancer Service in the documented Minikube setup.
- Includes architecture diagrams, deployment evidence, and screenshots from Headlamp.

[Project documentation](devops/kubernetes-flask/README.md)

## Additional Engineering Projects

### [Red Light Detector](projects/red-light-detector/)

A Python application for analyzing images and video to identify vehicles crossing a stop line during a red traffic signal. Built with **FastAPI, OpenCV, YOLOv8n (ONNX Runtime)**, and an optional desktop interface. Supports exporting analysis reports as PDF and Excel files.

[Project documentation](projects/red-light-detector/README.md)

### [RailControl](projects/rail-control/)

An offline, browser-based railway station management system created for academic practice. It uses JavaScript and browser storage to demonstrate user roles and application workflows. The original application is included as an archive.

[Project documentation](projects/rail-control/README.md)

### [DevOps Labs](devops/labs/)

An early-stage collection of DevOps study notes and experiments. Documentation is still being developed.

## Repository Layout

```text
devops/
  orders-platform/       Terraform, Ansible, Docker, Kubernetes, benchmarks
  ci-cd-demo/            GitHub Actions, Vite, linting and tests
  kubernetes-flask/      Docker and Minikube deployment
  labs/                  Notes and experiments

projects/
  red-light-detector/    Python, FastAPI, computer vision
  rail-control/          Browser-based application
```

## Working with the Projects

Each directory is an independent project. Start with its README for prerequisites, setup, and verification steps; there is no single command that runs the entire portfolio.

**Monorepo migration note:** Project histories are preserved, but the original CI/CD and Codespaces configurations were written for standalone repositories. Their paths and triggers must be reviewed before using them directly from this monorepository.

## Contact

- GitHub: [@owlildrownit-dev](https://github.com/owlildrownit-dev)
