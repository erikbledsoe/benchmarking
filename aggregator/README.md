# Aggregator benchmarking

We provide a simple script to run up multiple input VMs sending via TCP to a single Calyptia Core aggregator VM.
This is all configurable via the environment variables below:

| Name | Description | Default |
|------|-------------|---------|
|INPUT_IMAGE_NAME| The image to use for each of the input VMs | <https://www.googleapis.com/compute/v1/projects/calyptia-infra/global/images/calyptia-vendor-comparison-ubuntu-2004> |
|INPUT_MACHINE_TYPE| The GCP machine type for each of the input VMs | e2-highcpu-8 |
|INPUT_VM_COUNT| The number of input VMs to run. | 3 |
|INPUT_LOG_RATE| The number of log messages to generate per second on each input VM. | 2000 |
|INPUT_LOG_SIZE| The size of each log message in bytes. | 1000 |
|||
|CORE_VM_NAME| The name of the aggregator VM instance to create | benchmark-instance-core |
|CORE_IMAGE_NAME| The image to use for the aggregator VM. | <https://www.googleapis.com/compute/v1/projects/calyptia-infra/global/images/gold-calyptia-core-20220808152134-us> |
|CORE_MACHINE_TYPE| The GCP machine type for each of the input VMs | e2-highcpu-32 |

We require you to provide the following environment variables:

- CALYPTIA_CLOUD_PROJECT_TOKEN: The Calyptia Cloud project token to use.
- CALYPTIA_CLOUD_AGGREGATOR_NAME: The Calyptia Cloud aggregator name to use, this should be unique and not existing prior to running the script (remove and old ones if reusing)
