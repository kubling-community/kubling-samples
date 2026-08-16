# Authentication Sample

> [!WARNING]
> Legacy reference: this initializer and scheduler example is not validated with Kubling 26.4, and its image and bundle commands are obsolete. The JavaScript lifecycle code remains useful source material. Start with the [supported Quickstart](../quickstart/README.md).

Goal
: Use initializing and scheduling to keep a token up-to-date that we to pass all JS contexts.<br/>
In a real world use case, we could use this feature to avoid having to incorporate the logic of getting and verifying access
tokens and refreshing them in scripts like the `authenticator`, by keeping one global-scoped token per service, injected in all context's threads.

Difficulty
: Low

## How to test it

### 1. Generate bundle files
Execute [the gen-bundle script](gen-bundles.sh) to generate the zip files.

### 2. Point the source model to the JavaScript Module bundle 
Edit [VDB Scripting configuration file](descriptor/vdb/scripting/js-config.yaml) and add the URI of the 
`main-module-bundle.zip`, generated in the previous step, to property `zipFilePath`.

### 3. app-config
Point `descriptorBundle` to the file generated in the first step, called `rbac-descriptor-bundle.zip`.

### 4. Run container
This sample works well with our Community Edition, just replace the environment variables and run:

```
docker run --rm \ 
    -e DESCRIPTOR_BUNDLE=[/path/to/rbac-descriptor-bundle.zip] \
    -e APP_CONFIG=[/path/to/app-config.yaml] \
    -e MODULE_BUNDLE=[/path/to/main-module-bundle.zip] \
    -p 35432:35432 -p 35482:35482 -p 8282:8282 \
    -v [/path/to/dbvirt-samples]:[mount/path] \
    kubling/kubling:latest
```

Or, assuming that you cloned the repo in `~/dbvirt-samples`, just run:
```
docker run --rm \
    -e DESCRIPTOR_BUNDLE=/dbvirt-samples/initializer/initializer-descriptor-bundle.zip \
    -e APP_CONFIG=/dbvirt-samples/initializer/app-config.yaml \
    -e MODULE_BUNDLE=/dbvirt-samples/initializer/modules/tokenbased-module-bundle.zip \
    -p 35432:35432 -p 35482:35482 -p 8282:8282 \
    -v ~/dbvirt-samples:/dbvirt-samples \
    kubling/kubling:latest
```

### 5. Queries
Once the container is running, run `psql -h localhost -p 35432 -U sa -d DB` in a terminal. Type any password,
we are not authenticating users in the example.

Run `SELECT * FROM MY_TOKEN;` right after the engine starts, wait 10+ seconds and run it again, pay attention to field `token__decrypted`
