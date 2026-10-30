# Inventry Management — MySQL Auto-Initializer

Automatically installs MySQL 8.0, configures the Windows service, creates the database, users, and tables.

## Pre-requisites
- Windows (run as **Administrator**)
- Python 3.8+
- Internet connection (first run only)

## Install Python dependency
```bash
pip install -r requirements.txt
```

## Run
```bash
python main.py
```

---

## What it does
| Step | Action |
|------|--------|
| 1 | Downloads & extracts MySQL 8.0 to `C:\mysql` (if not present) |
| 2 | Writes `my.ini` with `bind-address=0.0.0.0` (LAN access) |
| 3 | Installs & starts Windows service **`Inventry_Management`** |
| 4 | Opens port 3306 in Windows Firewall |
| 5 | Creates DB & all users |
| 6 | Creates all three tables |
| 7 | Installs MySQL Workbench & Shell (optional) |

---

## Credentials

| Role        | Username | Password  |
|-------------|----------|-----------|
| Root        | root     | SPI12345  |
| Admin       | sde1     | sde100    |
| Embed User 1 | embed1  | embed100  |
| Embed User 2 | embed2  | embed200  |
| Embed User 3 | embed3  | embed300  |
| Embed User 4 | embed4  | embed400  |
| Embed User 5 | embed5  | embed500  |

All embed users have **GRANT ALL** on `CompanentsInventry` (CREATE, INSERT, UPDATE, DELETE, SELECT, …).

---

## Database: `CompanentsInventry`

### Table: `User`
| Column   | Type         | Notes          |
|----------|--------------|----------------|
| ID       | INT PK AI    |                |
| Name     | VARCHAR(255) |                |
| UserName | VARCHAR(255) | UNIQUE         |
| PassWord | VARCHAR(255) |                |

### Table: `Inventry`
| Column              | Type         | Notes                |
|---------------------|--------------|----------------------|
| ID                  | INT PK AI    |                      |
| LCSCPart            | VARCHAR(255) | UNIQUE               |
| MPNPart             | VARCHAR(255) |                      |
| Description         | VARCHAR(255) |                      |
| CurrentQTY          | INT          | Default 0            |
| UsedQTY             | INT          | Default 0            |
| CreatedDate         | DATETIME     | Default NOW          |
| LastUpdatedDateTime | DATETIME     | Auto-update on change |

### Table: `Event`
| Column   | Type         | Notes                        |
|----------|--------------|------------------------------|
| ID       | INT PK AI    |                              |
| StockID  | INT          | FK → Inventry(ID)            |
| Action   | VARCHAR(255) |                              |
| QTY      | INT          |                              |
| DateTime | DATETIME     | Default NOW                  |
| UserID   | INT          | FK → User(ID)                |
