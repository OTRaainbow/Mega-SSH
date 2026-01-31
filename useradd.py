import sys
import subprocess
import logging
import os
import concurrent.futures
from collections import Counter

# --- Auto-install required packages ---
def install_package(package):
    """Installs a package using pip, handling PEP 668 on modern Ubuntu."""
    try:
        print(f"Attempting to install {package}...")
        # Ubuntu 24.04 blocks system-wide pip install by default (PEP 668)
        # We use --break-system-packages as this is a standalone tool script
        subprocess.check_call([sys.executable, "-m", "pip", "install", package, "--break-system-packages"], 
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f"{package} installed successfully.")
    except subprocess.CalledProcessError:
        # Try without the flag if on an older system
        try:
             subprocess.check_call([sys.executable, "-m", "pip", "install", package], 
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
             print(f"{package} installed successfully.")
        except subprocess.CalledProcessError:
            print(f"Failed to install {package}. Please install it manually (e.g. apt install python3-{package.lower()})")
            sys.exit(1)

try:
    from PyQt6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QPushButton, QTreeWidget, QTreeWidgetItem, QTextEdit, QMessageBox,
        QInputDialog, QLineEdit, QLabel, QSplitter, QFileDialog, QDialog, QDialogButtonBox,
        QFormLayout, QTableWidget, QTableWidgetItem, QHeaderView, QCheckBox, QGridLayout
    )
except ImportError:
    install_package("PyQt6")
    from PyQt6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QPushButton, QTreeWidget, QTreeWidgetItem, QTextEdit, QMessageBox,
        QInputDialog, QLineEdit, QLabel, QSplitter, QFileDialog, QDialog, QDialogButtonBox,
        QFormLayout, QTableWidget, QTableWidgetItem, QHeaderView, QCheckBox, QGridLayout
    )

try:
    import paramiko
except ImportError:
    install_package("paramiko")
    import paramiko

from PyQt6.QtCore import QObject, pyqtSignal, QRunnable, QThreadPool, QTimer, Qt
from PyQt6.QtGui import QFont, QColor

# ====================================================================================
#
#          FILE: 1. Script.py
#
#         USAGE: python "1. Script.py"
#
#   DESCRIPTION: A PyQt application to manage users on multiple servers.
#
#  REQUIREMENTS: paramiko, PyQt6
#
# ====================================================================================

DARK_STYLESHEET = """
QWidget {
    background-color: #2b2b2b;
    color: #ffffff;
    border: none;
}
QMainWindow {
    background-color: #2b2b2b;
}
QTreeWidget {
    background-color: #3c3f41;
    color: #dcdcdc;
    border: 1px solid #4f4f4f;
}
QTreeWidget::item {
    padding: 5px;
}
QTreeWidget::item:selected {
    background-color: #4a6984;
}
QHeaderView::section {
    background-color: #3c3f41;
    color: #dcdcdc;
    padding: 4px;
    border: 1px solid #4f4f4f;
}
QPushButton {
    background-color: #4a4d50;
    color: #dcdcdc;
    border: 1px solid #4f4f4f;
    padding: 5px 10px;
    border-radius: 4px;
}
QPushButton:hover {
    background-color: #5a5d60;
}
QPushButton:pressed {
    background-color: #3c3f41;
}
QPushButton:disabled {
    background-color: #3a3d40;
    color: #8c8c8c;
}
QTextEdit {
    background-color: #2b2b2b;
    color: #dcdcdc;
    border: 1px solid #4f4f4f;
}
QMessageBox {
    background-color: #3c3f41;
}
QInputDialog {
    background-color: #3c3f41;
    color: #dcdcdc;
}
QLineEdit {
    background-color: #3c3f41;
    color: #dcdcdc;
    border: 1px solid #4f4f4f;
    padding: 2px;
}
"""

# --- Configuration ---
# Build paths relative to the script's location
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MEGA_SSH_SCRIPT_PATH = os.path.join(SCRIPT_DIR, 'mega_ssh_v3.sh')

class Config:
    SERVERS_FILE = os.path.join(SCRIPT_DIR, 'Servers.txt')
    LOG_LEVEL = logging.INFO

    @classmethod
    def ensure_files_exist(cls):
        """Ensures that necessary files exist, creating them if needed."""
        if not os.path.exists(cls.SERVERS_FILE):
            try:
                with open(cls.SERVERS_FILE, 'w') as f:
                    f.write("# Server configuration file\n")
                    f.write("# Format: IP|PORT|USERNAME|PASSWORD\n")
                print(f"Created empty {os.path.basename(cls.SERVERS_FILE)}")
            except Exception as e:
                print(f"Error creating {cls.SERVERS_FILE}: {e}")

# --- Custom Logger for PyQt ---
class QTextEditLogHandler(logging.Handler, QObject):
    log_signal = pyqtSignal(str, QColor)

    def __init__(self, text_edit):
        super().__init__()
        QObject.__init__(self)
        self.text_edit = text_edit
        self.log_signal.connect(self.append_log)

    def emit(self, record):
        msg = self.format(record)
        level_color = self.get_level_color(record.levelno)
        self.log_signal.emit(msg, level_color)

    def append_log(self, msg, color):
        self.text_edit.setTextColor(color)
        self.text_edit.append(msg)
        self.text_edit.setTextColor(QColor("white")) # Reset to default

    def get_level_color(self, levelno):
        if levelno >= logging.CRITICAL:
            return QColor("#e74c3c") # Bright Red
        elif levelno >= logging.ERROR:
            return QColor("#e74c3c") # Bright Red
        elif levelno >= logging.WARNING:
            return QColor("#f39c12") # Bright Yellow/Orange
        elif levelno >= logging.INFO:
            return QColor("#2ecc71") # Bright Green
        else:
            return QColor("#ffffff") # White

def setup_logger(handler):
    """Sets up a logger to use the custom handler."""
    logger = logging.getLogger()
    logger.setLevel(Config.LOG_LEVEL)
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s', datefmt='%H:%M:%S')
    handler.setFormatter(formatter)
    
    # Avoid adding duplicate handlers
    if not any(isinstance(h, QTextEditLogHandler) for h in logger.handlers):
        logger.addHandler(handler)
    return logger

logger = logging.getLogger()


# --- SSH Communication Logic ---
class SshClient:
    """Handles all SSH-related operations for a single server."""
    def __init__(self, server_details):
        self.ip, self.port, self.user, self.password = server_details
        self.ssh = None

    def connect(self):
        try:
            self.ssh = paramiko.SSHClient()
            self.ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            logger.info(f"Connecting to {self.ip}:{self.port}...")
            self.ssh.connect(
                self.ip, port=int(self.port), username=self.user,
                password=self.password, timeout=10
            )
            return True
        except Exception as e:
            logger.error(f"Failed to connect to {self.ip}:{self.port}: {e}")
            return False

    def disconnect(self):
        if self.ssh:
            self.ssh.close()
            logger.info(f"Connection closed for {self.ip}:{self.port}.")

    def list_users(self):
        """Lists non-system users on the server."""
        if not self.ssh:
            return None
        try:
            # List users with UID >= 1000, which are typically normal users
            command = "awk -F: '($3 >= 1000) {print $1}' /etc/passwd"
            stdin, stdout, stderr = self.ssh.exec_command(command)
            users = stdout.read().decode().splitlines()
            logger.info(f"Found {len(users)} user(s) on {self.ip}")
            return users
        except Exception as e:
            logger.error(f"Failed to list users on {self.ip}: {e}")
            return None
    
    def get_online_users(self):
        """Gets a dictionary of online users and their session counts."""
        if not self.ssh:
            return {}  # Return empty dict, not None
        try:
            # The `w` command is better as it's designed for this.
            # -h suppresses the header.
            command = "w -h"
            stdin, stdout, stderr = self.ssh.exec_command(command)
            output = stdout.read().decode().splitlines()

            # The first column of `w` output is the username
            online_usernames = [line.split()[0] for line in output if line]
            return Counter(online_usernames)
        except Exception as e:
            logger.error(f"Failed to get online users on {self.ip}: {e}")
            return {}  # Return empty dict on error

    def add_user(self, username, password):
        """Adds a single user, returning a result dictionary."""
        logger.info(f"Attempting to add user '{username}' on {self.ip}")
        try:
            # Check if user exists
            stdin, stdout, stderr = self.ssh.exec_command(f"id {username}")
            if stdout.channel.recv_exit_status() == 0:
                 logger.warning(f"User {username} already exists on {self.ip}.")
                 return {'status': 'warning', 'message': f"User {username} already exists on {self.ip}."}
                 
            command = f"useradd -m -s /bin/bash {username}"
            stdin, stdout, stderr = self.ssh.exec_command(command)
            err = stderr.read().decode()
            if err and "already exists" not in err:
                logger.error(f"Error creating user {username} on {self.ip}: {err.strip()}")
                return {'status': 'error', 'message': err.strip()}

            # Set password using chpasswd
            command = f"echo '{username}:{password}' | chpasswd"
            stdin, stdout, stderr = self.ssh.exec_command(command)
            err = stderr.read().decode()
            if err:
                 logger.error(f"Error setting password for {username} on {self.ip}: {err.strip()}")
                 return {'status': 'error', 'message': err.strip()}

            logger.info(f"Successfully added user {username} on {self.ip}.")
            return {'status': 'success', 'message': 'OK'}
        except Exception as e:
            logger.error(f"Exception adding user {username} on {self.ip}: {e}")
            return {'status': 'error', 'message': str(e)}

    def delete_user(self, username):
        """Deletes a single user, returning a result dictionary."""
        logger.info(f"Attempting to delete user '{username}' on {self.ip}")
        try:
            # Terminate processes first
            self.ssh.exec_command(f"pkill -u {username}")

            command = f"userdel -rf {username}"
            stdin, stdout, stderr = self.ssh.exec_command(command)
            
            exit_status = stdout.channel.recv_exit_status()
            err_output = stderr.read().decode().strip()

            if exit_status == 0:
                msg = f"Successfully deleted user {username}."
                logger.info(f"{msg} on {self.ip}.")
                return {'status': 'success', 'message': 'OK'}
            elif exit_status == 6: # userdel exit code for non-existent user
                msg = f"User {username} does not exist."
                logger.warning(f"{msg} on {self.ip}.")
                return {'status': 'warning', 'message': msg}
            else:
                msg = f"Error deleting user {username} (exit code {exit_status}): {err_output}"
                logger.error(f"{msg} on {self.ip}")
                return {'status': 'error', 'message': err_output or f"Exit code {exit_status}"}
                
        except Exception as e:
            logger.error(f"Exception deleting user {username} on {self.ip}: {e}")
            return {'status': 'error', 'message': str(e)}


# --- Threading and Worker System ---

class WorkerSignals(QObject):
    """
    Defines the signals available from a running worker thread.
    Supported signals are:
    finished: No data
    error:    tuple (exctype, value, traceback.format_exc())
    result:   object data returned from processing
    progress: int indicating % progress
    """
    finished = pyqtSignal()
    error = pyqtSignal(tuple)
    result = pyqtSignal(object)
    progress = pyqtSignal(object)


class Worker(QRunnable):
    """
    Worker thread
    Inherits from QRunnable to handle worker thread setup, signals and wrap-up.
    :param callback: The function callback to run on this worker thread. Supplied args and
                     kwargs will be passed through to the runner.
    :type callback: function
    :param args: Arguments to pass to the callback function
    :param kwargs: Keywords to pass to the callback function
    """

    def __init__(self, fn, *args, **kwargs):
        super().__init__()
        self.fn = fn
        self.args = args
        self.kwargs = kwargs
        self.signals = WorkerSignals()

        # Add the progress callback to our kwargs
        self.kwargs['progress_callback'] = self.signals.progress

    def run(self):
        """
        Initialise the runner function with passed args, kwargs.
        """
        try:
            result = self.fn(*self.args, **self.kwargs)
        except:
            import traceback
            traceback.print_exc()
            exctype, value = sys.exc_info()[:2]
            self.signals.error.emit((exctype, value, traceback.format_exc()))
        else:
            self.signals.result.emit(result)  # Return the result of the processing
        finally:
            self.signals.finished.emit()  # Done


# --- Main Application Window ---
class UserManagerApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Mega SSH User Manager")
        self.setGeometry(100, 100, 1200, 800)
        
        self.threadpool = QThreadPool()
        logger.info(f"Multithreading with maximum {self.threadpool.maxThreadCount()} threads.")

        # Load server details
        self.server_details = self.get_server_details()
        self.active_threads = 0
        self.bulk_operation_results = {}
        self.current_task = None
        
        self.online_status_timer = QTimer(self)
        self.online_status_timer.setInterval(30000)  # 30 seconds
        self.online_status_timer.timeout.connect(self.refresh_all_online_statuses)

        self.init_ui()

    def init_ui(self):
        # --- Main Layout ---
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        main_layout = QHBoxLayout(main_widget)

        splitter = QSplitter()
        main_layout.addWidget(splitter)
        
        # --- Left Panel (User Tree) ---
        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)
        
        self.user_tree = QTreeWidget()
        self.user_tree.setSelectionMode(QTreeWidget.SelectionMode.ExtendedSelection)
        self.user_tree.setHeaderLabels(["Servers & Users"])
        self.user_tree.setFont(QFont("Consolas", 10))
        left_layout.addWidget(self.user_tree)

        # --- Right Panel (Controls & Logs) ---
        right_panel = QWidget()
        right_layout = QVBoxLayout(right_panel)
        
        # --- Buttons in Grid Layout ---
        controls_widget = QWidget()
        controls_layout = QGridLayout(controls_widget)
        controls_layout.setSpacing(6)  # Adjust spacing between buttons
        
        # Row 0: Refresh and User Management
        self.refresh_button = QPushButton("🔄 Refresh")
        self.refresh_button.setToolTip("Refresh All Users")
        self.add_button = QPushButton("➕ Add User")
        self.add_button.setToolTip("Add a single user to selected servers")
        self.delete_button = QPushButton("❌ Delete User")
        self.delete_button.setToolTip("Delete selected user from servers")
        
        controls_layout.addWidget(self.refresh_button, 0, 0)
        controls_layout.addWidget(self.add_button, 0, 1)
        controls_layout.addWidget(self.delete_button, 0, 2)
        
        # Row 1: Bulk User Operations
        self.add_from_file_button = QPushButton("📄 Bulk Add")
        self.add_from_file_button.setToolTip("Add users from file")
        self.delete_from_file_button = QPushButton("📄 Bulk Delete")
        self.delete_from_file_button.setToolTip("Delete users from file")
        self.sync_check_button = QPushButton("🔄 Sync Users")
        self.sync_check_button.setToolTip("Run User Sync Check")
        
        controls_layout.addWidget(self.add_from_file_button, 1, 0)
        controls_layout.addWidget(self.delete_from_file_button, 1, 1)
        controls_layout.addWidget(self.sync_check_button, 1, 2)
        
        # Row 2: Server Management
        self.setup_server_button = QPushButton("🖥️ Setup Server")
        self.setup_server_button.setToolTip("Setup a new server")
        self.manage_servers_button = QPushButton("⚙️ Manage Servers")
        self.manage_servers_button.setToolTip("Manage server credentials")
        
        controls_layout.addWidget(self.setup_server_button, 2, 0)
        controls_layout.addWidget(self.manage_servers_button, 2, 1)
        
        # Make columns stretch equally
        for col in range(3):
            controls_layout.setColumnStretch(col, 1)
        
        # Add the controls widget to the right panel
        right_layout.addWidget(controls_widget)
        
        # Log Area
        self.log_output = QTextEdit()
        self.log_output.setReadOnly(True)
        self.log_output.setFont(QFont("Consolas", 9))
        right_layout.addWidget(self.log_output)

        splitter.addWidget(left_panel)
        splitter.addWidget(right_panel)
        splitter.setSizes([400, 800])

        # --- Setup Logging ---
        log_handler = QTextEditLogHandler(self.log_output)
        setup_logger(log_handler)
        
        # --- Connect Signals ---
        self.refresh_button.clicked.connect(self.refresh_all_users)
        self.add_button.clicked.connect(self.add_user_dialog)
        self.delete_button.clicked.connect(self.delete_selected_user)
        self.add_from_file_button.clicked.connect(self.add_users_from_file_dialog)
        self.delete_from_file_button.clicked.connect(self.delete_users_from_file_dialog)
        self.setup_server_button.clicked.connect(self.setup_server_dialog)
        self.sync_check_button.clicked.connect(self.run_sync_check)
        self.manage_servers_button.clicked.connect(self.manage_servers_dialog)

        if not self.server_details:
            logger.critical("Servers.txt not found or is empty. Please add server via 'Manage Servers'.")
            self.refresh_button.setEnabled(False)
            self.add_button.setEnabled(False)
            self.delete_button.setEnabled(False)
            self.add_from_file_button.setEnabled(False)
            self.delete_from_file_button.setEnabled(False)
            self.setup_server_button.setEnabled(True)
            self.manage_servers_button.setEnabled(True)
            self.sync_check_button.setEnabled(False)
        else:
            logger.info(f"Loaded {len(self.server_details)} servers. Click 'Refresh All Users' to begin.")
            # Auto-refresh on startup
            QTimer.singleShot(500, self.refresh_all_users)

    def get_server_details(self):
        """Reads server details from file."""
        try:
            with open(Config.SERVERS_FILE, 'r') as f:
                # Filter out empty or whitespace-only lines
                return [line.strip().split('|') for line in f if line.strip()]
        except FileNotFoundError:
            return []
            
    def start_task(self, task, **kwargs):
        # This method is now a placeholder/legacy.
        # All logic is moved to direct execute_* calls.
        pass
    
    def execute_bulk_task(self, action, user_data, servers=None):
        if servers is None:
            servers = self.server_details
        
        if not servers:
            logger.warning("No servers selected for the operation.")
            QMessageBox.warning(self, "No Servers", "No servers were selected for this operation.")
            return

        self.toggle_buttons(False)
        self.bulk_operation_results = {}
        self.active_threads = len(servers)

        for details in servers:
            # The worker needs server details as a list/tuple
            details_list = details if isinstance(details, list) else list(details.values())
            worker = Worker(self.process_bulk_for_server, details_list, action, user_data)
            worker.signals.result.connect(self.collect_bulk_results)
            worker.signals.finished.connect(self.on_task_complete)
            self.threadpool.start(worker)
            
    def process_bulk_for_server(self, server_details, action, user_data, progress_callback):
        """A single-server job for a bulk task, to be run in a worker."""
        client = SshClient(server_details)
        results = []
        if client.connect():
            if action == 'add':
                for user in user_data:
                    result = client.add_user(user['name'], user['password'])
                    results.append({'user': user['name'], **result})
            elif action == 'delete':
                for username in user_data:
                    result = client.delete_user(username)
                    results.append({'user': username, **result})
            client.disconnect()
        return server_details[0], results # Return (ip, results_list)

    def collect_bulk_results(self, result_tuple):
        server_ip, results = result_tuple
        self.bulk_operation_results[server_ip] = results

    def on_task_complete(self):
        self.active_threads -= 1
        if self.active_threads == 0:
            logger.info("All server operations complete.")
            self.toggle_buttons(True)

            if self.bulk_operation_results:
                self.show_results_dialog()
            
            logger.info("Automatically refreshing user list after changes...")
            self.refresh_all_users()

    def show_results_dialog(self):
        dialog = ResultsDialog(self.bulk_operation_results, self)
        dialog.exec()

    def refresh_all_users(self):
        """Fetches users from all servers and populates the tree."""
        self.online_status_timer.stop()
        self.user_tree.clear()
        self.toggle_buttons(False)
        self.active_threads = len(self.server_details)

        # Then start fetching users for each server
        for details in self.server_details:
            worker = Worker(self.fetch_users_for_server, details)
            worker.signals.result.connect(self.update_user_tree)
            worker.signals.finished.connect(self.on_refresh_task_complete)
            self.threadpool.start(worker)

    def on_refresh_task_complete(self):
        self.active_threads -= 1
        if self.active_threads == 0:
            logger.info("User list refresh complete.")
            self.toggle_buttons(True)
            if self.server_details:  # Only start if there are servers
                self.online_status_timer.start()
    
    def fetch_users_for_server(self, server_details, progress_callback):
        """A single-server job for fetching users and online status."""
        client = SshClient(server_details)
        if client.connect():
            users = client.list_users()
            online = client.get_online_users()
            client.disconnect()
            return server_details[0], users, online, True
        return server_details[0], [], {}, False

    def update_user_tree(self, result_tuple):
        server_ip, users, online_users, connected = result_tuple

        # Create the server node
        server_node = QTreeWidgetItem(self.user_tree)
        
        # Use symbols for connection status
        status_icon = "🟢" if connected else "🔴"
        status_text = f"{status_icon} {server_ip}"
        
        server_node.setText(0, status_text)
        font = QFont("Segoe UI", 10, QFont.Weight.Bold)
        server_node.setFont(0, font)

        if connected:
            server_node.setForeground(0, QColor("#2ecc71"))  # Greenish
            self._update_user_nodes(server_node, users, online_users)
        else:
            server_node.setForeground(0, QColor("#e74c3c"))  # Reddish
            error_node = QTreeWidgetItem(server_node, ["Connection failed"])
            error_node.setForeground(0, QColor("#e74c3c"))  # Reddish
        
        self.user_tree.expandAll()
        self.user_tree.resizeColumnToContents(0)
        
    def _format_user_text(self, user, session_count):
        if session_count > 0:
            text = f"🟢 {user} ({session_count} session" + ("s" if session_count > 1 else "") + ")"
            color = QColor("#98fb98") # Light Green for visibility
        else:
            text = f"⚪ {user}"
            color = QColor("#dcdcdc")
        return text, color

    def _update_user_nodes(self, server_item, users_list, online_users_dict):
        """Helper to create or update user nodes under a server item."""
        server_item.takeChildren()  # Clear old user nodes
        if not users_list:
            no_users_node = QTreeWidgetItem(server_item, ["No users found"])
            no_users_node.setForeground(0, QColor("#f39c12"))
            return

        for user in sorted(users_list):
            user_node = QTreeWidgetItem(server_item)
            user_node.setData(0, Qt.ItemDataRole.UserRole, user)
            
            session_count = online_users_dict.get(user, 0)
            text, color = self._format_user_text(user, session_count)
            
            user_node.setText(0, text)
            user_node.setForeground(0, color)
            user_node.setFont(0, QFont("Consolas", 10))

    def add_user_dialog(self):
        """Shows a dialog to get new user credentials and select servers."""
        username, ok1 = QInputDialog.getText(self, 'Add User', 'Enter username:')
        if ok1 and username:
            password, ok2 = QInputDialog.getText(self, 'Add User', f"Enter password for {username}:", QLineEdit.EchoMode.Password)
            if ok2 and password:
                # Dialog to select servers
                server_dialog = SelectServersDialog(self.server_details, self)
                if server_dialog.exec():
                    selected_servers = server_dialog.get_selected_servers()
                    if not selected_servers:
                        QMessageBox.warning(self, "Selection Error", "No servers were selected.")
                        return

                    server_count = len(selected_servers)
                    server_list_str = "\n".join([s[0] for s in selected_servers])
                    reply = QMessageBox.question(
                        self, 'Confirm Addition',
                        f"Add user '{username}' to the following {server_count} server(s)?\n\n{server_list_str}",
                        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                        QMessageBox.StandardButton.Yes
                    )
                    if reply == QMessageBox.StandardButton.Yes:
                        logger.info(f"Starting to add user '{username}' to {server_count} server(s).")
                        self.execute_bulk_task('add', [{'name': username, 'password': password}], servers=selected_servers)


    def delete_selected_user(self):
        """Deletes all users selected in the tree."""
        selected_items = self.user_tree.selectedItems()
        if not selected_items:
            QMessageBox.warning(self, "Selection Error", "Please select at least one user to delete.")
            return

        users_to_delete = []
        for item in selected_items:
            # Ensure we only add user items, not server parent items
            if item.parent():
                user_data = item.data(0, Qt.ItemDataRole.UserRole)
                if user_data:
                    users_to_delete.append(user_data)

        if not users_to_delete:
            QMessageBox.warning(self, "Selection Error", "The current selection contains no users.")
            return
            
        # Dialog to select servers
        server_dialog = SelectServersDialog(self.server_details, self)
        if server_dialog.exec():
            selected_servers = server_dialog.get_selected_servers()
            if not selected_servers:
                QMessageBox.warning(self, "Selection Error", "No servers were selected.")
                return

            user_count = len(users_to_delete)
            server_count = len(selected_servers)
            user_list_str = "\n".join(users_to_delete)
            
            reply = QMessageBox.question(
                self, 'Confirm Deletion',
                f"Are you sure you want to delete these {user_count} user(s) from {server_count} selected server(s)?\n\nUsers:\n{user_list_str}",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.Yes
            )
            if reply == QMessageBox.StandardButton.Yes:
                logger.info(f"Starting to delete {user_count} selected user(s) from {server_count} server(s).")
                self.execute_bulk_task('delete', users_to_delete, servers=selected_servers)

    def toggle_buttons(self, enabled):
        """Disables or enables buttons during long operations."""
        self.refresh_button.setEnabled(enabled)
        self.add_button.setEnabled(enabled)
        self.delete_button.setEnabled(enabled)
        self.add_from_file_button.setEnabled(enabled)
        self.delete_from_file_button.setEnabled(enabled)
        self.setup_server_button.setEnabled(enabled)
        self.manage_servers_button.setEnabled(enabled)
        self.sync_check_button.setEnabled(enabled)
        
    def closeEvent(self, event):
        # Cleanly exit threads if the window is closed.
        if self.active_threads > 0:
            reply = QMessageBox.question(
                self, 'Confirm Exit',
                "Tasks are still running. Are you sure you want to exit?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No
            )
            if reply == QMessageBox.StandardButton.Yes:
                # This is a bit abrupt, might need more graceful thread termination
                event.accept()
            else:
                event.ignore()
        else:
            event.accept()

    def setup_server_dialog(self):
        """Launches the server setup process for multiple servers."""
        if not os.path.exists(MEGA_SSH_SCRIPT_PATH):
            QMessageBox.critical(self, "Error", f"Setup script not found!\nExpected at: {MEGA_SSH_SCRIPT_PATH}")
            return
            
        setup_dialog = MultiServerSetupDialog(self)
        if setup_dialog.exec():
            credentials_list = setup_dialog.get_credentials_list()
            if not credentials_list:
                QMessageBox.warning(self, "Input Error", "No valid server credentials were provided.")
                return
            
            self.run_server_setup(credentials_list)

    def run_server_setup(self, credentials_list):
        self.progress_dialog = ProgressViewDialog(self)
        self.progress_dialog.setWindowTitle(f"Setting up {len(credentials_list)} Server(s)...")
        self.progress_dialog.show()

        for credentials in credentials_list:
            worker = Worker(self.execute_setup_script, credentials)
            worker.signals.progress.connect(self.progress_dialog.append_output)
            worker.signals.result.connect(self.on_setup_finished)
            worker.signals.error.connect(lambda err, creds=credentials: self.progress_dialog.append_output(f"<font color='#e74c3c'>--> FATAL ERROR for {creds['ip']}: {err[1]}</font>"))
            
            self.threadpool.start(worker)


    def on_setup_finished(self, result):
        success = result.get('success', False)
        message = result.get('message', 'No message.')
        new_server_details = result.get('details')

        self.progress_dialog.on_finished(success, message)
        if success and new_server_details:
            try:
                # To avoid duplicates, we'll read, check, and then write
                existing_ips = {s[0] for s in self.server_details}
                if new_server_details['ip'] not in existing_ips:
                    with open(Config.SERVERS_FILE, 'a') as f:
                        f.write(f"\n{new_server_details['ip']}|{new_server_details['port']}|{new_server_details['user']}|{new_server_details['password']}")
                    logger.info(f"Successfully added new server {new_server_details['ip']} to {os.path.basename(Config.SERVERS_FILE)}")
                    self.server_details.append(list(new_server_details.values()))
                    self.refresh_all_users()
                else:
                    logger.warning(f"Server {new_server_details['ip']} already exists in Servers.txt. Not adding again.")
                
                # Enable buttons if they were disabled and now we have servers
                if not self.refresh_button.isEnabled() and self.server_details:
                    self.toggle_buttons(True)

            except Exception as e:
                logger.error(f"Failed to write new server details to file: {e}")
                QMessageBox.critical(self, "File Error", f"Failed to update {Config.SERVERS_FILE}:\n{e}")
        
    def _run_command(self, ssh, command, progress_callback):
        """Executes a command on the remote server and streams output."""
        try:
            stdin, stdout, stderr = ssh.exec_command(command, get_pty=True)
            
            # Combine stdout and stderr streams
            for line in iter(stdout.readline, ""):
                progress_callback.emit(line.strip())
                
            exit_status = stdout.channel.recv_exit_status()
            
            # Check for errors after command finishes
            error_output = stderr.read().decode().strip()
            if error_output:
                progress_callback.emit(f"<font color='#f39c12'>{error_output}</font>")

            return exit_status
        except Exception as e:
            progress_callback.emit(f"<font color='#e74c3c'>Error running command '{command}': {e}</font>")
            return -1

    def execute_setup_script(self, credentials, progress_callback):
        """This function is run by a generic Worker to set up a new server."""
        ip = credentials['ip']
        ssh = None
        try:
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            progress_callback.emit(f"<b><font color='#87ceeb'>--- Starting setup for {ip} ---</font></b>")
            progress_callback.emit(f"--> Connecting to {ip}:{credentials['port']}...")
            ssh.connect(
                hostname=ip,
                port=int(credentials['port']),
                username=credentials['user'],
                password=credentials['password'],
                timeout=15
            )
            progress_callback.emit(f"<font color='#2ecc71'>--> Connection to {ip} successful!</font>")

            # Upload script
            sftp = ssh.open_sftp()
            remote_path = "/tmp/mega_ssh_v3.sh"
            progress_callback.emit(f"--> Uploading setup script to {ip}...")
            sftp.put(MEGA_SSH_SCRIPT_PATH, remote_path)
            sftp.close()
            progress_callback.emit("--> Upload complete.")

            # Execute script
            progress_callback.emit("--> Making script executable...")
            self._run_command(ssh, f"chmod +x {remote_path}", progress_callback)
            
            progress_callback.emit(f"<font color='#f39c12'>--> Executing setup script on {ip}... this may take a while.</font>")
            progress_callback.emit("="*80)
            
            # Use sudo if user is not root, otherwise direct execution
            exec_command = f"sudo {remote_path} install" if credentials['user'] != 'root' else f"{remote_path} install"
            exit_status = self._run_command(ssh, exec_command, progress_callback)

            progress_callback.emit("="*80)

            # Clean up the script
            progress_callback.emit(f"--> Removing temporary script from {ip}...")
            self._run_command(ssh, f"rm {remote_path}", progress_callback)
            
            if exit_status == 0:
                progress_callback.emit(f"<font color='#2ecc71'>--> Script executed successfully on {ip}!</font>")
                # Return the details of the newly configured server
                new_server_details = {
                    'ip': ip,
                    'port': '22', # The script likely changes the port to 22
                    'user': 'root', # And sets up root login
                    'password': credentials['password'], # Password should remain the same
                }
                return {'success': True, 'message': f"Server setup completed successfully for {ip}!", 'details': new_server_details}
            else:
                return {'success': False, 'message': f"Script execution failed on {ip} with exit code {exit_status}.", 'details': None}

        except Exception as e:
            logger.error(f"Setup failed for {ip}: {e}")
            progress_callback.emit(f"<font color='#e74c3c'>--> FATAL ERROR for {ip}: {e}</font>")
            return {'success': False, 'message': f"An error occurred during setup for {ip}: {e}", 'details': None}
        finally:
            if ssh and ssh.get_transport() is not None and ssh.get_transport().is_active():
                ssh.close()
                
    def add_users_from_file_dialog(self):
        """Handles the 'add from file' logic."""
        try:
            filepath, _ = QFileDialog.getOpenFileName(self, "Select Add Users File", "", "Text Files (*.txt);;All Files (*)")
            if not filepath:
                return

            users_to_add = self.parse_add_users_file(filepath)
            if not users_to_add:
                logger.warning(f"No valid users found in {filepath}.")
                return

            user_list_str = "\n".join([u['name'] for u in users_to_add])
            reply = QMessageBox.question(
                self, 'Confirm Bulk Addition',
                f"Add the following {len(users_to_add)} users to ALL servers?\n\n{user_list_str}",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.Yes
            )
            if reply == QMessageBox.StandardButton.Yes:
                logger.info(f"Starting bulk add of {len(users_to_add)} users from {os.path.basename(filepath)}.")
                self.execute_bulk_task('add', users_to_add)
        except Exception as e:
            logger.error(f"Error in add_users_from_file_dialog: {e}")
            QMessageBox.critical(self, "Error", f"An error occurred while processing the file: {e}")

    def delete_users_from_file_dialog(self):
        """Handles the 'delete from file' logic."""
        try:
            filepath, _ = QFileDialog.getOpenFileName(self, "Select Delete Users File", "", "Text Files (*.txt);;All Files (*)")
            if not filepath:
                return

            users_to_delete = self.parse_delete_users_file(filepath)
            if not users_to_delete:
                logger.warning(f"No valid users found in {filepath}.")
                return
            
            user_list_str = "\n".join(users_to_delete)
            reply = QMessageBox.question(
                self, 'Confirm Bulk Deletion',
                f"Delete the following {len(users_to_delete)} users from ALL servers?\n\n{user_list_str}",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.Yes
            )
            if reply == QMessageBox.StandardButton.Yes:
                logger.info(f"Starting bulk deletion of {len(users_to_delete)} users from {os.path.basename(filepath)}.")
                self.execute_bulk_task('delete', users_to_delete)
        except Exception as e:
            logger.error(f"Error in delete_users_from_file_dialog: {e}")
            QMessageBox.critical(self, "Error", f"An error occurred while processing the file: {e}")

    def parse_add_users_file(self, filepath):
        """Parses a file with 'username|password' per line."""
        users = []
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f, 1):
                    line = line.strip()
                    if not line or line.startswith('#'):  # Skip empty lines and comments
                        continue
                        
                    try:
                        if '|' in line:
                            parts = line.split('|', 1)
                            if len(parts) == 2:
                                username, password = parts
                                username = username.strip()
                                password = password.strip()
                                if username and password:  # Ensure both fields are non-empty
                                    users.append({'name': username, 'password': password})
                                else:
                                    logger.warning(f"Line {line_num}: Empty username or password - '{line}'")
                            else:
                                logger.warning(f"Line {line_num}: Invalid format - '{line}'")
                        else:
                            logger.warning(f"Line {line_num}: Missing separator '|' - '{line}'")
                    except Exception as e:
                        logger.warning(f"Line {line_num}: Error parsing line - '{line}': {e}")
        except Exception as e:
            logger.error(f"Error reading add users file {filepath}: {e}")
            QMessageBox.warning(self, "File Error", f"Could not read file {filepath}: {e}")
        
        if not users:
            logger.warning(f"No valid user entries found in {filepath}")
            
        return users

    def parse_delete_users_file(self, filepath):
        """Parses a file with one username per line, ignoring other data."""
        users = []
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f, 1):
                    line = line.strip()
                    if not line or line.startswith('#'):  # Skip empty lines and comments
                        continue
                    
                    # Take only the part before a potential '|'
                    username = line.split('|', 1)[0].strip()
                    if username:
                        users.append(username)
        except Exception as e:
            logger.error(f"Error reading delete users file {filepath}: {e}")
            QMessageBox.warning(self, "File Error", f"Could not read file {filepath}: {e}")
        return users

    def manage_servers_dialog(self):
        """Opens a dialog to manage the list of servers."""
        dialog = ServerManagementDialog(self.server_details, self)
        if dialog.exec():
            new_server_list = dialog.get_credentials_list()
            try:
                with open(Config.SERVERS_FILE, 'w', encoding='utf-8') as f:
                    for server in new_server_list:
                        line = "|".join([server['ip'], server['port'], server['user'], server['password']])
                        f.write(line + '\n')
                
                logger.info(f"Server list updated and saved to {os.path.basename(Config.SERVERS_FILE)}.")
                QMessageBox.information(self, "Success", "Server list has been updated.")
                
                # Reload servers and refresh UI
                self.server_details = self.get_server_details()
                if not self.server_details:
                    self.toggle_buttons(False) # Disable most buttons
                    self.setup_server_button.setEnabled(True)
                    self.manage_servers_button.setEnabled(True)
                    self.user_tree.clear()
                else:
                    self.toggle_buttons(True)
                    self.refresh_all_users()

            except Exception as e:
                logger.error(f"Failed to save server file: {e}")
                QMessageBox.critical(self, "Error", f"Failed to save server list: {e}")

    def run_sync_check(self):
        """Fetches all users and opens the sync dialog to show discrepancies."""
        logger.info("Starting user sync check...")
        self.toggle_buttons(False)
        
        self.all_server_users = {}
        self.active_threads = len(self.server_details)

        for details in self.server_details:
            worker = Worker(self.fetch_users_for_server, details)
            worker.signals.result.connect(self.collect_users_for_sync)
            worker.signals.finished.connect(self.on_sync_check_task_complete)
            self.threadpool.start(worker)

    def collect_users_for_sync(self, result_tuple):
        server_ip, users = result_tuple
        if users is not None:
            self.all_server_users[server_ip] = users

    def on_sync_check_task_complete(self):
        self.active_threads -= 1
        if self.active_threads == 0:
            self.toggle_buttons(True)
            logger.info("Sync check data collection complete.")
            
            if not self.all_server_users:
                QMessageBox.warning(self, "Sync Check", "Could not retrieve user data from any server.")
                return

            sync_dialog = SyncDialog(self.all_server_users, self)
            sync_dialog.sync_requested.connect(self.execute_sync_task)
            sync_dialog.exec()

    def execute_sync_task(self, users_to_sync):
        logger.info(f"Executing sync task for {len(users_to_sync)} user(s)...")
        # users_to_sync is a dict of: {'username': {'password': '...', 'missing_on': ['ip1', 'ip2']}}
        
        users_to_add_by_server = {}

        for user, data in users_to_sync.items():
            password = data.get('password')
            if not password:
                logger.warning(f"No password provided for user '{user}' during sync. Skipping.")
                continue

            for ip in data['missing_on']:
                if ip not in users_to_add_by_server:
                    users_to_add_by_server[ip] = []
                users_to_add_by_server[ip].append({'name': user, 'password': password})

        if not users_to_add_by_server:
            logger.info("Sync task complete. No actions were needed.")
            return

        self.bulk_operation_results = {}
        self.active_threads = len(users_to_add_by_server)
        self.toggle_buttons(False)

        for ip, user_list in users_to_add_by_server.items():
            server_details = next((s for s in self.server_details if s[0] == ip), None)
            if server_details:
                worker = Worker(self.process_bulk_for_server, server_details, 'add', user_list)
                worker.signals.result.connect(self.collect_bulk_results)
                worker.signals.finished.connect(self.on_task_complete)
                self.threadpool.start(worker)

    def refresh_all_online_statuses(self):
        logger.info("Refreshing online user statuses...")
        # Don't disable buttons for this background task
        for details in self.server_details:
            worker = Worker(self.fetch_online_status_worker, details)
            worker.signals.result.connect(self.update_online_status_in_tree)
            worker.signals.error.connect(lambda err, ip=details[0]: self.handle_online_status_error(ip, err))
            self.threadpool.start(worker)

    def fetch_online_status_worker(self, server_details, progress_callback):
        """Worker that ONLY fetches online status."""
        client = SshClient(server_details)
        if client.connect():
            online = client.get_online_users()
            client.disconnect()
            return server_details[0], online, True
        return server_details[0], {}, False
        
    def find_server_item(self, server_ip):
        """Finds a top-level item by server IP."""
        for i in range(self.user_tree.topLevelItemCount()):
            item = self.user_tree.topLevelItem(i)
            item_text = item.text(0)
            if server_ip in item_text:
                return item
        return None

    def handle_online_status_error(self, server_ip, error):
        logger.error(f"Failed to get online status for {server_ip}: {error[1]}")
        item = self.find_server_item(server_ip)
        if not item:
            return
        item.setText(0, f"🔴 {server_ip}")
        item.setForeground(0, QColor("#e74c3c"))

    def update_online_status_in_tree(self, result_tuple):
        server_ip, online_users, connected = result_tuple
        
        item = self.find_server_item(server_ip)
        if not item:
            return

        # Update server node status
        if connected:
            item.setText(0, f"🟢 {server_ip}")
            item.setForeground(0, QColor("#2ecc71"))
        else:
            item.setText(0, f"🔴 {server_ip}")
            item.setForeground(0, QColor("#e74c3c"))
            
        # Update children
        user_items = [item.child(i) for i in range(item.childCount())]
        for user_item in user_items:
            user = user_item.data(0, Qt.ItemDataRole.UserRole)
            if not user: # Skip "no users" or "connection failed" nodes
                continue
                
            session_count = online_users.get(user, 0)
            text, color = self._format_user_text(user, session_count)
                
            user_item.setText(0, text)
            user_item.setForeground(0, color)


class ResultsDialog(QDialog):
    def __init__(self, results, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Bulk Operation Results")
        self.results = results
        self.init_ui()

    def init_ui(self):
        self.layout = QVBoxLayout(self)
        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["Server / User", "Status", "Details"])
        self.layout.addWidget(self.tree)

        status_colors = {
            'success': QColor("#2ecc71"),
            'warning': QColor("#f39c12"),
            'error': QColor("#e74c3c")
        }

        for server_ip, user_results in sorted(self.results.items()):
            server_node = QTreeWidgetItem(self.tree, [server_ip])
            server_node.setFont(0, QFont("Segoe UI", 10, QFont.Weight.Bold))
            
            for result in user_results:
                status = result.get('status', 'error')
                user_node = QTreeWidgetItem(server_node, [
                    result.get('user', 'N/A'),
                    status.upper(),
                    result.get('message', 'No details.')
                ])
                color = status_colors.get(status, QColor("white"))
                for i in range(user_node.columnCount()):
                    user_node.setForeground(i, color)

        self.tree.expandAll()
        for i in range(self.tree.columnCount()):
            self.tree.resizeColumnToContents(i)

        # OK Button
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok)
        buttons.accepted.connect(self.accept)
        self.layout.addWidget(buttons)

        self.setMinimumSize(800, 500)


# --- Dialogs and Workers for Setup ---

class SetupDialog(QDialog):
    """Dialog to get initial server credentials."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("New Server Credentials")
        
        self.layout = QFormLayout(self)
        self.ip_input = QLineEdit()
        self.port_input = QLineEdit("22")
        self.user_input = QLineEdit("root")
        self.pass_input = QLineEdit()
        self.pass_input.setEchoMode(QLineEdit.EchoMode.Password)
        
        self.layout.addRow("Server IP:", self.ip_input)
        self.layout.addRow("SSH Port:", self.port_input)
        self.layout.addRow("Username:", self.user_input)
        self.layout.addRow("Password:", self.pass_input)
        
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        self.layout.addWidget(buttons)

    def get_credentials(self):
        return {
            "ip": self.ip_input.text(),
            "port": self.port_input.text(),
            "user": self.user_input.text(),
            "password": self.pass_input.text(),
        }

class MultiServerSetupDialog(QDialog):
    """Dialog to get credentials for multiple servers using a table."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Setup Multiple Servers")
        self.setMinimumSize(600, 400)
        
        self.layout = QVBoxLayout(self)
        
        # Table Widget
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(["IP Address", "Port", "Username", "Password"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        self.layout.addWidget(self.table)

        # Buttons for table manipulation
        button_layout = QHBoxLayout()
        add_row_button = QPushButton("Add Server")
        add_row_button.clicked.connect(self.add_row)
        remove_row_button = QPushButton("Remove Selected Server(s)")
        remove_row_button.clicked.connect(self.remove_selected_rows)
        button_layout.addStretch()
        button_layout.addWidget(add_row_button)
        button_layout.addWidget(remove_row_button)
        self.layout.addLayout(button_layout)
        
        # OK/Cancel buttons
        dialog_buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        dialog_buttons.accepted.connect(self.accept)
        dialog_buttons.rejected.connect(self.reject)
        self.layout.addWidget(dialog_buttons)

        # Add an initial row
        self.add_row()

    def add_row(self):
        row_position = self.table.rowCount()
        self.table.insertRow(row_position)
        
        # Set default values for new row
        self.table.setItem(row_position, 1, QTableWidgetItem("22"))
        self.table.setItem(row_position, 2, QTableWidgetItem("root"))

    def remove_selected_rows(self):
        selected_rows = sorted(list(set(index.row() for index in self.table.selectedIndexes())), reverse=True)
        for row in selected_rows:
            self.table.removeRow(row)

    def get_credentials_list(self):
        creds_list = []
        for row in range(self.table.rowCount()):
            ip = self.table.item(row, 0).text() if self.table.item(row, 0) else ""
            port = self.table.item(row, 1).text() if self.table.item(row, 1) else ""
            user = self.table.item(row, 2).text() if self.table.item(row, 2) else ""
            password = self.table.item(row, 3).text() if self.table.item(row, 3) else ""

            if all([ip, port, user]): # Password can be empty, though not recommended
                creds_list.append({
                    "ip": ip.strip(), "port": port.strip(), "user": user.strip(), "password": password
                })
            else:
                logger.warning(f"Skipping incomplete row {row+1} in multi-server setup.")
        return creds_list

class ProgressViewDialog(QDialog):
    """A dialog to show real-time output from a script."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Server Setup Progress")
        self.setMinimumSize(800, 600)

        self.layout = QVBoxLayout(self)
        self.output_area = QTextEdit()
        self.output_area.setReadOnly(True)
        self.output_area.setFont(QFont("Consolas", 9))
        self.layout.addWidget(self.output_area)

        self.close_button = QPushButton("Close")
        self.close_button.setEnabled(False)
        self.close_button.clicked.connect(self.accept)
        self.layout.addWidget(self.close_button)

    def append_output(self, text):
        self.output_area.append(text)

    def on_finished(self, success, message):
        color = "#2ecc71" if success else "#e74c3c"
        self.output_area.append(f'\n<font color="{color}"><b>{message}</b></font>')
        self.close_button.setEnabled(True)

class SyncDialog(QDialog):
    """Dialog to show user discrepancies and offer synchronization."""
    sync_requested = pyqtSignal(dict)

    def __init__(self, all_server_users, parent=None):
        super().__init__(parent)
        self.setWindowTitle("User Synchronization Check")
        self.setMinimumSize(800, 600)
        
        self.all_server_users = all_server_users
        self.users_to_sync = {}
        
        self.layout = QVBoxLayout(self)
        
        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["User", "Status", "Details"])
        self.layout.addWidget(self.tree)
        
        self.analyze_users()
        
        self.sync_button = QPushButton("Sync Missing Users")
        self.sync_button.clicked.connect(self.on_sync_clicked)
        if not self.users_to_sync:
            self.sync_button.setEnabled(False)
            self.sync_button.setText("All Users in Sync")

        buttons = QDialogButtonBox()
        buttons.addButton(self.sync_button, QDialogButtonBox.ButtonRole.ActionRole)
        buttons.addButton("Close", QDialogButtonBox.ButtonRole.RejectRole).clicked.connect(self.reject)
        self.layout.addWidget(buttons)

    def analyze_users(self):
        if not self.all_server_users or len(self.all_server_users) < 2:
            server_node = QTreeWidgetItem(self.tree, ["Sync check requires at least two servers with user data."])
            return

        all_users_set = set()
        for users in self.all_server_users.values():
            all_users_set.update(users)

        server_ips = list(self.all_server_users.keys())

        for user in sorted(list(all_users_set)):
            present_on = {ip for ip, users in self.all_server_users.items() if user in users}
            missing_on = set(server_ips) - present_on

            if not missing_on:
                # User exists everywhere
                status_text = "In Sync"
                servers_text = "All Servers"
                node = QTreeWidgetItem(self.tree, [user, status_text, servers_text])
                node.setForeground(1, QColor("#2ecc71"))
            else:
                # User is missing somewhere
                status_text = "Missing"
                servers_text = f"Missing on: {', '.join(sorted(list(missing_on)))}"
                node = QTreeWidgetItem(self.tree, [user, status_text, servers_text])
                node.setForeground(1, QColor("#f39c12"))
                # We need a password to add a user. We will ask for it when sync is clicked.
                self.users_to_sync[user] = {'missing_on': list(missing_on)}

        self.tree.expandAll()
        for i in range(self.tree.columnCount()):
            self.tree.resizeColumnToContents(i)

    def on_sync_clicked(self):
        """Asks for passwords for all users that need to be synced."""
        if not self.users_to_sync:
            return

        password_dialog = SyncPasswordsDialog(list(self.users_to_sync.keys()), self)
        if password_dialog.exec():
            passwords = password_dialog.get_passwords()
            if not passwords:
                QMessageBox.warning(self, "No Passwords", "No passwords were entered. Sync cancelled.")
                return

            for user in self.users_to_sync:
                if user in self.users_to_sync:
                    self.users_to_sync[user]['password'] = passwords[user]
            
            # Filter out users for whom no password was provided
            final_sync_list = {u: d for u, d in self.users_to_sync.items() if 'password' in d}

            if final_sync_list:
                self.sync_requested.emit(final_sync_list)
                self.accept()
            else:
                 QMessageBox.warning(self, "Sync Cancelled", "No users had passwords provided. Aborting sync.")


class SelectServersDialog(QDialog):
    """A dialog to select servers from a list with checkboxes."""
    def __init__(self, server_details, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Select Servers")
        self.server_details = server_details
        self.checkboxes = []

        layout = QVBoxLayout(self)
        
        form_layout = QFormLayout()
        for ip, port, user, _ in self.server_details:
            checkbox = QCheckBox(f"{user}@{ip}:{port}")
            checkbox.setChecked(True) # Default to all selected
            self.checkboxes.append(checkbox)
            form_layout.addRow(checkbox)
        
        layout.addLayout(form_layout)

        button_box = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        button_box.accepted.connect(self.accept)
        button_box.rejected.connect(self.reject)
        layout.addWidget(button_box)

    def get_selected_servers(self):
        selected = []
        for i, checkbox in enumerate(self.checkboxes):
            if checkbox.isChecked():
                selected.append(self.server_details[i])
        return selected

class ServerManagementDialog(QDialog):
    """Dialog to manage the list of servers."""
    def __init__(self, server_details, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Manage Servers")
        self.setMinimumSize(700, 450)
        
        self.layout = QVBoxLayout(self)
        
        # Table Widget
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(["IP Address", "Port", "Username", "Password"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        self.layout.addWidget(self.table)

        # Populate table with existing data
        for server in server_details:
            self.add_row(server)

        # Buttons for table manipulation
        button_layout = QHBoxLayout()
        add_row_button = QPushButton("Add Server")
        add_row_button.clicked.connect(lambda: self.add_row()) # Pass no args
        remove_row_button = QPushButton("Remove Selected Server(s)")
        remove_row_button.clicked.connect(self.remove_selected_rows)
        button_layout.addStretch()
        button_layout.addWidget(add_row_button)
        button_layout.addWidget(remove_row_button)
        self.layout.addLayout(button_layout)
        
        # OK/Cancel buttons
        dialog_buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        dialog_buttons.accepted.connect(self.accept)
        dialog_buttons.rejected.connect(self.reject)
        self.layout.addWidget(dialog_buttons)

    def add_row(self, server_data=None):
        row_position = self.table.rowCount()
        self.table.insertRow(row_position)
        
        if server_data:
            ip, port, user, password = server_data
            self.table.setItem(row_position, 0, QTableWidgetItem(ip))
            self.table.setItem(row_position, 1, QTableWidgetItem(port))
            self.table.setItem(row_position, 2, QTableWidgetItem(user))
            self.table.setItem(row_position, 3, QTableWidgetItem(password))
        else:
            # Set default values for new row
            self.table.setItem(row_position, 1, QTableWidgetItem("22"))
            self.table.setItem(row_position, 2, QTableWidgetItem("root"))

    def remove_selected_rows(self):
        selected_rows = sorted(list(set(index.row() for index in self.table.selectedIndexes())), reverse=True)
        for row in selected_rows:
            self.table.removeRow(row)

    def get_credentials_list(self):
        creds_list = []
        for row in range(self.table.rowCount()):
            ip = self.table.item(row, 0).text() if self.table.item(row, 0) else ""
            port = self.table.item(row, 1).text() if self.table.item(row, 1) else ""
            user = self.table.item(row, 2).text() if self.table.item(row, 2) else ""
            password = self.table.item(row, 3).text() if self.table.item(row, 3) else ""

            if all([ip, port, user]): # Password can be empty, though not recommended
                creds_list.append({
                    "ip": ip.strip(), "port": port.strip(), "user": user.strip(), "password": password
                })
            else:
                logger.warning(f"Skipping incomplete row {row+1} in server management.")
        return creds_list

class SyncPasswordsDialog(QDialog):
    """Asks for passwords for a list of users."""
    def __init__(self, users_to_sync, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Password(s) Required for Sync")
        self.users_to_sync = users_to_sync
        self.password_inputs = {}

        layout = QVBoxLayout(self)
        form_layout = QFormLayout()
        
        label = QLabel("Enter the correct current password for each user to sync them to other servers.")
        label.setWordWrap(True)
        layout.addWidget(label)

        for user in self.users_to_sync:
            password_edit = QLineEdit()
            password_edit.setEchoMode(QLineEdit.EchoMode.Password)
            self.password_inputs[user] = password_edit
            form_layout.addRow(f"Password for '{user}':", password_edit)

        layout.addLayout(form_layout)
        
        button_box = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        button_box.accepted.connect(self.accept)
        button_box.rejected.connect(self.reject)
        layout.addWidget(button_box)

    def get_passwords(self):
        passwords = {}
        for user, password_edit in self.password_inputs.items():
            if password_edit.text():
                passwords[user] = password_edit.text()
        return passwords

def main():
    print("Starting application...")
    try:
        # Ensure necessary files exist
        Config.ensure_files_exist()
        
        # Enable high DPI scaling - do this before creating QApplication
        print("Setting up high DPI scaling...")
        try:
            # Method 1: Using environment variables (most compatible)
            os.environ["QT_AUTO_SCREEN_SCALE_FACTOR"] = "1"
            os.environ["QT_SCALE_FACTOR"] = "1"
            os.environ["QT_SCREEN_SCALE_FACTORS"] = "1"
            print("High DPI scaling enabled via environment variables")
        except Exception as e:
            print(f"Could not set environment variables: {e}")
        
        # Create QApplication
        print("Creating QApplication...")
        app = QApplication(sys.argv)
        
        # Method 2: Try direct attribute setting if available
        try:
            # For PyQt6
            app.setAttribute(Qt.ApplicationAttribute.AA_UseHighDpiPixmaps)
            print("High DPI pixmaps enabled")
        except (AttributeError, TypeError):
            try:
                # Fallback
                app.setAttribute(Qt.AA_UseHighDpiPixmaps)
                print("High DPI pixmaps enabled (fallback)")
            except (AttributeError, TypeError):
                print("Could not enable high DPI pixmaps")
        
        app.setStyleSheet(DARK_STYLESHEET)
        print("Creating UserManagerApp...")
        window = UserManagerApp()
        print("Showing window...")
        window.show()
        print("Starting event loop...")
        sys.exit(app.exec())
    except Exception as e:
        print(f"CRITICAL ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()