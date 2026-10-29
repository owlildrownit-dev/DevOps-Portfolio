# RailControl

**Offline Railway Station Management System**

RailControl is a browser-based information system prototype for managing railway station operations, train schedules, passenger bookings, employees, and operational tasks.

The application demonstrates a modular administrative interface with role-based navigation, local data persistence, scheduling conflict detection, and a simulated asynchronous API.

It is implemented using HTML, CSS, and vanilla JavaScript, without requiring a backend server or external database.

> **Status:** Functional academic prototype with demonstration data. It is not intended for production railway operations.

## Technology Stack

| Component | Technology |
|---|---|
| User interface | HTML5, CSS3 |
| Application logic | Vanilla JavaScript |
| Data storage | Browser `localStorage` |
| Session state | Browser `sessionStorage` |
| API abstraction | Asynchronous in-browser API |
| Deployment | Static files |
| Backend server | Not required |

## Key Features

### Dashboard

The dashboard provides an overview of railway station activity, including:

- Scheduled train services.
- Delayed departures.
- Platform and track conflicts.
- Operational tasks.
- Notifications.
- Role-specific statistics.

### Reference Data Management

The application maintains interconnected reference data for:

- Railway stations.
- Platforms and tracks.
- Trains and carriages.
- Passenger seats.
- Routes.

These entities support scheduling and ticketing operations.

### Scheduling and Dispatch

The dispatch module supports:

- Viewing scheduled train services.
- Managing service statuses.
- Recording delays.
- Assigning tracks and platforms.
- Identifying scheduling conflicts.
- Publishing operational notifications.

Conflict detection checks for overlapping use of tracks or platforms within a defined time window.

### Ticketing and Bookings

The ticketing module supports a demonstration workflow for:

1. Searching available train services.
2. Selecting a trip and seat.
3. Creating a reservation.
4. Issuing a ticket.
5. Canceling a reservation.
6. Processing a simulated refund.
7. Reviewing operation history.

All booking and payment-related operations are simulated locally. No external payment service is integrated.

### Employee and Task Management

Staff-facing functionality includes:

- Employee records and employment statuses.
- Task creation and assignment.
- Task priorities and deadlines.
- Board and table views.
- Task progress tracking.

### Notifications and Audit Log

The application includes:

- Operational notifications with audience restrictions.
- Notification read states.
- An activity log for selected user actions and data changes.
- A JSON export of the local application dataset.

## Demonstration Roles

RailControl provides three predefined roles.

| Module | Administrator | Operator | Passenger |
|---|---|---|---|
| Dashboard | Yes | Yes | Yes |
| Reference data | Yes | Yes | No |
| Scheduling and dispatch | Yes | Yes | No |
| Bookings and tickets | Yes | Yes | Yes |
| Employees | Yes | Yes | No |
| Tasks | Yes | Yes | No |
| Notifications | Yes | Yes | Yes |
| Audit log | Yes | No | No |

The login page provides buttons that populate the credentials for each demonstration role.

**Security note:** Authentication and role navigation are implemented entirely in the browser. Demo accounts and passwords are bundled with the client-side data. This is suitable for an isolated prototype, but does not provide production-grade authentication or authorization.

## Getting Started

### Prerequisites

- A modern browser with JavaScript enabled.
- An operating system capable of extracting ZIP files.

No Node.js installation, package manager, or backend service is required.

### Run the Application

1. Download [`RailControl.zip`](RailControl.zip).
2. Extract the archive.
3. Open `index.html` in a modern browser.
4. Choose a demonstration role on the login screen.
5. Sign in using the corresponding demonstration credentials.

The interface is currently available in Russian.

If a browser restricts local storage for files opened through `file://`, the extracted directory can be served through a local HTTP server.

For example, with Python installed:

```bash
python -m http.server 8000
```

Then open `http://localhost:8000`.

## Project Structure

The current release is distributed as an archive containing the following files:

```text
RailControl/
├── index.html
├── assets/
│   ├── css/
│   │   └── styles.css
│   └── js/
│       ├── app.js
│       ├── local-api.js
│       └── storage.js
└── README.md
```

### Component Responsibilities

| File | Responsibility |
|---|---|
| `index.html` | Application entry point |
| `assets/css/styles.css` | Visual styling and responsive layouts |
| `assets/js/app.js` | Interface rendering, navigation, forms, and business logic |
| `assets/js/local-api.js` | Asynchronous CRUD operations and demo authentication |
| `assets/js/storage.js` | Application state, seed data, and browser storage |

## Data Architecture

RailControl uses a browser-based data model.

### Local Persistence

The application stores its main dataset in `localStorage`. Data remains available across page reloads within the same browser storage context.

The active user session is tracked using `sessionStorage`.

### Simulated API

The application uses an asynchronous API abstraction to access local collections.

Supported operations include:

- Listing records.
- Retrieving individual records.
- Creating records.
- Updating records.
- Removing records.
- Checking demonstration login credentials.

This API does not make HTTP requests to a backend. It operates on client-side state and persists changes locally.

### Initial Dataset

On first initialization, the application creates demonstration records for railway infrastructure, train services, users, bookings, employees, tasks, and notifications.

The interface also provides an option to reset local changes and restore the initial demonstration data.

## Manual Verification

The following steps can be used to explore the main workflows:

1. Sign in as an administrator and inspect the dashboard.
2. Open the reference data section.
3. Review scheduled train services and detected resource conflicts.
4. Sign in as a passenger and inspect ticket search and booking functionality.
5. Sign in as an operator and inspect employee tasks.
6. Create or update a demonstration record.
7. Reload the application and check whether the data persists.
8. Export the dataset to JSON.
9. Reset the demonstration data.

These are suggested manual verification steps, not a claim of completed automated test coverage.

## Limitations

RailControl is a frontend-only prototype with several intentional limitations:

- No backend database or centralized storage.
- No synchronization between users or devices.
- No secure server-side authentication.
- No server-enforced access control.
- No integration with external railway information systems.
- No real payment processing.
- No automated production deployment pipeline.
- Browser storage can be cleared or modified by the user.

The scheduling, booking, and operational workflows are demonstrations of application behavior rather than integrations with real railway infrastructure.

## Project Background

RailControl originated as an academic software engineering project at MTUSI.

It demonstrates user interface development, data modeling, state management, role-based workflows, CRUD operations, and the separation of application logic from a simulated data-access layer.

## Repository

This project is part of the [DevOps Engineering Portfolio](../../README.md).

Its original Git repository history was preserved during migration into the portfolio monorepository.
