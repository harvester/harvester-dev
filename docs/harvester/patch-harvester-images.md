## op:harvester-patch-images

The `op:harvester-patch-images` task patches the `harvester` managed chart to pull the `harvester` and `harvester-webhook` container images from a custom registry, then waits for the chart to reconcile.

### Usage

```sh
task op:harvester-patch-images -- <REPOSITORY> <TAG>
```

Example:

```sh
task op:harvester-patch-images -- 10.0.100.1:5000/rancher e2e-workflow-head-amd64
```

> NOTE
>
> If you include a registry in the `REPOSITORY`, you must ensure the registry has a publicly trusted certificate.

### Development Usage 

For development purposes, you can omit the registry and use the task in combination with the [op:harvester-configure-registries](configure-registries.md) task. Assume you have a insecure HTTP registry at `http://172.17.0.1:5000`:

* Push your images to the registry. Assume you the images are tagged with:

  ```
  rancher/harvester:dev
  rancher/harvester-webhook:dev
  ```

* Configure containerd mirrors in the Harvester cluster:
  * Edit config.yaml

    ```yaml
    harvester:
      registry_mirrors:
        - registry: docker.io
          endpoint: http://172.17.0.1:5000
    ```

  * Configure the `containerd-registry` settings in Harvester:

    ```bash
    task op:harvester-configure-registries
    ```

* Run this task to patch images:

  ```
  task op:harvester-patch-images -- rancher dev
  ```

This will configure k8s to run the harvester and harvester-webhook deployments with the `rancher/harvester:dev` and `rancher/harvester-webhook:dev` images. And use the private registry as the mirror.


### How the task works

The script (`op/harvester/patch-harvester-images.sh`) runs three steps:

1. **Pause** the `harvester` managed chart so Fleet does not reconcile mid-patch.
2. **Patch** the chart's `spec.values` with the new image coordinates:

   ```yaml
   spec:
     values:
       webhook:
         image:
           imagePullPolicy: Always
           repository: <REPOSITORY>/harvester-webhook
           tag: <TAG>
       containers:
         apiserver:
           image:
             imagePullPolicy: Always
             repository: <REPOSITORY>/harvester
             tag: <TAG>
   ```

3. **Unpause** the chart and wait (up to 5 minutes) for the managed chart to reach the `ready` state before returning.

The kubeconfig at `./kubeconfig` is used. Run `task op:nodes-get-kubeconfig` first if it does not exist yet.
