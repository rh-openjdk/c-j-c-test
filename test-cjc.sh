#!/bin/sh

set -eux

downloadUrls="https://kojihub.stream.centos.org/kojifiles/packages
https://kojipkgs.fedoraproject.org/packages"

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
		--downloadUrl)
			downloadUrls="$( printf '%s\n%s' "${2}" "${downloadUrls}"  )"
			shift
			shift
			;;
		--rpmCacheDir)
			rpmCacheDir="${2}"
			shift
			shift
			;;
		--jdkSuffix)
			jdkSuffix="${2}"
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

jdkArch="$( uname -m )"

# firt empty line is intentional (it is no suffix)
jdkRpmSuffixes="
-devel"

if printf '%s\n' "${jdkName}" | grep -q "java-11-openjdk" ; then
jdkRpmSuffixes="${jdkRpmSuffixes}
-jmods"
if [ -z "${jdkSuffix:-}" ] ; then
jdkRpmSuffixes="${jdkRpmSuffixes}
-javadoc
-javadoc-zip"
fi
fi

if printf '%s\n' "${jdkName}" | grep -q "openjdk" ; then
# openjdks
	if printf '%s\n' "${jdkName}" | grep -q '^java-1.7.0-openjdk' \
	&& printf '%s\n' "${newJdkRelease:-}" | grep -q '\.el6' ; then
		# jdk7 on rhel 6 does not have headless package
		true
	else
		jdkRpmSuffixes="${jdkRpmSuffixes}
		-headless"
	fi
jdkRpmSuffixes="${jdkRpmSuffixes}
-demo
-src"
fi

if printf '%s\n' "${jdkName}" | grep -q "java-1.8.0-ibm" \
|| printf '%s\n' "${jdkName}" | grep -q "java-1.8.0-oracle" ; then
jdkRpmSuffixes="${jdkRpmSuffixes}
-plugin"
	if printf '%s\n' "${newJdkRelease:-}" | grep -q '\.el8' ; then
		jdkRpmSuffixes="${jdkRpmSuffixes}
-webstart
-headless
-demo
-jdbc
-src"
	fi
fi

if [ -n "${jdkSuffix:-}" ] ; then
    jdkRpmSuffixes="$( printf '%s' "${jdkRpmSuffixes}" | sed "s/\$/${jdkSuffix}/g" )"
fi

oldJdkInstName="${jdkName}"
newJdkInstName="${jdkName}"
if printf '%s\n' "${jdkName}" | grep -q "java-latest-openjdk" ; then
	majorVersionPattern='^([0-9]+)[.].*$'
	oldJdkVersionMajor="$( printf '%s' "${oldJdkVersion}" | sed -E "s/${majorVersionPattern}/\\1/g" )"
	oldJdkInstName="$( printf '%s' "${oldJdkInstName}" | sed "s/-latest-/-${oldJdkVersionMajor}-/g" )"
	newJdkVersionMajor="$( printf '%s' "${newJdkVersion}" | sed -E "s/${majorVersionPattern}/\\1/g" )"
	newJdkInstName="$( printf '%s' "${newJdkInstName}" | sed "s/-latest-/-${newJdkVersionMajor}-/g" )"
fi

cjcName="copy-jdk-configs"
testLog="test-summary.log"
tmpDir=""
if [ -z "${rpmCacheDir:-}" ] ; then
	rpmCacheDir="rpmcache"
fi
etcPrefix="/etc/java"
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
		printf '%s\n' "${downloadUrls}" \
		| while read -r dlUrl ; do
			if  wget -P "${dlDir}" "${dlUrl}/${name}/${version}/${release}/${architecture}/${rpmName}" ; then
				break;
			fi
		done
		[ -e  "${dlDir}/${rpmName}" ] || return 1
	else
		printf 'Rpm %s found in cache, skipping' "${rpmName}" 1>&2
	fi
)

downloadJdk() (
	version="$1"
	release="$2"

	printf '%s\n' "${jdkRpmSuffixes}" \
	| while read -r rpm ; do
		rpmName="${jdkName}${rpm}"
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
	mkdir "${oldRpmsDir}"
	oldArchRpmsDir="$( getRpmCacheDir "${jdkName}" "${oldJdkVersion}" "${oldJdkRelease}" "${jdkArch}" )"
	createRpmLinks "${oldArchRpmsDir}" "${oldRpmsDir}"
	oldNoarchRpmsDir="$( getRpmCacheDir "${jdkName}" "${oldJdkVersion}" "${oldJdkRelease}" "noarch" )"
	createRpmLinks "${oldNoarchRpmsDir}" "${oldRpmsDir}"

	downloadJdk "${newJdkVersion}" "${newJdkRelease}"
	mkdir "${newRpmsDir}"
	newArchRpmsDir="$( getRpmCacheDir "${jdkName}" "${newJdkVersion}" "${newJdkRelease}" "${jdkArch}" )"
	createRpmLinks "${newArchRpmsDir}" "${newRpmsDir}"
	newNoarchRpmsDir="$( getRpmCacheDir "${jdkName}" "${newJdkVersion}" "${newJdkRelease}" "noarch" )"
	createRpmLinks "${newNoarchRpmsDir}" "${newRpmsDir}"
)


getJdkConfigFiles() (
	rpmsDir="$1"
	instName="$2"
	for rpm in "${rpmsDir}"/*.rpm ; do
		rpm -qcp "${rpm}" \
		| sed -E \
		-e "s;^${jdkInstallPrefix}/[^/]+/;${jdkInstallPrefix}/@{JVM_DIR_NAME}/;" \
		-e "s;^${etcPrefix}/${instName}/[^/]+/;${etcPrefix}/${instName}/@{JVM_DIR_NAME}/;"
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
		jdkDirName="${name}-${version}-${release}.${architecture}${jdkSuffix:-}"
	fi
	printf '%s' "${jdkDirName}"
)

setGlobals() {
	configFilesOld="$( getJdkConfigFiles "${oldRpmsDir}" "${oldJdkInstName}" | sort -u )"
	configFilesNew="$( getJdkConfigFiles "${newRpmsDir}" "${newJdkInstName}" | sort -u )"
	jdkDirNameOld="$( getJdkDirName "${oldJdkInstName}" "${oldJdkVersion}" "${oldJdkRelease}" "${jdkArch}" )"
	jdkDirNameNew="$( getJdkDirName "${newJdkInstName}" "${newJdkVersion}" "${newJdkRelease}" "${jdkArch}" )"
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
	sudo rm -rf "/usr/lib/jvm/${oldJdkInstName}"*
	sudo rm -rf "/usr/lib/jvm/${newJdkInstName}"*
	if [ -d "/etc/java" ] ; then
		sudo rm -rf "/etc/java/${jdkName}"
		sudo rm -rf "/etc/java/${oldJdkInstName}"
		sudo rm -rf "/etc/java/${newJdkInstName}"
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

	oldNvrPattern="${jdkDirNameOld}"
	oldNvrSubst='${NVR_OLD}'
	newNvrPattern="${jdkDirNameNew}"
	newNvrSubst='${NVR_NEW}'

	message="$( printf '%s' "${message}" | sed -e "s/${oldNvrPattern}/${oldNvrSubst}/g" -e "s/${newNvrPattern}/${newNvrSubst}/g"  )"

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
		pkgName="${jdkName}${suffix}"
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
	fileWithModifications="${file}"
	if ! testFileExists "${file}.rpmnew" && ! testFileExists "${file}.rpmsave" && ! testFileExists "${file}.rpmorig" ; then
		if ! isSameJdkDirOldNew ; then
			printf '%s\n' "FAIL: Neither of ${file}.rpmnew, ${file}.rpmsave, ${file}.rpmorig exists" 1>&2
			err=1
		fi
	else
		bckpFileCount=0
		if testFileExists "${file}.rpmnew" ; then
			bckpFileCount="$(( bckpFileCount + 1 ))"
		fi
		if testFileExists "${file}.rpmsave" ; then
			fileWithModifications="${file}.rpmsave"
			bckpFileCount="$(( bckpFileCount + 1 ))"
		fi
		if testFileExists "${file}.rpmorig" ; then
			fileWithModifications="${file}.rpmorig"
			bckpFileCount="$(( bckpFileCount + 1 ))"
		fi
		if [ "${bckpFileCount}" -ne 1 ] ; then
			printf '%s\n' "FAIL: Exactly one of ${file}.rpmnew, ${file}.rpmsave, ${file}.rpmorig is expected to exist!" 1>&2
			err=1
		fi
	fi
	if ! cat "${fileWithModifications}" | grep -q "${testPattern}" ; then
		printf '%s\n' "FAIL: File ${fileWithModifications} does not have modified content !" 1>&2
		err=1
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

EMPTY_DIR="/etc/empty_dir.test"

testRogueLinksEl7() (
	testMessage "TEST: Update with rogue links in /usr/lib/jvm"

	checkedCommand "Installing old JDK" installOld
	checkedCommand "Verifying installed files (old)" verifyJdkInstallation

	sudo mkdir -p $EMPTY_DIR
	ROGUE_LINK="/usr/lib/jvm/${jdkDirNameOld}/passwd.link"
	sudo ln -s "/etc/passwd" "$ROGUE_LINK"

	checkedCommand "Installing new JDK" installNew
	#checkedCommand "Verifying installed files (new)" verifyJdkInstallation
	set +e
	verifyJdkInstallation
	echo $?

	sudo rm "$ROGUE_LINK"
	#checkedCommand "checking if update deleted empty dirs" $([[ -d "$EMPTY_DIR" ]])
	test -d "$EMPTY_DIR"
	echo $?
	set -e
)

testRogueLinksEl8() (
	testMessage "TEST: Update with rogue links in /etc/java"

	checkedCommand "Installing old JDK" installOld
	checkedCommand "Verifying installed files (old)" verifyJdkInstallation

	sudo mkdir -p $EMPTY_DIR
	ROGUE_LINK="/etc/java/${jdkDirNameOld}/passwd.link"
	sudo mkdir -p "/etc/java/${jdkDirNameOld}"
	sudo ln -s "/etc/passwd" "$ROGUE_LINK"

	checkedCommand "Installing new JDK" installNew
	checkedCommand "Verifying installed files (new)" verifyJdkInstallation

	sudo rm "$ROGUE_LINK"
	checkedCommand "checking if update deleted empty dirs" $([[ -d "$EMPTY_DIR" ]]) 
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
testRogueLinksEl7
cleanupJdks
testRogueLinksEl8
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
