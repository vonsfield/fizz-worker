#!/bin/bash

clear
DESTINATION_DIR="/usr/local/bin"
BINARY_NAME="fizz"
VERSION="latest"

# Fizz variables
GATEWAY_ADDRESS="provider.spheron.nebulablock.com" # Provider domain: example = provider.devnetcsphn.com
GATEWAY_PROXY_PORT="8553" # Proxyport = 8553
GATEWAY_WEBSOCKET_PORT="8544" # ws url of the gateway example= ws://provider.devnetcsphn.com:8544
CPU_PRICE="4.5"
CPU_UNITS="6"
MEMORY_PRICE="1.6"
MEMORY_UNITS="16"
STORAGE_PRICE="6"
WALLET_ADDRESS="0x9C1499B6923e35f1C85f24e01c01A1CB952068a2" 
USER_TOKEN="0xec2dc0587b587734a73557e104c50e76c8fb0d82fb080b4050806db1cec7d89d564e3420892f7fcbb310ec34c580aec6da39ee65b2b986d204cc9ba0a7ae461b00"
STORAGE_UNITS="600"
GPU_MODEL=""
GPU_UNITS="0"
GPU_PRICE="0"
GPU_MEMORY="<gpu-memory>"
GPU_ID=""

# Function to detect the operating system
detect_os() {
    case "$(uname -s)" in
        Darwin*)    echo "macos" ;;
        Linux*)     
            if grep -q Microsoft /proc/version; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        CYGWIN*|MINGW32*|MSYS*|MINGW*) echo "windows" ;;
        *)          echo "unknown" ;;
    esac
}

OS=$(detect_os)
ARCH="$(uname -m)"

# Function to display system information
display_system_info() {
    echo "System Information:"
    echo "==================="
    echo "Detecting system configuration..."
    echo "Operating System: $OS"
    echo "Architecture: $ARCH"
    # CPU information
    case $OS in
        macos)
            cpu_cores=$(sysctl -n hw.ncpu)
            ;;
        linux|wsl)
            cpu_cores=$(nproc)
            ;;
        *)
            cpu_cores="Unknown"
            ;;
    esac
    echo "Available CPU cores: $cpu_cores"
    
    # disable cpu check
    # if [ "$cpu_cores" != "$CPU_UNITS" ]; then
    # echo "Error: Available CPU cores ($cpu_cores) does not match CPU_UNITS ($CPU_UNITS)"
    # exit 1
    # fi
    
    # Memory information
    case $OS in
        macos)
            total_memory=$(sysctl -n hw.memsize | awk '{printf "%.2f GB", $1 / 1024 / 1024 / 1024}')
            available_memory=$(vm_stat | awk '/Pages free/ {free=$3} /Pages inactive/ {inactive=$3} END {printf "%.2f GB", (free+inactive)*4096/1024/1024/1024}')
            ;;
        linux|wsl)
            total_memory=$(free -h | awk '/^Mem:/ {print $2}')
            available_memory=$(free -h | awk '/^Mem:/ {print $7}')
            ;;
        *)
            total_memory="Unknown"
            available_memory="Unknown"
            ;;
    esac
    echo "Total memory: $total_memory"
    echo "Available memory: $available_memory"
    
     if command -v nvidia-smi &> /dev/null; then
        echo -e "\nNVIDIA GPU Information:"
        echo "========================"
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
    fi
    
}

# Function to check bandwidth
check_bandwidth() {
    echo "Checking bandwidth..."
    if ! command -v speedtest-cli &> /dev/null; then
        echo "speedtest-cli not found. Installing..."
        case $OS in
            macos)
                brew install speedtest-cli
                ;;
            linux|wsl)
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update && sudo apt-get install -y speedtest-cli
                elif command -v yum &> /dev/null; then
                    sudo yum install -y speedtest-cli
                elif command -v dnf &> /dev/null; then
                    sudo dnf install -y speedtest-cli
                else
                    echo "Unable to install speedtest-cli. Please install it manually."
                    return 1
                fi
                ;;
            *)
                echo "Unsupported OS for automatic speedtest-cli installation. Please install it manually."
                return 1
                ;;
        esac
    fi

    # Run speedtest and capture results
    result=$(speedtest-cli 2>&1)
    if echo "$result" | grep -q "ERROR"; then
        echo "Error running speedtest: $result"
        BANDWIDTH_RANGE="NA"
    else
        download=$(echo "$result" | grep "Download" | awk '{print $2}')
        upload=$(echo "$result" | grep "Upload" | awk '{print $2}')

        if [[ -z "$download" || -z "$upload" ]]; then
            echo "Error: Could not parse download or upload speed"
            BANDWIDTH_RANGE="NA"
        else
            echo "Download speed: $download Mbit/s"
            echo "Upload speed: $upload Mbit/s"

            # Determine bandwidth range
            total_speed=$(echo "$download + $upload" | bc 2>/dev/null)
            if [[ $? -ne 0 || -z "$total_speed" ]]; then
                echo "Error: Could not calculate total speed"
                BANDWIDTH_RANGE="NA"
            else
                if (( $(echo "$total_speed < 50" | bc -l) )); then
                    BANDWIDTH_RANGE="10mbps"
                elif (( $(echo "$total_speed < 100" | bc -l) )); then
                    BANDWIDTH_RANGE="50mbps"
                elif (( $(echo "$total_speed < 200" | bc -l) )); then
                    BANDWIDTH_RANGE="100mbps"
                elif (( $(echo "$total_speed < 300" | bc -l) )); then
                    BANDWIDTH_RANGE="200mbps"
                elif (( $(echo "$total_speed < 400" | bc -l) )); then
                    BANDWIDTH_RANGE="300mbps"
                elif (( $(echo "$total_speed < 500" | bc -l) )); then
                    BANDWIDTH_RANGE="400mbps"
                elif (( $(echo "$total_speed < 1000" | bc -l) )); then
                    BANDWIDTH_RANGE="500mbps"
                elif (( $(echo "$total_speed < 5000" | bc -l) )); then
                    BANDWIDTH_RANGE="1gbps"
                elif (( $(echo "$total_speed < 10000" | bc -l) )); then
                    BANDWIDTH_RANGE="5gbps"
                elif (( $(echo "$total_speed >= 10000" | bc -l) )); then
                    BANDWIDTH_RANGE="10gbps"
                else
                    BANDWIDTH_RANGE="NA"
                fi
            fi
        fi
    fi

    echo "Bandwidth range: $BANDWIDTH_RANGE"
}

# Check for 'info' flag
if [ "$1" == "info" ]; then
    display_system_info
    check_bandwidth
    exit 0
fi

echo "===================================="
echo "      SPHERON FIZZ INSTALLER        "
echo "===================================="
echo ""
echo "$BINARY_NAME $VERSION"
echo ""


display_system_info 
check_bandwidth

# Function to install Docker and Docker Compose on macOS
install_docker_mac() {
    echo "Installing Docker for macOS..."
    if command -v brew &>/dev/null; then
        brew install --cask docker
    else
        echo "Homebrew is not installed. Please install Homebrew first:"
        echo "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    echo "Docker for macOS has been installed. Please start Docker from your Applications folder."
    echo "Docker Compose is included with Docker for Mac."
}

# Function to install Docker and Docker Compose on Ubuntu/Debian
install_docker_ubuntu() {
    if lspci | grep -q NVIDIA; then
        if ! nvidia-smi &>/dev/null; then
            echo "NVIDIA GPU detected, but drivers are not installed. Installing drivers !!!"
            sudo apt update
            sudo apt install -y alsa-utils
            sudo ubuntu-drivers autoinstall
            echo "NVIDIA Driver Installed, rebooting the system"
            echo "Please rerun the script after reboot"
            reboot now
        fi
        echo "NVIDIA GPU detected. Installing NVIDIA Docker"
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

        sudo apt-get update
        sudo apt-get install -y nvidia-docker2 jq
        sudo systemctl restart docker
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
        echo "Nvidia Docker and Docker Compose for Ubuntu/Debian have been installed. You may need to log out and back in for group changes to take effect."
    else 
        echo "Installing Docker for Ubuntu/Debian..."
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common jq
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        sudo apt-get install -y docker-compose
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo usermod -aG docker $USER
        echo "Docker and Docker Compose for Ubuntu/Debian have been installed. You may need to log out and back in for group changes to take effect."
    fi
}

# Function to install Docker and Docker Compose on Fedora
install_docker_fedora() {
    echo "Installing Docker for Fedora..."
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin jq
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    echo "Docker and Docker Compose for Fedora have been installed. You may need to log out and back in for group changes to take effect."
}

# Function to query nvidia-smi and verify GPU information
verify_gpu_info() {
    if command -v nvidia-smi &>/dev/null; then
        echo "Querying NVIDIA GPU information..."
        gpu_count=$(nvidia-smi --list-gpus | wc -l)
        gpu_model=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader,nounits | head -n1)
        gpu_memory_mib=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
        gpu_pcie_id=$(nvidia-smi --query-gpu=pci.device_id --format=csv,noheader | head -n1 | cut -c3-6 | tr '[:upper:]' '[:lower:]')
        
        json_url="https://spheron-release.s3.amazonaws.com/static/gpus-pcie.json"
        json_content=$(curl -s "$json_url") 

        read_json_value() {
            local json="$1"
            local key="$2"
            echo "$json" | jq -r --arg key "$key" '.[$key] // empty'    
        }

        gpu_key=$(read_json_value "$json_content" "$gpu_pcie_id")

        if [ "$gpu_key" != "$GPU_ID" ]; then
            echo "Error: GPU ID mismatch. Expected $GPU_ID, but found $gpu_key"
            exit 1
        fi
       
        echo "GPU ID Found: $gpu_key"
       
        gpu_memory_gib=$(awk "BEGIN {printf \"%.2f\", $gpu_memory_mib / 1024}")
        
        if [ $gpu_count -gt 0 ]; then
            echo "Detected $gpu_count GPU(s)"
            echo "GPU Model: $gpu_model"
            echo "GPU Memory: $gpu_memory_gib Gi"
            
            # Convert GPU_MODEL to lowercase and check if it contains "gpu"
            gpu_model_lower=$(echo "$gpu_model" | tr '[:upper:]' '[:lower:]')
            if [[ $gpu_model_lower == *"$GPU_MODEL"* ]]; then
                GPU_UNITS="$gpu_count"
                GPU_MEMORY="${gpu_memory_gib}Gi"
                
                echo "Updated GPU_MODEL: $GPU_MODEL"
                echo "Updated GPU_UNITS: $GPU_UNITS"
                echo "Updated GPU_MEMORY: $GPU_MEMORY GiB"
            else
                echo "GPU model does not contain 'gpu'. Skipping GPU_MODEL, GPU_UNITS, and GPU_MEMORY update."
            fi
        else
            echo "No NVIDIA GPU detected."
        fi
    else
        echo "nvidia-smi command not found. Unable to verify GPU information."
    fi
}

# Check if docker is installed
if ! command -v docker &>/dev/null; then
    echo "Docker is not installed. Please install Docker to continue."
    echo "For more information, please refer to https://docs.docker.com/get-docker/"
    # Detect OS and install Docker and Docker Compose accordingly
    if [[ "$OSTYPE" == "darwin"* ]]; then
        install_docker_mac
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
                install_docker_ubuntu
            elif [[ "$ID" == "fedora" ]]; then
                install_docker_fedora
            else
                echo "Unsupported Linux distribution. Please install Docker and Docker Compose manually."
                exit 1
            fi
        else
            echo "Unable to determine Linux distribution. Please install Docker and Docker Compose manually."
            exit 1
        fi
    else
        echo "Unsupported operating system. Please install Docker and Docker Compose manually."
        exit 1
    fi

    # Verify Docker and Docker Compose installation
    if command -v docker &>/dev/null && command -v docker compose &>/dev/null; then
        echo "Docker and Docker Compose have been successfully installed."
        docker --version
        docker compose version
    else
        echo "Docker and/or Docker Compose installation failed. Please try installing manually."
        exit 1
    fi
fi

# Verify GPU information
verify_gpu_info

# Function to determine which Docker Compose command works
get_docker_compose_command() {
    if command -v docker-compose &>/dev/null; then
        echo "docker-compose"
    elif docker compose version &>/dev/null; then
        echo "docker compose"
    else
        echo ""
    fi
}

# Get the working Docker Compose command
DOCKER_COMPOSE_CMD=$(get_docker_compose_command)
if [ -z "$DOCKER_COMPOSE_CMD" ]; then
    echo "Error: Neither 'docker-compose' nor 'docker compose' is available."
    exit 1
fi

# Check if the docker-compose.yml file exists
if [ -f ~/.spheron/fizz/docker-compose.yml ]; then
    echo "Stopping any existing Fizz containers..."
    $DOCKER_COMPOSE_CMD -f ~/.spheron/fizz/docker-compose.yml down
    $DOCKER_COMPOSE_CMD -f ~/.spheron/fizz/docker-compose.yml rm 
else
    echo "No existing Fizz configuration found. Skipping container cleanup."
fi


# Create config file
mkdir -p ~/.spheron/fizz
mkdir -p ~/.spheron/fizz-manifests
echo "Creating yml file..."
cat << EOF > ~/.spheron/fizz/docker-compose.yml
version: '2.2'

services:
  fizz:
    image: spheronnetwork/fizz:latest
    network_mode: "host"
    pull_policy: always
    privileged: true
    cpus: 1
    mem_limit: 512M
    restart: always
    environment:
      - GATEWAY_ADDRESS=$GATEWAY_ADDRESS
      - GATEWAY_PROXY_PORT=$GATEWAY_PROXY_PORT
      - GATEWAY_WEBSOCKET_PORT=$GATEWAY_WEBSOCKET_PORT
      - CPU_PRICE=$CPU_PRICE
      - MEMORY_PRICE=$MEMORY_PRICE
      - STORAGE_PRICE=$STORAGE_PRICE
      - WALLET_ADDRESS=$WALLET_ADDRESS
      - USER_TOKEN=$USER_TOKEN
      - CPU_UNITS=$CPU_UNITS
      - MEMORY_UNITS=$MEMORY_UNITS
      - STORAGE_UNITS=$STORAGE_UNITS
      - GPU_MODEL=$GPU_MODEL
      - GPU_UNITS=$GPU_UNITS
      - GPU_PRICE=$GPU_PRICE
      - GPU_MEMORY=$GPU_MEMORY 
      - BANDWIDTH_RANGE=$BANDWIDTH_RANGE
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ~/.spheron/fizz-manifests:/.spheron/fizz-manifests

EOF

# Check if the Docker image exists and remove it if present
if docker image inspect spheronnetwork/fizz:latest >/dev/null 2>&1; then
    echo "Removing existing Docker image..."
    docker rmi -f spheronnetwork/fizz:latest
else
    echo "Docker image 'spheronnetwork/fizz:latest' not found. Skipping removal."
fi

if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running. Attempting to start Docker..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open -a Docker
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo systemctl start docker
    else
        echo "Unsupported operating system. Please start Docker manually."
        exit 1
    fi

    # Wait for Docker to start
    echo "Waiting for Docker to start..."
    until docker info >/dev/null 2>&1; do
        sleep 1
    done
    echo "Docker has been started successfully."
fi


echo "Starting Fizz..."
$DOCKER_COMPOSE_CMD  -f ~/.spheron/fizz/docker-compose.yml up -d --force-recreate

echo ""
echo "============================================"
echo "Fizz Is Installed and Running successfully"
echo "============================================"
echo ""
echo "To fetch the logs, run:"
echo "$DOCKER_COMPOSE_CMD -f ~/.spheron/fizz/docker-compose.yml logs -f"
echo ""
echo "To stop the service, run:"
echo "$DOCKER_COMPOSE_CMD -f ~/.spheron/fizz/docker-compose.yml down"
echo "============================================"
echo "Thank you for installing Fizz! 🎉"
echo "============================================"
echo ""
echo "Fizz logs:"
$DOCKER_COMPOSE_CMD -f ~/.spheron/fizz/docker-compose.yml logs -f
