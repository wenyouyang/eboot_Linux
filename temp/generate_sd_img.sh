#!/bin/bash

##### Constants
IMAGE_SIZE_MB=768
BOOT_PART_SIZE_MB=64
BOOT_PART_NAME="BOOT"
ROOTFS_PART_NAME="ROOTFS"
TMPMNT_DIR=tmpmnt
BUILDROOT_SD_IMG_NAME=sdcard.img

TOP_DIR=`pwd`

# Configuration
if [ -f  build_config.sh ]; then
	source build_config.sh
else
	echo "## error: not able to find configuration file"
	exit 1
fi

# Data
if [ -f board_data.sh ]; then
	source board_data.sh
else
	echo "## error: not able to find board data file"
	exit 1
fi


##### Functions
# TODO: implement parameters and use the "usage" function
#function usage
#{
#    echo "usage: $0 [-a at91bootstrap] [-u u-boot] [-k kernel] [-d dtb] [-r rootfs_archive]"
#}

function cp_boot
{
	echo "Copying boot files..."
	sudo mount /dev/mapper/${LOOP_DEV}p1 ${TMPMNT_DIR}/BOOT/
	if [ $? -ne 0 ]; then
		echo "## error: can't mount BOOT partition"
		return 1
	else
		#sudo cp README ${TMPMNT_DIR}/BOOT/
		sudo cp ${AT91BOOTSTRAP} ${TMPMNT_DIR}/BOOT/BOOT.BIN
		sudo cp ${UBOOT} ${TMPMNT_DIR}/BOOT/u-boot.bin
		sudo cp ${UBOOT_ENV} ${TMPMNT_DIR}/BOOT/uboot.env
		sudo cp ${KERNEL} ${TMPMNT_DIR}/BOOT/zImage
		sudo cp ${DTB} ${TMPMNT_DIR}/BOOT/
		
		for dtb in ${DTBS}; do
			sudo cp ${_SRC_DIR}/*.dtb ${TMPMNT_DIR}/BOOT/
		done
	fi

	return 0
}

function cp_rootfs
{
	echo "Extracting rootfs..."
	sudo mount /dev/mapper/${LOOP_DEV}p2 ${TMPMNT_DIR}/ROOTFS/
	if [ $? -ne 0 ]; then
		echo "## error: can't mount ROOTFS partition"
		return 1
	else
		sudo tar xaf $ROOTFS -C ${TMPMNT_DIR}/ROOTFS/
		if [ $? -ne 0 ]; then
			echo "## error: can't extract rootfs"
			return 1
		fi
	fi

	return 0
}

function cleanup_img_gen
{
	echo "Cleaning up image generation..."
	sync
	sudo umount -f ${TMPMNT_DIR}/BOOT
	sudo umount -f ${TMPMNT_DIR}/ROOTFS
	rmdir ${TMPMNT_DIR}/BOOT
	rmdir ${TMPMNT_DIR}/ROOTFS
	rmdir ${TMPMNT_DIR}
	sudo kpartx -d ${IMAGE}
	rm -f ${UBOOT_ENV} ${UBOOT_ENV}.txt
}

function check_files() {
	local _SRC_DIR=$1

	for f in $AT91BOOTSTRAP $UBOOT $KERNEL $ROOTFS; do
		if [ ! -f "${_SRC_DIR}/$f" ]; then
			echo "### error: can't find file: ${_SRC_DIR}/$f"
			return 1
		fi
	done

	for dtb in ${DTBS}; do
		if [ ! -f "${_SRC_DIR}/${dtb}" ]; then
			echo "### error: can't find file: ${_SRC_DIR}/${dtb}"
			return 1
		fi
	done
}

##### Main
#for i in `find . -maxdepth 1 -name "sdcard_linux4sam-buildroot-*" | sort`; do
#for i in `find . -maxdepth 1 -name "sdcard_linux4sam-buildroot-*" | sort`; do
for i in `find . -maxdepth 1 -name "sdcard_linux4sam-*" | sort`; do


	echo "========== Entering ${i} directory =========="
	cd ${i}

	MACHINE=`echo ${i} | cut -f3 -d-`
	if [ "${MACHINE}" == "at91sam9x5ek" ]; then
		VARIANT="ek_dm"
	else
		VARIANT=`echo ${MACHINE} | cut -f3 -d_`
	fi
	if [ "x${VARIANT}" != "x" ]; then
		MACHINE=`echo ${MACHINE} | sed s/_${VARIANT}//`
	fi
	IMAGE_NAME=`echo ${i} | sed s/sdcard_//`
	IMAGE_NAME="${IMAGE_NAME}-${TAG}"
	if [ "x${VARIANT}" == "x" ]; then
		BUILT_VARIANT=""
	else
		BUILT_VARIANT=" VARIANT: ${VARIANT}"
	fi
	echo "MACHINE: ${MACHINE}${BUILT_VARIANT} IMAGE: ${IMAGE_NAME}"

	# do we have to go further?
	# if machine not listed in AT91_BOARD_FAMILY variable, give up here
	echo ${AT91_BOARD_FAMILY} | grep ${MACHINE} > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Nothing to do : board not listed in AT91_BOARD_FAMILY"
		cd ${TOP_DIR}
		continue
	fi

	# If we are in a Buildroot directory, there is a sdcard.img file,
	# the only thing to do is to compress this image.
	if [ -f ${BUILDROOT_SD_IMG_NAME} ]; then
		echo "Generating the image archive..."
		bzip2 -k9 ${BUILDROOT_SD_IMG_NAME}
		mv ${BUILDROOT_SD_IMG_NAME}.bz2 ${DELIVERY_DIR}/${IMAGE_NAME}.img.bz2

		cd ${TOP_DIR}
		continue
	fi

	AT91BOOTSTRAP=`find . -name "at91bootstrap-*.bin"`
	if [ -z "${AT91BOOTSTRAP}" ]; then
		echo "## error: at91bootstrap missing"
		exit 1
	fi
	echo "- at91bootstrap: ${AT91BOOTSTRAP}"
	UBOOT=`find . -name "u-boot-*-sd.bin"`
	if [ -z "${UBOOT}" ]; then
		echo "## error: u-boot missing"
		exit 1
	fi
	echo "- u-boot: ${UBOOT}"

	UBOOT_ENV="uboot.env"
	
	KERNEL=`find . -name "zImage-*-sd.bin"`
	if [ -z "${KERNEL}" ]; then
		echo "## error: zImage missing"
		exit 1
	fi
	echo "- kernel: ${KERNEL}"

	# arbitrary dtb for at91sam9x5ek
	if [ "${MACHINE}" == "at91sam9x5ek" ]; then
		DTB="at91sam9g35ek.dtb"
	else
		DTB=`find . -name "*.dtb"`
	fi
	if [ -z "${DTB}" ]; then
		echo "## error: device tree missing"
		exit 1
	fi
	echo "- device tree file: ${DTB}"

	ROOTFS=`find . -name "*-sd.tar.gz"`
	if [ -z "${ROOTFS}" ]; then
		echo "## error: root filesystem missing"
		exit 1
	fi
	echo "- rootfs: ${ROOTFS}"

	IMAGE="${IMAGE_NAME}.img"

	BOOTARGS="console=ttyS0,${console_baudrate[${MACHINE}]}"
	if [ ! ${mci_id[${MACHINE}]} ]; then
		BOOTCMD="fatload mmc 0:1 0x21000000 `basename ${DTB}`; fatload mmc 0:1 0x22000000 zImage; bootz 0x22000000 - 0x21000000"
		BOOTARGS="${BOOTARGS} root=/dev/mmcblk0p2 rw rootfstype=ext4 rootwait"
	else
		BOOTCMD="fatload mmc ${mci_id[${MACHINE}]}:1 0x21000000 `basename ${DTB}`; fatload mmc ${mci_id[${MACHINE}]}:1 0x22000000 zImage; bootz 0x22000000 - 0x21000000"
		BOOTARGS="${BOOTARGS} root=/dev/mmcblk${mci_id[${MACHINE}]}p2 rw rootfstype=ext4 rootwait"
	fi

	if [ "x${VARIANT}" != "x" ]; then
		BOOTARGS="${BOOTARGS} video=${video_mode[${VARIANT}]}"
	fi


	cat <<-EOF > ${UBOOT_ENV}.txt
	bootargs=${BOOTARGS}
	bootcmd=${BOOTCMD}
	bootdelay=1
	ethact=gmac0
	stderr=serial
	stdin=serial
	stdout=serial
	EOF
	mkenvimage -s 16384 -o ${UBOOT_ENV} ${UBOOT_ENV}.txt

	echo "Creating image file..."
	dd if=/dev/zero of=${IMAGE} bs=1M count=${IMAGE_SIZE_MB}

	# Creating mount directories 
	mkdir -p ${TMPMNT_DIR}/BOOT
	mkdir -p ${TMPMNT_DIR}/ROOTFS
	# Issue with old version of util-linux. Tested with 2.27.1 and 2.28.
	echo "Creating partitions..."
	echo "First partition is ${BOOT_PART_NAME}, ${BOOT_PART_SIZE_MB} MB"
	BOOT_PART_SIZE_SECT=$((${BOOT_PART_SIZE_MB} * 1024 * 1024 / 512))
	BOOT_PART_FIRST_SECT=2048
	BOOT_PART_LAST_SECT=$((${BOOT_PART_FIRST_SECT} + ${BOOT_PART_SIZE_SECT} - 1))
	echo -e "\tnumber of sectors = ${BOOT_PART_SIZE_SECT}"
	echo -e "\tfirst sectors     = ${BOOT_PART_FIRST_SECT}"
	echo -e "\tlast  sectors     = ${BOOT_PART_LAST_SECT}"
	/sbin/sfdisk -q --unit S ${IMAGE} << EOF
	${BOOT_PART_FIRST_SECT},${BOOT_PART_SIZE_SECT},0xb,*
	,,L,-
EOF
	echo "Mounting partitions..."
	sudo /sbin/kpartx -v -s -a ${IMAGE}
	if [ $? -ne 0 ]; then
		echo "### error: unable to create device maps"
		cleanup_img_gen
		exit 1
	fi

	LOOP_DEV=$(sudo /sbin/losetup -j ${IMAGE} | cut -f 1 -d ":" | cut -f 3 -d "/")
	if [ -z "${LOOP_DEV}" ]; then
		echo "### error: unable to find loop device"
		cleanup_img_gen
		exit 1
	fi
	echo "Loop dev used ${LOOP_DEV}"

	echo "Formating partitions..."
	sudo mkfs.vfat -F 32 /dev/mapper/${LOOP_DEV}p1 -n ${BOOT_PART_NAME} ${BOOT_PART_SIZE_SECT}
	RET=$?
	# TODO: implement tune2fs -O ^huge_file
	sudo mkfs.ext4 /dev/mapper/${LOOP_DEV}p2 -L ${ROOTFS_PART_NAME}
	if [ $? -ne 0 -o $RET -ne 0 ]; then
		echo "### error: unable to format partitions"
		cleanup_img_gen
		exit 1
	fi

	cp_boot
	if [ $? -eq 0 ]; then
		cp_rootfs
		if [ $? -ne 0 ]; then
			cleanup_img_gen
			exit 1
		fi
	fi 

	# Cleanup
	cleanup_img_gen

	echo "Generating the image archive..."
	bzip2 -9 ${IMAGE}
	mv ${IMAGE}.bz2 ${DELIVERY_DIR}

	cd ${TOP_DIR}

done

echo "#########################################################"
echo " $(basename $0) done without error."
exit 0
