# Minimal Sample

> [!WARNING]
> Legacy reference: this JavaScript data-source example is not validated with Kubling 26.4, and its image and bundle commands are obsolete. Use it to study the delegate contract, not as the repository Quickstart. Start with the [supported Quickstart](../quickstart/README.md).

Goal
: Get familiar with the basic structure of a `DBVirt` bundle file and JavaScript Modules

Difficulty
: Low

## How to test it

### 1. Generate bundle files
Execute [the gen-bundle script](gen-bundles.sh) to generate the zip files.

### 2. Point the source model to the JavaScript Module bundle 
Edit [VDB Scripting configuration file](descriptor/vdb/scripting/js-config.yaml) and add the URI of the 
`main-module-bundle.zip`, generated in the previous step, to property `zipFilePath`.

### 3. app-config
[This configuration file](app-config.yaml) is read during Engine initialization and, among internal configuration parameters,
tells the engine where to find the VDB Bundle file.
In our case, we will point to the file generated in the first step, called `minimal-descriptor-bundle.zip`.
Here you can opt for specifying the URI or keeping the variable `DESCRIPTOR_BUNDLE` which must be passed to the container.

### 4. Run container
This sample works well with our Community Edition, just replace the environment variables and run:

```
docker run --rm \ 
    -e DESCRIPTOR_BUNDLE=[/path/to/minimal-descriptor-bundle.zip] \
    -e APP_CONFIG=[/path/to/app-config.yaml] \
    -e MODULE_BUNDLE=[/path/to/main-module-bundle.zip] \
    -p 35432:35432 -p 35482:35482 -p 8282:8282 \
    -v [/path/to/dbvirt-samples]:[mount/path] \
    kubling/kubling:latest
```

Or, assuming that you cloned the repo in `~/dbvirt-samples`, just run:
```
docker run --rm \
    -e DESCRIPTOR_BUNDLE=/dbvirt-samples/minimal/minimal-descriptor-bundle.zip \
    -e APP_CONFIG=/dbvirt-samples/minimal/app-config.yaml \
    -e MODULE_BUNDLE=/dbvirt-samples/minimal/modules/main-module-bundle.zip \
    -p 35432:35432 -p 35482:35482 -p 8282:8282 \
    -v ~/dbvirt-samples:/dbvirt-samples \
    kubling/kubling:latest
```

### 5. Queries
Once the container is running, run `psql -h localhost -p 35432 -U sa -d application` in a terminal. Type any password,
we are not authenticating users in the example.
Some queries you can start with:
* `SELECT * from KUBLING_DEPLOYMENT;`
* `SELECT * from KUBLING_DEPLOYMENT WHERE name = 'some' AND age > 60;`
* `SELECT name from KUBLING_DEPLOYMENT ORDER BY name DESC LIMIT 10 offset 20;`
* `INSERT INTO KUBLING_DEPLOYMENT (name) VALUES ('my_name');`
* `DELETE FROM KUBLING_DEPLOYMENT WHERE name = 'my_name';`

Each query will print out the received context object and won't save or delete any information.   
