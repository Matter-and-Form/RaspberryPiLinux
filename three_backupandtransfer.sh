#!/bin/bash

# Check for correct number of arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <remote_user> <remote_password>"
    exit 1
fi

# Command line arguments for remote user and password
REMOTE_USER=$1
REMOTE_PASSWORD=$2

# Define other variables
OUTPUT_DIR="output_dir"
KERNEL_VERSION=$(basename $(ls -d ${OUTPUT_DIR}/lib/modules/*))
TRANSFER_DIR="transfer"
REMOTE_HOST="matterandform.local"
REMOTE_DEST="/tmp"
BACKUP_DIR="/backup_$(date +%Y%m%d_%H%M%S)"
ZIP_FILE="kernel_upgrade.zip"

# Step 1: Create a folder called transfer
echo "Creating transfer directory..."
mkdir -p ${TRANSFER_DIR}

# Step 2: Copy all modules from the output directory to the transfer folder
echo "Copying kernel modules to transfer directory..."
mkdir -p ${TRANSFER_DIR}/${KERNEL_VERSION}
cp -r ${OUTPUT_DIR}/lib/modules/${KERNEL_VERSION}/kernel ${TRANSFER_DIR}/${KERNEL_VERSION}/

# Step 3: Copy the Image file to the transfer folder as kernel8.img
echo "Copying kernel Image to transfer directory..."
cp arch/arm64/boot/Image ${TRANSFER_DIR}/kernel8.img

# Step 4: Copy the broadcom and the overlay device tree files to the transfer folder
echo "Copying Device Tree files to transfer directory..."
mkdir -p ${TRANSFER_DIR}/boot
cp arch/arm64/boot/dts/broadcom/*.dtb ${TRANSFER_DIR}/boot
mkdir -p ${TRANSFER_DIR}/boot/overlays
cp arch/arm64/boot/dts/overlays/*.dtb* ${TRANSFER_DIR}/boot/overlays/
cp arch/arm64/boot/dts/overlays/README ${TRANSFER_DIR}/boot/overlays/

# Step 5: Zip the folder and transfer it via SCP
echo "Zipping transfer directory..."
zip -r ${ZIP_FILE} ${TRANSFER_DIR}
echo "Transferring ${ZIP_FILE} to ${REMOTE_USER}@${REMOTE_HOST}..."
sshpass -p ${REMOTE_PASSWORD} scp ${ZIP_FILE} ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DEST}

# Step 6: Backup current overlays, kernel image, and modules on the remote system
echo "Backing up current kernel files on remote system..."
sshpass -p ${REMOTE_PASSWORD} ssh ${REMOTE_USER}@${REMOTE_HOST} "sudo mkdir -p ${BACKUP_DIR} && \
    sudo cp -r /boot ${BACKUP_DIR} && \
    sudo cp -r /lib/modules ${BACKUP_DIR}/"

# Step 7: Unzip the transferred files on the remote system and move them into place
echo "Unzipping and installing new kernel files on remote system..."
sshpass -p ${REMOTE_PASSWORD} ssh ${REMOTE_USER}@${REMOTE_HOST} "unzip -o ${REMOTE_DEST}/${ZIP_FILE} -d ${REMOTE_DEST}"

echo "Removing old files and copying new files..."
sshpass -p ${REMOTE_PASSWORD} ssh ${REMOTE_USER}@${REMOTE_HOST} "sudo rm /boot/*.img && \
    sudo rm /boot/*.dtb* && \
    sudo rm -rf /boot/overlays && \
    sudo cp ${REMOTE_DEST}/${TRANSFER_DIR}/kernel8.img /boot/ && \
    sudo cp -r ${REMOTE_DEST}/${TRANSFER_DIR}/boot/* /boot && \
    sudo mkdir -p /lib/modules/${KERNEL_VERSION} && \
    sudo rm -rf /lib/modules/${KERNEL_VERSION}/kernel && \
    sudo cp -r ${REMOTE_DEST}/${TRANSFER_DIR}/${KERNEL_VERSION}/kernel /lib/modules/${KERNEL_VERSION}/"

# Step 8: Run depmod to update module dependencies
echo "Running depmod on remote system..."
sshpass -p ${REMOTE_PASSWORD} ssh ${REMOTE_USER}@${REMOTE_HOST} "sudo depmod -a ${KERNEL_VERSION}"

echo "Kernel upgrade process completed successfully!"