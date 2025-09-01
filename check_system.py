#!/usr/bin/env python3
"""
System compatibility checker for Apple Subscription Service
This script checks if the system has all the required dependencies and helps set up the environment.
"""
import os
import sys
import subprocess
import platform
import argparse
import shutil

# ANSI color codes for terminal output
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
BLUE = '\033[0;34m'
NC = '\033[0m'  # No Color

def print_colored(text, color):
    """Print text with color"""
    print(f"{color}{text}{NC}")

def run_command(command, check=True):
    """Run a shell command and return the output"""
    try:
        result = subprocess.run(command, check=check, shell=True, 
                                text=True, capture_output=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        if check:
            print_colored(f"Error running command: {e}", RED)
            print_colored(f"Command output: {e.stderr}", RED)
        return None

def is_command_available(command):
    """Check if a command is available on the system"""
    return shutil.which(command) is not None

def is_linux():
    """Check if the system is Linux"""
    return platform.system().lower() == 'linux'

def is_mac():
    """Check if the system is macOS"""
    return platform.system().lower() == 'darwin'

def is_debian_based():
    """Check if the system is Debian-based"""
    if not is_linux():
        return False
    
    return os.path.exists('/etc/debian_version')

def check_python_version():
    """Check Python version"""
    print_colored("\nChecking Python version...", BLUE)
    
    version = platform.python_version()
    print(f"Python version: {version}")
    
    major, minor, _ = map(int, version.split('.'))
    
    if major < 3 or (major == 3 and minor < 8):
        print_colored("❌ Python 3.8 or higher is required!", RED)
        return False
    else:
        print_colored("✅ Python version is compatible.", GREEN)
        return True

def check_pip():
    """Check pip installation"""
    print_colored("\nChecking pip installation...", BLUE)
    
    if is_command_available('pip') or is_command_available('pip3'):
        pip_cmd = 'pip3' if is_command_available('pip3') else 'pip'
        pip_version = run_command(f"{pip_cmd} --version")
        print(f"pip version: {pip_version}")
        print_colored("✅ pip is installed.", GREEN)
        return True
    else:
        print_colored("❌ pip is not installed!", RED)
        if is_debian_based():
            print_colored("Installing pip...", YELLOW)
            run_command("apt-get update && apt-get install -y python3-pip")
            if is_command_available('pip3'):
                print_colored("✅ pip was installed successfully.", GREEN)
                return True
        return False

def check_venv():
    """Check venv module"""
    print_colored("\nChecking venv module...", BLUE)
    
    try:
        import venv
        print_colored("✅ venv module is available.", GREEN)
        return True
    except ImportError:
        print_colored("❌ venv module is not available!", RED)
        if is_debian_based():
            print_colored("Installing python3-venv...", YELLOW)
            run_command("apt-get update && apt-get install -y python3-venv")
            try:
                import venv
                print_colored("✅ venv module was installed successfully.", GREEN)
                return True
            except ImportError:
                return False
        return False

def check_postgres():
    """Check PostgreSQL installation and development libraries"""
    print_colored("\nChecking PostgreSQL...", BLUE)
    
    if is_linux():
        if is_debian_based():
            postgres_status = run_command("dpkg -l | grep postgresql", check=False)
            if postgres_status:
                print_colored("✅ PostgreSQL is installed.", GREEN)
            else:
                print_colored("❌ PostgreSQL is not installed!", RED)
                print_colored("Installing PostgreSQL...", YELLOW)
                run_command("apt-get update && apt-get install -y postgresql postgresql-contrib")
                print_colored("✅ PostgreSQL was installed.", GREEN)
            
            # Check for development libraries
            libpq_status = run_command("dpkg -l | grep libpq-dev", check=False)
            if libpq_status:
                print_colored("✅ PostgreSQL development libraries are installed.", GREEN)
            else:
                print_colored("❌ PostgreSQL development libraries are not installed!", RED)
                print_colored("Installing PostgreSQL development libraries...", YELLOW)
                run_command("apt-get update && apt-get install -y libpq-dev postgresql-server-dev-all")
                print_colored("✅ PostgreSQL development libraries were installed.", GREEN)
            
            return True
        else:
            print_colored("⚠️ Non-Debian Linux detected. Please install PostgreSQL and its development libraries manually.", YELLOW)
            return False
    elif is_mac():
        if is_command_available('brew'):
            postgres_status = run_command("brew list | grep postgresql", check=False)
            if postgres_status:
                print_colored("✅ PostgreSQL is installed via Homebrew.", GREEN)
            else:
                print_colored("❌ PostgreSQL is not installed via Homebrew!", RED)
                print_colored("Installing PostgreSQL via Homebrew...", YELLOW)
                run_command("brew install postgresql libpq")
                print_colored("✅ PostgreSQL was installed via Homebrew.", GREEN)
                
                print_colored("Setting up environment for PostgreSQL...", YELLOW)
                run_command("brew link --force libpq")
                
                # Add environment variables to shell profile
                shell_profile = None
                if os.path.exists(os.path.expanduser("~/.zshrc")):
                    shell_profile = os.path.expanduser("~/.zshrc")
                elif os.path.exists(os.path.expanduser("~/.bash_profile")):
                    shell_profile = os.path.expanduser("~/.bash_profile")
                elif os.path.exists(os.path.expanduser("~/.bashrc")):
                    shell_profile = os.path.expanduser("~/.bashrc")
                
                if shell_profile:
                    with open(shell_profile, 'a') as f:
                        f.write('\n# PostgreSQL environment variables for psycopg2\n')
                        f.write('export LDFLAGS="-L$(brew --prefix libpq)/lib"\n')
                        f.write('export CPPFLAGS="-I$(brew --prefix libpq)/include"\n')
                        f.write('export PATH="$(brew --prefix libpq)/bin:$PATH"\n')
                    
                    print_colored(f"✅ Added PostgreSQL environment variables to {shell_profile}.", GREEN)
                    print_colored(f"⚠️ Please run 'source {shell_profile}' or restart your terminal session.", YELLOW)
            
            return True
        else:
            print_colored("❌ Homebrew is not installed! Cannot install PostgreSQL automatically.", RED)
            print_colored("Please install Homebrew and PostgreSQL manually.", RED)
            return False
    else:
        print_colored("⚠️ Unsupported operating system. Please install PostgreSQL and its development libraries manually.", YELLOW)
        return False

def check_build_tools():
    """Check build tools"""
    print_colored("\nChecking build tools...", BLUE)
    
    if is_linux():
        if is_debian_based():
            build_essential_status = run_command("dpkg -l | grep build-essential", check=False)
            if build_essential_status:
                print_colored("✅ Build tools are installed.", GREEN)
            else:
                print_colored("❌ Build tools are not installed!", RED)
                print_colored("Installing build tools...", YELLOW)
                run_command("apt-get update && apt-get install -y build-essential python3-dev")
                print_colored("✅ Build tools were installed.", GREEN)
            return True
        else:
            print_colored("⚠️ Non-Debian Linux detected. Please install build-essential and python3-dev manually.", YELLOW)
            return False
    elif is_mac():
        xcode_tools = run_command("xcode-select -p", check=False)
        if xcode_tools:
            print_colored("✅ Xcode command line tools are installed.", GREEN)
            return True
        else:
            print_colored("❌ Xcode command line tools are not installed!", RED)
            print_colored("Installing Xcode command line tools...", YELLOW)
            run_command("xcode-select --install")
            print_colored("⚠️ Please complete the Xcode installation when prompted.", YELLOW)
            return False
    else:
        print_colored("⚠️ Unsupported operating system. Please install build tools manually.", YELLOW)
        return False

def check_psycopg2_installation():
    """Try to install psycopg2 and check for issues"""
    print_colored("\nTesting psycopg2 installation...", BLUE)
    
    # Create a temporary directory for testing
    temp_dir = os.path.join(os.getcwd(), "psycopg2_test")
    if not os.path.exists(temp_dir):
        os.makedirs(temp_dir)
    
    # Create a temporary virtual environment
    venv_dir = os.path.join(temp_dir, "venv")
    run_command(f"python3 -m venv {venv_dir}")
    
    # Determine the pip command based on the platform
    if is_linux() or is_mac():
        pip_cmd = f"source {venv_dir}/bin/activate && pip"
    else:
        pip_cmd = f"{venv_dir}\\Scripts\\pip"
    
    # Update pip and install wheel
    run_command(f"{pip_cmd} install --upgrade pip wheel setuptools")
    
    # Try to install psycopg2-binary
    print_colored("Attempting to install psycopg2-binary...", YELLOW)
    result = run_command(f"{pip_cmd} install psycopg2-binary", check=False)
    
    if result is None or "ERROR" in result or "error" in result:
        print_colored("❌ Failed to install psycopg2-binary directly.", RED)
        
        # Set environment variables for macOS
        if is_mac():
            env_vars = 'LDFLAGS="-L$(brew --prefix libpq)/lib" CPPFLAGS="-I$(brew --prefix libpq)/include"'
            print_colored("Trying with explicit PostgreSQL paths on macOS...", YELLOW)
            result = run_command(f"{env_vars} {pip_cmd} install psycopg2-binary", check=False)
            
            if result is None or "ERROR" in result or "error" in result:
                print_colored("❌ Still failed with explicit paths.", RED)
                print_colored("Trying psycopg2 instead of psycopg2-binary...", YELLOW)
                result = run_command(f"{env_vars} {pip_cmd} install psycopg2", check=False)
        else:
            print_colored("Trying psycopg2 instead of psycopg2-binary...", YELLOW)
            result = run_command(f"{pip_cmd} install psycopg2", check=False)
    
    if result is None or "ERROR" in result or "error" in result:
        print_colored("❌ All psycopg2 installation attempts failed.", RED)
        print_colored("Please check your PostgreSQL installation and development libraries.", RED)
        return False
    else:
        print_colored("✅ psycopg2 installation successful!", GREEN)
        return True
    
    # Clean up
    shutil.rmtree(temp_dir, ignore_errors=True)

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Check system compatibility for Apple Subscription Service")
    parser.add_argument("--fix", action="store_true", help="Attempt to fix any issues")
    args = parser.parse_args()
    
    print_colored("==================================================", BLUE)
    print_colored("Apple Subscription Service - System Compatibility Check", BLUE)
    print_colored("==================================================", BLUE)
    
    print(f"Operating System: {platform.system()} {platform.release()}")
    print(f"Machine: {platform.machine()}")
    
    python_ok = check_python_version()
    pip_ok = check_pip()
    venv_ok = check_venv()
    postgres_ok = check_postgres()
    build_tools_ok = check_build_tools()
    
    if args.fix and python_ok and pip_ok and venv_ok and postgres_ok and build_tools_ok:
        psycopg2_ok = check_psycopg2_installation()
    else:
        psycopg2_ok = False
    
    print_colored("\n==================================================", BLUE)
    print_colored("System Compatibility Summary:", BLUE)
    print_colored("==================================================", BLUE)
    print(f"Python 3.8+: {'✅ Compatible' if python_ok else '❌ Not Compatible'}")
    print(f"pip: {'✅ Available' if pip_ok else '❌ Not Available'}")
    print(f"venv: {'✅ Available' if venv_ok else '❌ Not Available'}")
    print(f"PostgreSQL: {'✅ Ready' if postgres_ok else '❌ Not Ready'}")
    print(f"Build Tools: {'✅ Ready' if build_tools_ok else '❌ Not Ready'}")
    
    if args.fix:
        print(f"psycopg2 Test: {'✅ Success' if psycopg2_ok else '❌ Failed'}")
    
    all_ok = python_ok and pip_ok and venv_ok and postgres_ok and build_tools_ok
    if args.fix:
        all_ok = all_ok and psycopg2_ok
    
    if all_ok:
        print_colored("\n✅ System is ready for Apple Subscription Service!", GREEN)
        sys.exit(0)
    else:
        print_colored("\n❌ System is not ready. Please fix the issues highlighted above.", RED)
        sys.exit(1)

if __name__ == "__main__":
    main()
