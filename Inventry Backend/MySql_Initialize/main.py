import os
import sys
import socket
import zipfile
import urllib.request
import subprocess
import time
import mysql.connector
from mysql.connector import Error
import ctypes

# ---------------- CONFIG ----------------
MYSQL_SERVER_URL = "https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.43-winx64.zip"
MYSQL_WORKBENCH_URL = "https://cdn.mysql.com/Downloads/MySQLGUITools/mysql-workbench-community-8.0.43-winx64.msi"
MYSQL_SHELL_URL = "https://cdn.mysql.com/Downloads/MySQL-Shell/mysql-shell-9.4.0-windows-x86-64bit.msi"

MYSQL_DIR = r"C:\mysql"
DATADIR = os.path.join(MYSQL_DIR, "data")
MY_INI = os.path.join(MYSQL_DIR, "my.ini")
SERVICE_NAME = "Inventry_Management"

MYSQL_ROOT_PASSWORD = "SPI12345"
DB_NAME = "CompanentsInventry"

ADMIN_USER = "sde1"
ADMIN_PASS = "sde100"

# 5 Embed users — all get GRANT ALL on the DB
EMBED_USERS = [
    {"user": "embed1", "pass": "embed100"},
    {"user": "embed2", "pass": "embed200"},
    {"user": "embed3", "pass": "embed300"},
    {"user": "embed4", "pass": "embed400"},
    {"user": "embed5", "pass": "embed500"},
]

# LAN IP
HOST = socket.gethostbyname(socket.gethostname())
print(f"ℹ LAN IP detected: {HOST}")

# ---------------- Admin Check ----------------
def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False

if not is_admin():
    print("⚠ Please run this script as Administrator (right-click → Run as Administrator).")
    sys.exit(1)

# ---------------- Helper Functions ----------------
def download_file(url, filename):
    try:
        print(f"⬇️  Downloading {filename} …")
        urllib.request.urlretrieve(url, filename)
        print(f"✅ Downloaded {filename}")
        return True
    except Exception as e:
        print(f"❌ Failed to download {filename}: {e}")
        return False

def install_msi(filename):
    try:
        print(f"📦 Installing {filename} ...")
        subprocess.run(["msiexec", "/i", filename, "/quiet", "/norestart"], check=True)
        print(f"✅ {filename} installed.")
        os.remove(filename)
    except subprocess.CalledProcessError as e:
        print(f"❌ Error installing {filename}: {e}")

def find_mysqld(mysql_dir):
    for root, dirs, files in os.walk(mysql_dir):
        if "mysqld.exe" in files:
            return os.path.join(root, "mysqld.exe")
    return None

# ---------------- MySQL Setup ----------------
def setup_mysql_server():
    bin_path = find_mysqld(MYSQL_DIR)
    if not bin_path:
        print("⚙️  MySQL Server not found. Downloading & extracting...")
        zip_path = "mysql_server.zip"
        if not download_file(MYSQL_SERVER_URL, zip_path):
            print("❌ Failed to download MySQL server. Please download manually.")
            sys.exit(1)
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(MYSQL_DIR)
        os.remove(zip_path)
        bin_path = find_mysqld(MYSQL_DIR)

    if not bin_path:
        print("❌ mysqld.exe not found after extraction.")
        sys.exit(1)

    MYSQL_BIN = bin_path
    os.makedirs(DATADIR, exist_ok=True)

    if not os.listdir(DATADIR):
        subprocess.run([MYSQL_BIN,
                        "--initialize-insecure",
                        f"--datadir={DATADIR}"], check=True)
        print("✅ MySQL data directory initialized (no root password).")
    else:
        print("ℹ️  Data directory already initialized. Skipping.")

    return MYSQL_BIN

# ---------------- my.ini ----------------
def create_my_ini():
    datadir_fixed = DATADIR.replace("\\", "/")
    content = f"""
[mysqld]
datadir={datadir_fixed}
port=3306
bind-address=0.0.0.0
sql_mode=NO_ENGINE_SUBSTITUTION,STRICT_TRANS_TABLES
"""
    with open(MY_INI, "w") as f:
        f.write(content.strip())
    print("✅ my.ini created with bind-address = 0.0.0.0 (LAN + localhost enabled).")

# ---------------- Windows Service ----------------
def install_mysql_service(MYSQL_BIN):
    check = subprocess.run(["sc", "query", SERVICE_NAME], capture_output=True, text=True)

    # ── Already running ──────────────────────────────────────────────────────
    if "RUNNING" in check.stdout:
        print(f"ℹ️  Service '{SERVICE_NAME}' already running. Skipping reinstall.")
        return True

    # ── Exists but stopped — just start it, no reinstall needed ─────────────
    if "STOPPED" in check.stdout or "STOP_PENDING" in check.stdout:
        print(f"⚠️  Service '{SERVICE_NAME}' is stopped. Starting it...")
        result = subprocess.run(["sc", "start", SERVICE_NAME], capture_output=True, text=True)
        if result.returncode == 0:
            print(f"✅ Service '{SERVICE_NAME}' started.")
        else:
            print(f"⚠️  sc start returned: {result.stderr.strip() or result.stdout.strip()}")
        return True

    # ── Not installed at all — full fresh install ───────────────────────────
    print(f"🔧 Installing MySQL service '{SERVICE_NAME}' ...")
    subprocess.run(["sc", "stop",   SERVICE_NAME], check=False, capture_output=True)
    subprocess.run(["sc", "delete", SERVICE_NAME], check=False, capture_output=True)

    cmd_install = [
        MYSQL_BIN,
        "--install",
        SERVICE_NAME,
        f"--defaults-file={MY_INI}"
    ]
    result = subprocess.run(cmd_install, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"❌ Failed to install service:\n{result.stderr or result.stdout}")
        return False

    print(f"✅ Service '{SERVICE_NAME}' installed.")
    subprocess.run(["sc", "config", SERVICE_NAME, "start=", "auto"], capture_output=True)
    subprocess.run(["sc", "start",  SERVICE_NAME], capture_output=True)
    print(f"🚀 MySQL service '{SERVICE_NAME}' started.")
    return True

# ---------------- Firewall ----------------
def allow_mysql_port():
    print("🔥 Allowing MySQL port 3306 through Windows Firewall ...")
    subprocess.run([
        "netsh", "advfirewall", "firewall", "add", "rule",
        "name=MySQL_InventryMgmt", "dir=in", "action=allow", "protocol=TCP", "localport=3306"
    ], capture_output=True)
    print("✅ Firewall rule added.")

# ---------------- Database & Users ----------------
def setup_database_and_users():
    # Wait for MySQL to be ready
    print("⏳ Waiting for MySQL to be ready...")
    time.sleep(5)  # give mysqld a moment to initialise before polling
    for _ in range(30):  # up to 90 seconds
        try:
            conn = mysql.connector.connect(user="root", password="", host="127.0.0.1")
            conn.close()
            break
        except mysql.connector.Error as err:
            if err.errno == 1045:
                try:
                    conn = mysql.connector.connect(user="root", password=MYSQL_ROOT_PASSWORD, host="127.0.0.1")
                    conn.close()
                    break
                except:
                    pass
            time.sleep(3)
        except:
            time.sleep(3)
    else:
        print("❌ MySQL did not start in time.")
        sys.exit(1)

    # Connect as root (no password initially, or fallback to root password)
    try:
        conn = mysql.connector.connect(user="root", password="", host="127.0.0.1")
    except mysql.connector.Error as err:
        if err.errno == 1045:
            conn = mysql.connector.connect(user="root", password=MYSQL_ROOT_PASSWORD, host="127.0.0.1")
        else:
            raise err
    cursor = conn.cursor()


    # ---- Root user ----
    try:
        cursor.execute(f"ALTER USER 'root'@'localhost' IDENTIFIED BY '{MYSQL_ROOT_PASSWORD}'")
    except:
        pass
    try:
        cursor.execute(f"CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '{MYSQL_ROOT_PASSWORD}'")
    except:
        pass
    cursor.execute("GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION")

    # ---- Create database ----
    cursor.execute(f"CREATE DATABASE IF NOT EXISTS `{DB_NAME}`")
    print(f"✅ Database `{DB_NAME}` ensured.")

    # ---- Admin user (sde1) ----
    for host in ["localhost", "%"]:
        cursor.execute(
            f"CREATE USER IF NOT EXISTS '{ADMIN_USER}'@'{host}' IDENTIFIED BY '{ADMIN_PASS}'"
        )
        cursor.execute(
            f"GRANT ALL PRIVILEGES ON `{DB_NAME}`.* TO '{ADMIN_USER}'@'{host}' WITH GRANT OPTION"
        )
    print(f"✅ Admin user '{ADMIN_USER}' created with GRANT ALL.")

    # ---- Embed users — CREATE, DELETE, UPDATE, SELECT + GRANT ALL ----
    for embed in EMBED_USERS:
        u = embed["user"]
        p = embed["pass"]
        for host in ["localhost", "%"]:
            cursor.execute(
                f"CREATE USER IF NOT EXISTS '{u}'@'{host}' IDENTIFIED BY '{p}'"
            )
            cursor.execute(
                f"GRANT ALL PRIVILEGES ON `{DB_NAME}`.* TO '{u}'@'{host}' WITH GRANT OPTION"
            )
        print(f"✅ Embed user '{u}' created with GRANT ALL.")

    cursor.execute("FLUSH PRIVILEGES")
    conn.commit()
    cursor.close()
    conn.close()
    print("✅ All database users configured for localhost + remote LAN.")

# ---------------- Tables ----------------
def check_and_create_tables():
    conn = mysql.connector.connect(
        user=ADMIN_USER,
        password=ADMIN_PASS,
        host="127.0.0.1",
        database=DB_NAME
    )
    cursor = conn.cursor()

    # ---- User Table ----
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS `User` (
            ID       INT AUTO_INCREMENT PRIMARY KEY,
            Name     VARCHAR(255) NOT NULL,
            UserName VARCHAR(255) NOT NULL UNIQUE,
            PassWord VARCHAR(255) NOT NULL
        )
    """)
    print("✅ Table `User` ensured.")

    # ---- Inventry Table ----
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS `Inventry` (
            ID                  INT AUTO_INCREMENT PRIMARY KEY,
            LCSCPart            VARCHAR(255)  NOT NULL UNIQUE,
            MPNPart             VARCHAR(255),
            Description         VARCHAR(255),
            Type                VARCHAR(255)  NOT NULL DEFAULT '',
            Package             VARCHAR(100)  NOT NULL DEFAULT '',
            CurrentQTY          INT           NOT NULL DEFAULT 0,
            UsedQTY             INT           NOT NULL DEFAULT 0,
            InStock             INT           NOT NULL DEFAULT 0,
            ReferelLink         VARCHAR(1024) NOT NULL DEFAULT '',
            CurrentPrice        VARCHAR(50)   NOT NULL DEFAULT '',
            OldPrice            VARCHAR(50)   NOT NULL DEFAULT '',
            CreatedDate         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
            LastUpdatedDateTime DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                                             ON UPDATE CURRENT_TIMESTAMP
        )
    """)
    print("✅ Table `Inventry` ensured.")



    # ---- Migration: Add Package column if not exists ----
    cursor.execute("""
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = %s
          AND TABLE_NAME   = 'Inventry'
          AND COLUMN_NAME  = 'Package'
    """, (DB_NAME,))
    (col_exists,) = cursor.fetchone()
    if col_exists == 0:
        cursor.execute(
            "ALTER TABLE `Inventry` ADD COLUMN `Package` VARCHAR(100) NOT NULL DEFAULT ''"
        )
        print("✅ Column `Package` added to `Inventry`.")
    else:
        print("ℹ️  Column `Package` already exists in `Inventry`. Skipping.")

    # ---- Migration: Add Type column if not exists ----
    cursor.execute("""
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = %s
          AND TABLE_NAME   = 'Inventry'
          AND COLUMN_NAME  = 'Type'
    """, (DB_NAME,))
    (col_exists,) = cursor.fetchone()
    if col_exists == 0:
        cursor.execute(
            "ALTER TABLE `Inventry` ADD COLUMN `Type` VARCHAR(255) NOT NULL DEFAULT ''"
        )
        print("✅ Column `Type` added to `Inventry`.")
    else:
        print("\u2139\ufe0f  Column `Type` already exists in `Inventry`. Skipping.")

    # ---- Migration: Add ReferelLink column if not exists ----
    cursor.execute("""
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = %s
          AND TABLE_NAME   = 'Inventry'
          AND COLUMN_NAME  = 'ReferelLink'
    """, (DB_NAME,))
    (col_exists,) = cursor.fetchone()
    if col_exists == 0:
        cursor.execute(
            "ALTER TABLE `Inventry` ADD COLUMN `ReferelLink` VARCHAR(1024) NOT NULL DEFAULT ''"
        )
        print("\u2705 Column `ReferelLink` added to `Inventry`.")
    else:
        print("\u2139\ufe0f  Column `ReferelLink` already exists. Skipping.")

    # ---- Migration: Add CurrentPrice column if not exists ----
    cursor.execute("""
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = %s
          AND TABLE_NAME   = 'Inventry'
          AND COLUMN_NAME  = 'CurrentPrice'
    """, (DB_NAME,))
    (col_exists,) = cursor.fetchone()
    if col_exists == 0:
        cursor.execute(
            "ALTER TABLE `Inventry` ADD COLUMN `CurrentPrice` VARCHAR(50) NOT NULL DEFAULT ''"
        )
        print("\u2705 Column `CurrentPrice` added to `Inventry`.")
    else:
        print("\u2139\ufe0f  Column `CurrentPrice` already exists. Skipping.")

    # ---- Migration: Add OldPrice column if not exists ----
    cursor.execute("""
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = %s
          AND TABLE_NAME   = 'Inventry'
          AND COLUMN_NAME  = 'OldPrice'
    """, (DB_NAME,))
    (col_exists,) = cursor.fetchone()
    if col_exists == 0:
        cursor.execute(
            "ALTER TABLE `Inventry` ADD COLUMN `OldPrice` VARCHAR(50) NOT NULL DEFAULT ''"
        )
        print("\u2705 Column `OldPrice` added to `Inventry`.")
    else:
        print("\u2139\ufe0f  Column `OldPrice` already exists. Skipping.")

    # ---- Migration: Add InStock column if not exists ----
    cursor.execute("""
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = %s
          AND TABLE_NAME   = 'Inventry'
          AND COLUMN_NAME  = 'InStock'
    """, (DB_NAME,))
    (col_exists,) = cursor.fetchone()
    if col_exists == 0:
        cursor.execute(
            "ALTER TABLE `Inventry` ADD COLUMN `InStock` INT NOT NULL DEFAULT 0"
        )
        print("\u2705 Column `InStock` added to `Inventry`.")
    else:
        print("\u2139\ufe0f  Column `InStock` already exists. Skipping.")


    # ---- Event Table ----
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS `Event` (
            ID       INT AUTO_INCREMENT PRIMARY KEY,
            StockID  INT          NOT NULL,
            Action   VARCHAR(255) NOT NULL,
            QTY      INT          NOT NULL,
            DateTime DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UserID   INT          NOT NULL,
            CONSTRAINT fk_event_stock  FOREIGN KEY (StockID) REFERENCES `Inventry`(ID)
                ON DELETE CASCADE ON UPDATE CASCADE,
            CONSTRAINT fk_event_user   FOREIGN KEY (UserID)  REFERENCES `User`(ID)
                ON DELETE RESTRICT ON UPDATE CASCADE
        )
    """)
    print("✅ Table `Event` ensured.")

    conn.commit()
    cursor.close()
    conn.close()
    print("✅ All tables created / verified in DB.")

# ---------------- Optional Installs ----------------
def install_workbench():
    dest_folder = r"C:\Program Files\MySQL\MySQL Workbench 8.0 CE"
    if os.path.exists(dest_folder):
        print("ℹ️  Workbench already exists. Skipping.")
        return
    if download_file(MYSQL_WORKBENCH_URL, "mysql_workbench.msi"):
        install_msi("mysql_workbench.msi")

def install_shell():
    dest_folder = r"C:\Program Files\MySQL\MySQL Shell 8.0"
    if os.path.exists(dest_folder):
        print("ℹ️  MySQL Shell already exists. Skipping.")
        return
    if download_file(MYSQL_SHELL_URL, "mysql_shell.msi"):
        install_msi("mysql_shell.msi")

# ---------------- Main ----------------
if __name__ == "__main__":
    MYSQL_BIN = setup_mysql_server()
    create_my_ini()
    install_mysql_service(MYSQL_BIN)
    allow_mysql_port()
    setup_database_and_users()
    check_and_create_tables()
    install_workbench()
    install_shell()

    print("\n🎉 Setup finished successfully!")
    print(f"   Service   : {SERVICE_NAME}")
    print(f"   Database  : {DB_NAME}")
    print(f"   Root      : root / {MYSQL_ROOT_PASSWORD}")
    print(f"   Admin     : {ADMIN_USER} / {ADMIN_PASS}")
    for e in EMBED_USERS:
        print(f"   Embed     : {e['user']} / {e['pass']}")
    print(f"   LAN IP    : {HOST}")
    input("\nPress Enter to exit...")
