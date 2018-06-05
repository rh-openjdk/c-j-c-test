#!/bin/sh

set -eux

cat /etc/system-release

resultsDir="results"
resultsDirOpenJdk8="${resultsDir}/OpenJDK8"
resultsDirOpenJdk7="${resultsDir}/OpenJDK7"
resultsDirOracleJdk8="${resultsDir}/OracleJDK8"
resultsDirOracleJdk7="${resultsDir}/OracleJDK7"
resultsDirOracleJdk6="${resultsDir}/OracleJDK6"
resultsDirIbmJdk8="${resultsDir}/IbmJDK8"
resultsDirIbmJdk7="${resultsDir}/IbmJDK7"

mkdir "${resultsDir}"
mkdir "${resultsDirOpenJdk8}"
mkdir "${resultsDirOpenJdk7}"
mkdir "${resultsDirOracleJdk8}"
mkdir "${resultsDirOracleJdk7}"
mkdir "${resultsDirOracleJdk6}"
mkdir "${resultsDirIbmJdk8}"
mkdir "${resultsDirIbmJdk7}"


# java-1.8.0-openjdk
./test-cjc.sh \
--jdkName java-1.8.0-openjdk \
--oldJdkVersion 1.8.0.161 \
--oldJdkRelease 2.b14.el7 \
--newJdkVersion 1.8.0.171 \
--newJdkRelease 7.b10.el7 \
2>&1 | tee "${resultsDirOpenJdk8}/test.log"
mv test-summary.log "${resultsDirOpenJdk8}"

# java-1.7.0-openjdk
./test-cjc.sh \
--jdkName java-1.7.0-openjdk \
--oldJdkVersion 1.7.0.171 \
--oldJdkRelease 2.6.13.2.el7 \
--newJdkVersion 1.7.0.181 \
--newJdkRelease 2.6.14.3.el7 \
2>&1 | tee "${resultsDirOpenJdk7}/test.log"
mv test-summary.log "${resultsDirOpenJdk7}"

# java-1.8.0-oracle
./test-cjc.sh \
--jdkName java-1.8.0-oracle \
--oldJdkVersion 1.8.0.161 \
--oldJdkRelease 1jpp.2.el7 \
--newJdkVersion 1.8.0.171 \
--newJdkRelease 1jpp.1.el7 \
2>&1 | tee "${resultsDirOracleJdk8}/test.log"
mv test-summary.log "${resultsDirOracleJdk8}"

# java-1.7.0-oracle
./test-cjc.sh \
--jdkName java-1.7.0-oracle \
--oldJdkVersion 1.7.0.171 \
--oldJdkRelease 1jpp.1.el7 \
--newJdkVersion 1.7.0.181 \
--newJdkRelease 1jpp.1.el7 \
2>&1 | tee "${resultsDirOracleJdk7}/test.log"
mv test-summary.log "${resultsDirOracleJdk7}"

# java-1.6.0-sun
./test-cjc.sh \
--jdkName java-1.6.0-sun \
--oldJdkVersion 1.6.0.181 \
--oldJdkRelease 1jpp.2.el7 \
--newJdkVersion 1.6.0.191 \
--newJdkRelease 1jpp.1.el7 \
2>&1 | tee "${resultsDirOracleJdk6}/test.log"
mv test-summary.log "${resultsDirOracleJdk6}"

# java-1.8.0-ibm
#./test-cjc.sh \
#--jdkName java-1.8.0-ibm \
#--oldJdkVersion 1.8.0.5.5 \
#--oldJdkRelease 1jpp.2.el7 \
#--newJdkVersion 1.8.0.5.10 \
#--newJdkRelease 1jpp.1.el7 \
#2>&1 | tee "${resultsDirIbmJdk8}/test.log"
#mv test-summary.log "${resultsDirIbmJdk8}"

# java-1.8.0-ibm
./test-cjc.sh \
--jdkName java-1.8.0-ibm \
--oldJdkVersion 1.8.0.5.10 \
--oldJdkRelease 1jpp.1.el7 \
--newJdkVersion 1.8.0.5.10 \
--newJdkRelease 1jpp.3.el7 \
2>&1 | tee "${resultsDirIbmJdk8}/test.log"
mv test-summary.log "${resultsDirIbmJdk8}"

# java-1.7.1-ibm
./test-cjc.sh \
--jdkName java-1.7.1-ibm \
--oldJdkVersion 1.7.1.4.15 \
--oldJdkRelease 1jpp.2.el7 \
--newJdkVersion 1.7.1.4.20 \
--newJdkRelease 1jpp.1.el7 \
2>&1 | tee "${resultsDirIbmJdk7}/test.log"
mv test-summary.log "${resultsDirIbmJdk7}"

if cat "${resultsDir}"/*/test-summary.log | grep -q "FAILED" ; then
	printf '%s\n' "Result of all JDKs: FAILED"
	exit 1
else
	printf '%s\n' "Result of all JDKs: PASSED"
	exit 0
fi
