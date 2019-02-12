#!/bin/sh

set -eux

brewUrl="http://localhost/brewroot/packages"
brewUrl2="http://localhost/brewroot/vol/rhel-6/packages"

while [ "$#" -gt 0 ] ; do
	arg="$1"
	case "$arg" in
		--jdkName)
			jdkName="${2}"
			shift
			shift
			;;
		--oldJdkVersion)
			oldJdkVersion="${2}"
			shift
			shift
			;;
		--oldJdkRelease)
			oldJdkRelease="${2}"
			shift
			shift
			;;
		--newJdkVersion)
			newJdkVersion="${2}"
			shift
			shift
			;;
		--newJdkRelease)
			newJdkRelease="${2}"
			shift
			shift
			;;
		*)
			printf '%s\n' "Unsupported arg: $1"
			exit 1
			;;
	esac
done

if [ -z "${jdkName:-}" ] ; then
	printf '%s\n' "jdkName not set"
	exit 1
fi

if [ -z "${oldJdkVersion:-}" ] ; then
	printf '%s\n' "oldJdkVersion not set"
	exit 1
fi

if [ -z "${oldJdkRelease:-}" ] ; then
	printf '%s\n' "oldJdkRelease not set"
	exit 1
fi

if [ -z "${newJdkVersion:-}" ] ; then
	printf '%s\n' "newJdkVersion not set"
	exit 1
fi

if [ -z "${newJdkRelease:-}" ] ; then
	printf '%s\n' "newJdkRelease not set"
	exit 1
fi

jdkArch="x86_64"

# firt empty line is intentional (it is no suffix)
jdkRpmSuffixes="
devel"

if printf '%s\n' "${jdkName}" | grep -q "java-11-openjdk" ; then
jdkRpmSuffixes="${jdkRpmSuffixes}
jmods
javadoc
javadoc-zip"
fi

if printf '%s\n' "${jdkName}" | grep -q "openjdk" ; then
# openjdks
	if printf '%s\n' "${jdkName}" | grep -q '^java-1.7.0-openjdk' \
	&& printf '%s\n' "${newJdkRelease:-}" | grep -q '\.el6' ; then
		# jdk7 on rhel 6 does not have headless package
		true
	else
		jdkRpmSuffixes="${jdkRpmSuffixes}
		headless"
	fi
jdkRpmSuffixes="${jdkRpmSuffixes}
demo
src"
fi

if printf '%s\n' "${jdkName}" | grep -q "java-1.8.0-ibm" \
|| printf '%s\n' "${jdkName}" | grep -q "java-1.8.0-oracle" ; then
jdkRpmSuffixes="${jdkRpmSuffixes}
plugin"
fi



cjcName="copy-jdk-configs"
testLog="test-summary.log"
tmpDir=""
rpmCacheDir="rpmcache"
etcPrefix="/etc/java/${jdkName}"
jdkInstallPrefix="/usr/lib/jvm"

cleanup() {
	if [ -n "${tmpDir:-}" ] ; then
		rm -rf "${tmpDir}"
	fi
}

basicInit() {
	tmpDir="$( mktemp -d )"
	trap cleanup EXIT

	rpmCacheDir="$( readlink -f "${rpmCacheDir}" )"

	newRpmsDir="${tmpDir}/newrpms"
	oldRpmsDir="${tmpDir}/oldrpms"

	pkgMan="yum"
	if type dnf &> /dev/null ; then
		pkgMan="dnf"
	fi
}

getRpmCacheDir() (
	name="$1"
	version="$2"
	release="$3"
	architecture="$4"

	printf '%s' "${rpmCacheDir}/${name}/${version}/${release}/${architecture}"
)

downloadRpm() (
	name="$1"
	version="$2"
	release="$3"
	architecture="$4"
	rpmName="$5"

	rpmName="${rpmName}-${version}-${release}.${architecture}.rpm"
	dlDir="$( getRpmCacheDir "${name}" "${version}" "${release}" "${architecture}" )"
	if ! [ -d "${dlDir}" ] ; then
		mkdir -p "${dlDir}"
	fi
	if ! [ -e  "${dlDir}/${rpmName}" ] ; then
		if ! wget -P "${dlDir}" "${brewUrl}/${name}/${version}/${release}/${architecture}/${rpmName}" ; then
			wget -P "${dlDir}" "${brewUrl2}/${name}/${version}/${release}/${architecture}/${rpmName}"
		fi
	else
		printf 'Rpm %s found in cache, skipping' "${rpmName}" 1>&2
	fi
)

downloadJdk() (
	version="$1"
	release="$2"

	printf '%s\n' "${jdkRpmSuffixes}" \
	| while read -r rpm ; do
		rpmName="${jdkName}${rpm:+-}${rpm}"
		downloadRpm "${jdkName}" "${version}" "${release}" "${jdkArch}" "${rpmName}"
	done
)

createRpmLinks() (
	srcDir="${1}"
	targetDir="${2}"

	if [ -d "${srcDir}" ] ; then
		for rpm in "${srcDir}/"* ; do
			if [ -e "${rpm}" ] ; then
				ln -s "${rpm}" "${targetDir}/$( basename "${rpm}" )"
			fi
		done
	fi
)

prepare() (
	tee "${testLog}" <<- EOF
	INFO: c-j-c: $( rpm -qa | grep copy-jdk-config )
	INFO: JDK old: ${jdkName}-${oldJdkVersion}-${oldJdkRelease}.${jdkArch}
	INFO: JDK new: ${jdkName}-${newJdkVersion}-${newJdkRelease}.${jdkArch}

	EOF

	downloadJdk "${oldJdkVersion}" "${oldJdkRelease}"
	downloadJdk "${newJdkVersion}" "${newJdkRelease}"

	mkdir "${oldRpmsDir}"
	oldArchRpmsDir="$( getRpmCacheDir "${jdkName}" "${oldJdkVersion}" "${oldJdkRelease}" "${jdkArch}" )"
	createRpmLinks "${oldArchRpmsDir}" "${oldRpmsDir}"
	oldNoarchRpmsDir="$( getRpmCacheDir "${jdkName}" "${oldJdkVersion}" "${oldJdkRelease}" "noarch" )"
	createRpmLinks "${oldNoarchRpmsDir}" "${oldRpmsDir}"

	mkdir "${newRpmsDir}"
	newArchRpmsDir="$( getRpmCacheDir "${jdkName}" "${newJdkVersion}" "${newJdkRelease}" "${jdkArch}" )"
	createRpmLinks "${newArchRpmsDir}" "${newRpmsDir}"
	newNoarchRpmsDir="$( getRpmCacheDir "${jdkName}" "${newJdkVersion}" "${newJdkRelease}" "noarch" )"
	createRpmLinks "${newNoarchRpmsDir}" "${newRpmsDir}"
)


getJdkConfigFiles() (
	rpmsDir="$1"
	for rpm in "${rpmsDir}"/*.rpm ; do
		rpm -qcp "${rpm}" \
		| sed \
		-e "s;^${jdkInstallPrefix}/[^/]\+/;${jdkInstallPrefix}/@{JVM_DIR_NAME}/;" \
		-e "s;^${etcPrefix}/[^/]\+/;${etcPrefix}/@{JVM_DIR_NAME}/;"
	done
)

getJdkDirName() (
	name="$1"
	version="$2"
	release="$3"
	architecture="$4"

	if [ "${name}" = "java-1.6.0-sun" ] ; then
		jdkDirName="${name}-${version}.${architecture}"
	elif printf '%s\n' "${jdkName}" | grep -q '^java-1.7.0-openjdk' \
	&& printf '%s\n' "${newJdkRelease:-}" | grep -q '\.el6' ; then
		jdkDirName="${name}-${version}.${architecture}"
	elif printf '%s\n' "${jdkName}" | grep -q '^java-1.8.0-oracle' \
	&& printf '%s\n' "${newJdkRelease:-}" | grep -q '\.el6' ; then
		jdkDirName="${name}-${version}.${architecture}"
	elif printf '%s\n' "${jdkName}" | grep -q '^java-1.7.1-ibm' \
	&& printf '%s\n' "${newJdkRelease:-}" | grep -q '\.el6' ; then
		jdkDirName="${name}-${version}.${architecture}"
	elif printf '%s\n' "${jdkName}" | grep -q '^java-1.8.0-ibm' \
	&& printf '%s\n' "${newJdkRelease:-}" | grep -q '\.el6' ; then
		jdkDirName="${name}-${version}.${architecture}"
	else
		jdkDirName="${name}-${version}-${release}.${architecture}"
	fi
	printf '%s' "${jdkDirName}"
)

setGlobals() {
	configFilesOld="$( getJdkConfigFiles "${oldRpmsDir}" | sort -u )"
	configFilesNew="$( getJdkConfigFiles "${newRpmsDir}" | sort -u )"
	jdkDirNameOld="$( getJdkDirName "${jdkName}" "${oldJdkVersion}" "${oldJdkRelease}" "${jdkArch}" )"
	jdkDirNameNew="$( getJdkDirName "${jdkName}" "${newJdkVersion}" "${newJdkRelease}" "${jdkArch}" )"
}

isSameJdkDirOldNew() {
	if [ "x${jdkDirNameOld}" = "x${jdkDirNameNew}" ] ; then
		return 0
	fi
	return 1
}

installOld() {
	sudo "${pkgMan}" -y install --exclude="${cjcName}" "${oldRpmsDir}"/*.rpm
}

installNew() {
	sudo "${pkgMan}" -y install --exclude="${cjcName}" "${newRpmsDir}"/*.rpm
}

upgradeToNew() {
	sudo "${pkgMan}" -y upgrade --exclude="${cjcName}" "${newRpmsDir}"/*.rpm
}

downgradeToOld() {
	sudo "${pkgMan}" -y downgrade --exclude="${cjcName}" "${oldRpmsDir}"/*.rpm
}

cleanupJdks() {
	sudo "${pkgMan}" -y remove --exclude="${cjcName}" "${jdkName}*"
	sudo rm -rf "/usr/lib/jvm/${jdkName}"*
	if [ -d "/etc/java" ] ; then
		sudo rm -rf "/etc/java/${jdkName}"
	fi
}

testMessage() (
	message="$1"

	tee -a "${testLog}" <<- EOF
	${message}
	EOF
)

checkedCommand() (
	message="$1"
	shift

	tee -a "${testLog}" <<- EOF
	INFO: ${message}
	EOF
	if "$@" ; then
		tee -a "${testLog}" <<- EOF
		PASSED: ${message}
		EOF
	else
		tee -a "${testLog}" <<- EOF
		FAILED: ${message}
		EOF
	fi
)

verifyJdkInstallation() (
	verifyString="$(
	printf '%s\n' "${jdkRpmSuffixes}" \
	| while read -r suffix ; do
		pkgName="${jdkName}${suffix:+-}${suffix}"
		rpm -V "${pkgName}"
	done | grep -v "classes.jsa" )"
	if [ -n "${verifyString}" ] ; then
		printf '%s\n' "${verifyString}"
		return 1
	fi
	return 0
)

testContainsPattern() (
	file="$1"
	pattern="$2"

	if [ -e "${file}" ] && cat "${file}" | grep -q "${pattern}" ; then
		return 0
	fi
	return 1
)

testFileExists() (
	file="$1"

	if [ -e "${file}" ] ; then
		return 0
	fi
	return 1
)

testFileNotExists() (
	file="$1"

	if [ -e "${file}" ] ; then
		return 1
	fi
	return 0
)

testFileUnmodifiedInstall() (
	file="$1"

	err=0
	if ! testFileExists "${file}" ; then
		printf '%s\n' "FAIL: File does not exist ${file} !" 1>&2
		err=1
	fi

	if testFileExists "${file}.rpmnew" ; then
		printf '%s\n' "FAIL: File exists ${file}.rpmnew !" 1>&2
		err=1
	fi

	if testFileExists "${file}.rpmsave" ; then
		printf '%s\n' "FAIL: File exists ${file}.rpmsave !" 1>&2
		err=1
	fi
	return "${err}"

)

testPattern="# sfjsalkfjlsakfjslfjs"

modifyFile() (
	file="$1"
	modifiedFile="${tmpDir}/modified"

	sudo cp -p "${file}" "${tmpDir}/$( basename "${file}" )"
	printf '%s\n' "${testPattern}" | sudo sh -c 'cat >> "$1"' sh "${modifiedFile}"
	sudo mv -f "${modifiedFile}" "${file}"
	sudo rm -rf "${modifiedFile}" || true
)

testFileModifiedInstall() (
	file="$1"

	err=0
	if ! testFileExists "${file}" ; then
		printf '%s\n' "FAIL: File does not exist ${file} !" 1>&2
		err=1
	fi

	if ! testFileExists "${file}.rpmnew" && ! testFileExists "${file}.rpmsave" ; then
		if ! isSameJdkDirOldNew ; then
			printf '%s\n' "FAIL: Nor ${file}.rpmnew nor ${file}.rpmsave exists !" 1>&2
			err=1
		elif ! cat "${file}" | grep -q "${testPattern}" ; then
			printf '%s\n' "FAIL: File ${file} does not have expected content !" 1>&2
			err=1
		fi
	elif testFileExists "${file}.rpmnew" && testFileExists "${file}.rpmsave" ; then
		printf '%s\n' "FAIL: Both ${file}.rpmnew and ${file}.rpmsave exist !" 1>&2
		err=1
	else
		fileWithModifications="${file}"
		if testFileExists "${file}.rpmsave" ; then
			fileWithModifications="${file}.rpmsave"
		fi
		if ! cat "${fileWithModifications}" | grep -q "${testPattern}" ; then
			printf '%s\n' "FAIL: File ${fileWithModifications} does not have expected content !" 1>&2
			err=1
		fi
	fi

	return "${err}"
)

testUpdateUnmodified() (
	testMessage "TEST: Update, config files unmodified"

	checkedCommand "Installing old JDK" installOld
	checkedCommand "Verifying installed files (old)" verifyJdkInstallation
	checkedCommand "Installing new JDK" installNew
	checkedCommand "Verifying installed files (new)" verifyJdkInstallation
	printf '%s\n' "${configFilesNew}" \
	| sed "s;@{JVM_DIR_NAME};${jdkDirNameNew};" \
	| while read -r configFile ; do
		checkedCommand "checking ${configFile}" testFileUnmodifiedInstall "${configFile}"
	done
	testMessage ""
)

testDowngradeUnmodified() (
	testMessage "TEST: Downgrade, config files unmodified"

	checkedCommand "Installing new JDK" installNew
	checkedCommand "Verifying installed files (new)" verifyJdkInstallation
	checkedCommand "Downgrading to old JDK" downgradeToOld
	checkedCommand "Verifying installed files (old)" verifyJdkInstallation
	printf '%s\n' "${configFilesOld}" \
	| sed "s;@{JVM_DIR_NAME};${jdkDirNameOld};" \
	| while read -r configFile ; do
		checkedCommand "checking ${configFile}" testFileUnmodifiedInstall "${configFile}"
	done
	testMessage ""
)

testUpdateModified() (
	testMessage "TEST: Upgrade, config files modified"

	checkedCommand "Installing old JDK" installOld
	checkedCommand "Verifying installed files (old)" verifyJdkInstallation
	printf '%s\n' "${configFilesNew}" \
	| sed "s;@{JVM_DIR_NAME};${jdkDirNameOld};" \
	| while read -r configFile ; do
		checkedCommand "Modifying ${configFile}" modifyFile "${configFile}"
	done
	checkedCommand "Installing new JDK" installNew
	printf '%s\n' "${configFilesNew}" \
	| sed "s;@{JVM_DIR_NAME};${jdkDirNameNew};" \
	| while read -r configFile ; do
		checkedCommand "checking ${configFile}" testFileModifiedInstall "${configFile}"
	done
	testMessage ""
)

testDowngradeModified() (
	testMessage "TEST: Downgrade, config files modified"

	checkedCommand "Installing new JDK" installNew
	checkedCommand "Verifying installed files (new)" verifyJdkInstallation
	printf '%s\n' "${configFilesOld}" \
	| sed "s;@{JVM_DIR_NAME};${jdkDirNameNew};" \
	| while read -r configFile ; do
		checkedCommand "Modifying ${configFile}" modifyFile "${configFile}"
	done

	checkedCommand "Downgrading to old JDK" downgradeToOld
	printf '%s\n' "${configFilesOld}" \
	| sed "s;@{JVM_DIR_NAME};${jdkDirNameOld};" \
	| while read -r configFile ; do
		checkedCommand "checking ${configFile}" testFileModifiedInstall "${configFile}"
	done
	testMessage ""
)

testUpgradeDeleted() (
	testMessage "TEST: Update, config files deleted"

	checkedCommand "Installing old JDK" installOld
	checkedCommand "Verifying installed files (old)" verifyJdkInstallation
	printf '%s\n' "${configFilesNew}" \
	| sed "s;@{JVM_DIR_NAME};${jdkDirNameOld};" \
	| while read -r configFile ; do
		sudo rm -rf "${configFile}"
	done
	checkedCommand "Installing new JDK" installNew
	printf '%s\n' "${configFilesNew}" \
	| sed "s;@{JVM_DIR_NAME};${jdkDirNameNew};" \
	| while read -r configFile ; do
		checkedCommand "checking ${configFile}" testFileUnmodifiedInstall "${configFile}"
	done
	testMessage ""
)

testDowngradeDeleted() (
	testMessage "TEST: Downgrade, config files deleted"

	checkedCommand "Installing new JDK" installNew
	checkedCommand "Verifying installed files (new)" verifyJdkInstallation
	printf '%s\n' "${configFilesOld}" \
	| sed "s;@{JVM_DIR_NAME};${jdkDirNameNew};" \
	| while read -r configFile ; do
		sudo rm -rf "${configFile}"
	done
	checkedCommand "Downgrading to old JDK" downgradeToOld
	printf '%s\n' "${configFilesOld}" \
	| sed "s;@{JVM_DIR_NAME};${jdkDirNameOld};" \
	| while read -r configFile ; do
		checkedCommand "checking ${configFile}" testFileUnmodifiedInstall "${configFile}"
	done
	testMessage ""
)

basicInit
prepare
setGlobals
cleanupJdks || true
testUpdateUnmodified
cleanupJdks
testDowngradeUnmodified
cleanupJdks
testUpdateModified
cleanupJdks
testDowngradeModified
cleanupJdks
testUpgradeDeleted
cleanupJdks
testDowngradeDeleted
cleanupJdks

overallResult=0
cat "${testLog}" | grep -q "^FAILED:" && overallResult=1

if [ "${overallResult}" -eq 0 ] ; then
	testMessage "OVERALL RESULT: PASSED"
	exit 0
else
	testMessage "OVERALL RESULT: FAILED"
	exit 1
fi
