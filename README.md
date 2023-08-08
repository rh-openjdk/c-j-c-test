# c-j-c-test
This is testsuite for testing [copy-jdk-configs](https://pagure.io/copy_jdk_configs) package. It performs upgrade/downgrade in several scenarios (unmodified config files, modified config files, deleted config files) an checks if behavior meets [expectations](https://www.cl.cam.ac.uk/~jw35/docs/rpm_config.html).

## Example usage
```
sudo dnf install copy-jdk-configs
./test-cjc.sh --jdkName "java-1.8.0-openjdk" --oldJdkAuto --newJdkAuto
```
