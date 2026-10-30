# SPI Inventory Management System

A comprehensive electronic component inventory management solution designed for tracking components, LCSC parts, stock transactions, and audit logs. The system consists of a cross-platform Flutter desktop client and an automated MySQL database backend.

---

## 📌 Table of Contents
- [Architecture Overview](#architecture-overview)
- [Key Features](#key-features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [1. Backend & Database Setup](#1-backend--database-setup)
  - [2. Frontend Setup (Flutter)](#2-frontend-setup-flutter)
- [Database Schema & Roles](#database-schema--roles)
- [Hardware & Scanner Integration](#hardware--scanner-integration)
- [Reporting & Data Export](#reporting--data-export)

---

## 🏗 Architecture Overview

- **Frontend Client (`FronEnd/inventry_frontend`)**:
  - Developed with **Flutter** (targeted for Windows Desktop).
  - State management powered by **Provider**.
  - Direct MySQL connection via `mysql_client`.
  - Serial port communication via `serial_port_win32` for barcode scanners.
  - LCSC API integration for fetching component metadata.
  - Data export to **Excel**, **PDF**, and **CSV**.

- **Backend & Database Initializer (`Inventry Backend/`)**:
  - Automated MySQL 8.0 installer and service initializer in **Python**.
  - Configures the Windows service `Inventry_Management`.
  - Sets up the schema `CompanentsInventry`, default users, and access privileges.
  - Standalone executable (`InventryDB_Setup.exe`) for zero-dependency deployment.

---

## ✨ Key Features

- **Component Management**: Track electronic components with LCSC Part numbers, Manufacturer Part Numbers (MPN), descriptions, and quantities (Current & Used).
- **LCSC API Synchronization**: Fetch real-time component information directly from LCSC.
- **Hardware Barcode & Serial Scanner Support**: Connect USB/COM serial barcode scanners on Windows for rapid scanning of component reels and labels.
- **Audit & Event History**: Automatically logs all inventory actions (Stock In, Stock Out, adjustments) with timestamps and user associations.
- **Role-Based Access Control**: Multi-user login system with user and admin access management.
- **Export & Reports**: Export inventory listings and event logs to Excel (.xlsx), PDF, and CSV formats.
- **Configurable Database Settings**: Dynamic database connection settings UI to configure MySQL host IP, port, and credentials.

---

## 📁 Project Structure

```text
SPI_Inventry_Management/
├── FronEnd/
│   └── inventry_frontend/          # Flutter Desktop Application
│       ├── lib/
│       │   ├── database/           # MySQL client helper & queries
│       │   ├── models/             # Data models (Inventry, Event, User)
│       │   ├── providers/          # State management (Auth, Inventory, DB Settings)
│       │   ├── services/           # LCSC API & Serial port scanner services
│       │   └── views/              # UI screens (Login, Inventory, History, Settings)
│       ├── test/                   # Widget tests
│       ├── windows/                # Windows desktop runner & platform configs
│       ├── pubspec.yaml            # Flutter dependencies & metadata
│       └── analysis_options.yaml   # Dart lint rules
├── Inventry Backend/
│   ├── InventryDB_Setup.exe        # Standalone executable to initialize MySQL service
│   └── MySql_Initialize/           # Python source & configuration for DB setup
│       ├── main.py                 # MySQL automated setup script
│       ├── requirements.txt        # Python dependencies
│       └── Verification_Guide.txt  # Step-by-step verification instructions
├── .gitignore                      # Git ignore rules for build and temp files
└── README.md                       # Project documentation
```

---

## ⚙ Prerequisites

### For Frontend:
- [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (v3.9+ / Dart 3.9+)
- Visual Studio with **Desktop development with C++** (required for Flutter Windows builds)

### For Backend:
- Windows OS (Run as **Administrator**)
- Python 3.8+ (if running from source) or use the prebuilt `InventryDB_Setup.exe`
- Active internet connection (on first run to download MySQL binaries)

---

## 🚀 Getting Started

### 1. Backend & Database Setup

#### Option A: Using the Pre-built Executable (Fastest)
1. Navigate to `Inventry Backend/`.
2. Right-click `InventryDB_Setup.exe` and select **Run as Administrator**.
3. Follow the console prompt. It will download MySQL, install the `Inventry_Management` service, open port 3306 in Windows Firewall, and create all databases and default users.

#### Option B: Running from Python Source
```powershell
cd "Inventry Backend\MySql_Initialize"
pip install -r requirements.txt
python main.py
```

#### Verify MySQL Service
```powershell
sc query Inventry_Management
```
Ensure the state shows `4 RUNNING`.

---

### 2. Frontend Setup (Flutter)

1. Navigate to the frontend directory:
   ```powershell
   cd "FronEnd\inventry_frontend"
   ```

2. Fetch Flutter packages:
   ```powershell
   flutter pub get
   ```

3. Run the application on Windows:
   ```powershell
   flutter run -d windows
   ```

4. Build release executable:
   ```powershell
   flutter build windows --release
   ```

---

## 🗄 Database Schema & Roles

### Database: `CompanentsInventry`

- **`User`**: Manages application operators and administrators.
  - `ID`, `Name`, `UserName` (UNIQUE), `PassWord`
- **`Inventry`**: Stores stock items and quantities.
  - `ID`, `LCSCPart` (UNIQUE), `MPNPart`, `Description`, `CurrentQTY`, `UsedQTY`, `CreatedDate`, `LastUpdatedDateTime`
- **`Event`**: Transaction and audit log table.
  - `ID`, `StockID` (FK -> Inventry), `Action`, `QTY`, `DateTime`, `UserID` (FK -> User)

### Default Credentials

| Role | Username | Password |
|---|---|---|
| Root | `root` | `SPI12345` |
| Admin | `sde1` | `sde100` |
| Embed Users | `embed1` – `embed5` | `embed100` – `embed500` |

---

## 🔌 Hardware & Scanner Integration

The application integrates with Windows COM/Serial ports using `serial_port_win32`:
- Automatically listens for input from connected barcode/QR scanners.
- Matches scanned barcodes against `LCSCPart` or `MPNPart`.
- Automatically fetches component descriptions and updates inventory records.

---

## 📊 Reporting & Data Export

- **Excel (.xlsx)**: Export full stock ledger or filtered inventory.
- **PDF**: Generate printable transaction summaries and inventory stock reports.
- **CSV**: Raw data export for data exchange and external analysis.
