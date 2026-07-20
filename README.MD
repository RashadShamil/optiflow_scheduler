# 🖨️ OptiFlow V2: Enterprise Print Shop Scheduler

![Flutter](https://img.shields.io/badge/Frontend-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![FastAPI](https://img.shields.io/badge/Backend-FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white)
![Python](https://img.shields.io/badge/Engine-Python_3.10-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Google OR-Tools](https://img.shields.io/badge/Optimization-CP--SAT-FF6F00?style=for-the-badge&logo=google&logoColor=white)
![Supabase](https://img.shields.io/badge/Database-Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)

OptiFlow is an enterprise-grade Operations Research system and ERP built to solve the **Flexible Job Shop Scheduling Problem (FJSP)** for high-volume manufacturing and print environments. 

Moving beyond legacy heuristic/CRUD rule-based systems, OptiFlow V2 utilizes **Constraint Programming (CP-SAT)** via Google OR-Tools to mathematically optimize factory throughput while strictly enforcing physical manufacturing constraints (Directed Acyclic Graphs).

---

## 📖 Table of Contents
- [System Architecture](#️-system-architecture)
- [Key Features](#-key-features)
- [Project Directory Structure](#-project-directory-structure)
- [The Mathematical Engine](#-the-mathematical-engine)
- [Database Schema](#-database-schema)
- [REST API Structure](#-rest-api-structure)
- [Local Installation & Setup](#️-local-installation--setup)
- [Agile Methodology](#-agile-methodology)

---

## 🏗️ System Architecture

OptiFlow V2 is built using a decoupled, API-first architecture, allowing high-performance mathematical modeling on the backend and cross-platform flexibility on the frontend.

*   **The Backend (Python/FastAPI):** A highly modular REST API handling all data validation (Pydantic), PostgreSQL transactions, and heavy algorithmic calculations.
*   **The Frontend (Flutter):** A 100% single-codebase UI utilizing responsive `LayoutBuilder` logic to serve two distinct experiences:
    *   **Desktop Manager App:** A wide-screen dashboard featuring dynamic DAG form builders, Skills Matrix configuration, and an interactive Gantt chart schedule.
    *   **Mobile Worker App:** A narrow-screen, mobile-first telemetry application used by factory floor workers to receive, start, and complete scheduled tasks.

---

## ✨ Key Features

### 1. Advanced Order Pipeline (DAGs)
Print orders are no longer treated as flat entities. Managers can dynamically build multi-step manufacturing pipelines (e.g., Print $\rightarrow$ Ink Cure $\rightarrow$ Fold $\rightarrow$ Bind) and enforce mandatory chronological wait times between tasks.

### 2. Algorithmic Schedule Optimization
A single click triggers the C++ CP-SAT solver. The engine evaluates millions of schedule permutations to find the optimal assignment of machines and workers, balancing processing speed against operational costs to minimize the overall **Makespan**.

### 3. Centralized Skills Matrix
A highly relational tracking system mapping `Resources` (humans and machines) to specific `Capabilities` (e.g., CMYK Printing, Binding), enforcing strict data integrity for processing speeds (units/hr) and financial overhead.

### 4. Real-Time Worker Execution (Mobile)
A dedicated mobile interface strictly partitioned by Row-Level/Application logic. Workers only see tasks mathematically assigned to them, allowing them to shift states from `SCHEDULED` $\rightarrow$ `IN_PROGRESS` $\rightarrow$ `COMPLETED` seamlessly.

---

## 📂 Project Directory Structure

```text
e22-co2060-OptiFlow/
├── README.MD                   # Main project documentation
├── optiflow_back/              # Backend (Python / FastAPI / OR-Tools)
│   ├── main.py                 # App entrypoint, middleware, & legacy routes
│   ├── route.py                # CRUD operations & Optimization router
│   ├── optimizer.py            # Google OR-Tools CP-SAT scheduler algorithm
│   ├── models.py               # Pydantic input validation models
│   ├── databse.py              # Supabase PostgreSQL client initializer
│   ├── booking_manager.py      # Resource booking & conflict check helpers
│   ├── seed_db.py              # Minimal DB seed script (human resources)
│   ├── seed_pitch_data.py      # Complete database clear & pitch data seed script
│   ├── requirements.txt        # Python dependency manifest
│   └── .env.local              # Local environment secrets (ignored by git)
└── optiflow_front/             # Frontend (Flutter / Riverpod)
    ├── lib/
    │   ├── main.dart           # App entrypoint (initializes Supabase/Theme/Router)
    │   ├── core/               # Shared models, services, & utilities
    │   │   ├── services/       # http API service & Supabase Authentication client
    │   │   └── models/         # App-wide Dart data representations (Job, Task, etc.)
    │   ├── mobile/             # Worker Telemetry Interface (Mobile screens & widgets)
    │   └── slices/             # Manager Interface Slices (Admin, Engine, Order)
    ├── assets/                 # Images, icons, and fonts
    ├── pubspec.yaml            # Flutter project dependencies
    └── run_dashboard.bat       # Convenience launch script for Windows target
```

---

## 🧠 The Mathematical Engine

The core brain of OptiFlow (`optimizer.py`) is powered by **Google OR-Tools**.

The algorithm dynamically ingests the factory's current state from PostgreSQL and constructs a mathematical universe:
1.  **Optional Intervals:** Creates Boolean "switches" for every capable machine/worker, forcing the solver to pick exactly *one* execution path per task.
2.  **Chronology Enforcement:** Translates the PostgreSQL DAGs into strictly enforced linear time dependencies ($Start_{B} \ge End_{A} + Wait$).
3.  **Disjunctive Constraints:** Utilizes `AddNoOverlap()` primitives to prevent machine double-booking.
4.  **Objective Function:** Aggressively minimizes the maximum completion time across the entire board.

---

## 🗄️ Database Schema

Hosted on **Supabase** (PostgreSQL), the architecture relies on a normalized 7-table schema to maintain data integrity:

1.  `profiles`: Application-level user roles.
2.  `operation_types`: Dictionary of factory capabilities.
3.  `resources`: Active registry of machines and human workers.
4.  `resource_capabilities`: The junction table defining the Skills Matrix.
5.  `jobs`: Overarching client orders.
6.  `tasks`: Atomic sub-components targeted by the scheduling engine.
7.  `task_dependencies`: The DAG edges enforcing chronological integrity.

---

## 🔌 REST API Structure

The backend application contains two main route layers exposed by FastAPI:

1. **Standard App Routes (`main.py`):**
   Exposed directly under the root context (no `/api` prefix). These routes handle legacy booking systems and direct job claims:
   - `POST /book_machine`
   - `GET /jobs`
   - `POST /claim_job`
   - `POST /create_job`

2. **Core Router Endpoints (`route.py`):**
   Grouped under the `/api` prefix (configured via `app.include_router(router, prefix="/api")`). These handle core capabilities and optimization requests:
   - `GET|POST|PUT|DELETE /api/operation-types`
   - `GET|POST|PUT|DELETE /api/resources`
   - `GET|POST|PUT /api/capabilities`
   - `POST /api/optimize/{job_id}` — Triggers the CP-SAT solver for a specific job order.

---

## 🛠️ Local Installation & Setup

### Prerequisites
*   Python 3.10+
*   Flutter SDK (Stable Channel)
*   Supabase Project (URL & Anon/Service Keys)

### Backend (FastAPI) Setup

1. **Navigate to the backend directory:**
   ```bash
   cd optiflow_back
   ```

2. **Create a virtual environment & activate it:**
   *   **On Windows:**
       ```bash
       python -m venv venv
       .\venv\Scripts\activate
       ```
   *   **On macOS/Linux:**
       ```bash
       python3 -m venv venv
       source venv/bin/activate
       ```

3. **Install python dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Environment Variables:**
   Create a `.env.local` file inside the `optiflow_back/` folder:
   ```ini
   SUPABASE_URL="your_supabase_project_url"
   SUPABASE_KEY="your_supabase_service_role_key"
   ```

5. **Seed the database (Optional but Recommended):**
   *   **Minimal Seed:** Check and populate standard team members (HUMAN resources):
       ```bash
       python seed_db.py
       ```
   *   **Full Reset & Pitch Seed:** Clear existing records and populate a fresh, complete set of demo jobs, tasks, operation types, capabilities, and dependencies:
       ```bash
       python seed_pitch_data.py
       ```

6. **Run the API server:**
   ```bash
   uvicorn main:app --reload
   ```
   * The live API documentation will be available at [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs).

---

### Frontend (Flutter) Setup

1. **Navigate to the frontend directory:**
   ```bash
   cd optiflow_front
   ```

2. **Get packages and dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the application:**
   *   **Windows Desktop:**
       Ensure Windows Developer Mode is enabled, then run:
       ```bash
       flutter run -d windows
       ```
       *(Alternatively, you can double-click or execute the convenience script `./run_dashboard.bat`)*.
   *   **Web (Chrome):**
       ```bash
       flutter run -d chrome
       ```
   *   **Mobile / Other Target Devices:**
       ```bash
       flutter run
       ```

---

## 👥 Agile Methodology

The development process of OptiFlow V2 followed rigorous Agile standards, split into critical engineering cycles:
*   **Sprint Planning & Backlog Grooming:** Translating operational challenges into granular tickets.
*   **Decoupled Slice Architecture:** Dividing features into discrete backend routers and frontend components (e.g. Admin Capabilities, Engine Optimization, Orders DAG form builders) to allow parallel work streams.
*   **Frequent Releases & Integration Testing:** Validating API request shapes through rigorous Pydantic contracts and Flutter telemetry logs.
