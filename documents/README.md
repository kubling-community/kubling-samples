# Documents Sample

> [!WARNING]
> Legacy reference: this sample is not validated with Kubling 26.4. Its synthetic-entity and JavaScript examples remain useful, but its external mock and run instructions are obsolete. Start with the [supported Quickstart](../quickstart/README.md).

Goal
: Learn how to deal with complex nested documents, and how to decide whether Kubling can help.

Difficulty
: Medium

## Schema-and-Tuple-Based Design in an Industry Dominated by Document-Based Interfaces—Why?

Kubling is not meant to replace any system's API. However, there is a clear tendency to adapt organizations to 
systems and cloud providers, rather than the other way around. This makes DevOps operations —and especially 
application development— challenging and often confusing.

Most organizations have chosen to discard their internal IT/Cloud operation models in favor of specific tools 
that developers cannot access directly due to "security reasons". Not surprising.

A good example is Kubernetes. Instead of discussing how to migrate to containerized workloads, many organizations 
have invested time and energy in implementing Kubernetes as a tool — without a clear definition of what it truly 
implies or how to prepare their ecosystem to operate on it.

Kubling's mission is to isolate upstream system complexity as much as possible by defining universal 
concepts (entities) such as Code Repository, Artifact Repository, Container Image, Container Instance (run), 
Metric, and Log Entry. These concepts are made to operate consistently beyond simple provisioning.

### Consistency and Traceability

Consistency in our context means relationships. For example:
- A Container Instance relates to an Image hosted in an Artifact Repository.
- That Image is built using resources hosted in a Code Repository.

Without a proper schema, defining this level of traceability is difficult. Once established, it simplifies IT/Cloud/Security 
operations significantly.

Kubling serves as an abstraction layer —a facade— that knows nothing about interacting with specific implementations 
like GitHub (as a Code Repository) or Kubernetes (as a container orchestrator). This knowledge is dynamically loaded 
into the engine as JavaScript modules.

## The problem of arrays in JSON and YAML Documents
When acting as a facade, Kubling transforms JSON-based documents exchanged with other systems via their APIs into tuples. 
Flattening a JSON document is straightforward, but capturing essential information for operational purposes can be challenging, 
particularly when dealing with dynamic array sections in complex response documents.

### Example: Kubernetes Deployment
Kubernetes `Deployment` documents can define multiple `containers` under `spec.template.spec.containers`. 
Suppose we need to retrieve a `Deployment` with two containers. Flattening the document as-is results in:
```text
spec.template.spec.containers[0].image
spec.template.spec.containers[1].image
```
This clashes with schema definitions, which require explicitly listed fields during entity definitions.

### Approaches
To address arrays, we offer two approaches:
1. Embed sections of the document into a field.
2. Create a new synthetic entity that models the information contained in the nested document, e.g., `DEPLOYMENT_CONTAINER`.

### Synthetic Entities
Synthetic entities exist only within a `schema` and have no counterpart in the underlying systems. 
Their purpose is to simplify dealing with arrays in documents.

### Directives
Directives are options added to fields and entities that guide their behavior during operations (Select, Insert, and Update). 
These are passed as `OPTIONS`, which are key-value pairs. Below is a list of synthetic-related directives:

Please see [this diagram](../diagrams/synthetic_directives.svg)

For more information about options and directives, please see [official documentation.](https://docs.kubling.com/Engine/DDL#options).

## `SCRIPT_DOCUMENT_JS` Data Source Type

One key feature to explore is Kubling's ability to abstract the complexity of document handling, particularly for JSON and YAML.

The `SCRIPT_DOCUMENT_JS` data source type signals to the engine that pre-processing is required for queries involving 
synthetic entities. The engine performs **group** and **ungroup** operations internally:

1. **Group**: The engine walks through the synthetic entity lineage to the first non-synthetic entity and calls the `resultset` JavaScript delegate.
2. **Ungroup**: It returns to the lineage and applies ungrouping based on the `synthetic_path`.

For the `resultset` script, your JavaScript operates as in the `SCRIPT_JS` delegation. Synthetic entities can have other synthetic entities as parents, creating a lineage.

### Operations: INSERT, UPDATE, DELETE

Operations (`INSERT`, `UPDATE`, `DELETE`) behave differently with synthetic entities, as described below.

#### INSERT

Adds a new element in the parent `synthetic_path` array.

| Member/Func | Type               | Description                        |
|-------------|--------------------|------------------------------------|
| table       | String             | Parent non-synthetic table name    |
| fieldValues | List<SetOperation> | Field/value pairs in the operation |
| jsonList    | List<String>       | JSON documents to insert           |
| yamlList    | List<String>       | YAML documents to insert           |

#### UPDATE

Replaces values in an existing node.

| Member/Func      | Type                 | Description                                                             |
|------------------|----------------------|-------------------------------------------------------------------------|
| table            | String               | Parent non-synthetic table name                                         |
| updates          | List<SetOperation>   | Field/value pairs in the operation                                      |
| queryFilter      | QueryFilter          | Filter, sort, and pagination information                                |
| jsonList         | List<String>         | JSON documents with updates                                             |
| yamlList         | List<String>         | YAML documents with updates                                             |
| originalJsonList | List<String>         | Original document in JSON format before changes                         |
| differences      | JsonDifferenceResult | Delta between the original and updated documents for easier processing. |

#### DELETE

Removes a node from the document.

| Member/Func | Type         | Description                       |
|-------------|--------------|-----------------------------------|
| table       | String       | Parent non-synthetic table name   |
| queryFilter | QueryFilter  | Filter, sort, and pagination info |
| jsonList    | List<String> | JSON documents for deletion       |


## JavaScript Side

For synthetic entities, scripts receive full documents (as returned by the `resultset` script). 
Operations like `INSERT`, `UPDATE`, and `DELETE` use these full documents for processing.

See [sample code](modules/doc/action) for examples of how this works.

## How to test it

### 1. Generate bundle files
Execute [the gen-bundle script](gen-bundles.sh) to generate the zip files.

### 2. app-config
Point to the file generated in the first step, called `documents-descriptor-bundle.zip`.
Here you can opt for specifying the URI or keeping the variable `DESCRIPTOR_BUNDLE` which must be passed to the container.

### 3. Kubernetes Server Mock
Clone [this project](https://github.com/kubling-community/dbvirt-mock-upstream.git).<br/>
Build using `./mvnw clean package` and run `java -jar target/dbvirt-mock-upstream-24.12.jar`

### 4. Run container
This sample works well with our Community Edition, just replace the environment variables and run:

```
docker run --rm \ 
    -e DESCRIPTOR_BUNDLE=[/path/to/documents-descriptor-bundle.zip] \
    -e MODULE_BUNDLE=[/path/to/documents-module-bundle.zip] \
    -e APP_CONFIG=[/path/to/app-config.yaml] \
    -e PROPS_FILE=[/path/to/env.properties] \
    -p 35432:35432 -p 35482:35482 -p 8282:8282 \
    -v [/path/to/dbvirt-samples]:[mount/path] \
    kubling/kubling:latest
```

Or, assuming that you cloned the repo in `~/dbvirt-samples`, just run:
```
docker run --rm \
    -e DESCRIPTOR_BUNDLE=/dbvirt-samples/documents/documents-descriptor-bundle.zip \
    -e MODULE_BUNDLE=/dbvirt-samples/documents/modules/documents-module-bundle.zip \
    -e APP_CONFIG=/dbvirt-samples/documents/app-config.yaml \
    -e PROPS_FILE=/dbvirt-samples/documents/env.properties \
    -p 35432:35432 -p 35482:35482 -p 8282:8282 \
    -v ~/dbvirt-samples:/dbvirt-samples \
    kubling/kubling:latest
```

### 5. Queries
Once the container is running, run `psql -h localhost -p 35432 -U sa -d application` in a terminal. Type any password,
we are not authenticating users in the example.
Some queries you can start with:
* `SELECT * FROM k8s.DEPLOYMENTS WHERE metadata__namespace = '08abb0fc-f7af-4fe8-98d4-e76729567dc8';`<br/><br/>
* `SELECT * FROM k8s.DEPLOYMENT_CONTAINER WHERE metadata__namespace = '08abb0fc-f7af-4fe8-98d4-e76729567dc8';`<br/><br/>
* `SELECT * FROM k8s.DEPLOYMENT_CONTAINER WHERE metadata__namespace = '08abb0fc-f7af-4fe8-98d4-e76729567dc8' and metadata__name = 'nginx';`<br/><br/>
* `SELECT * FROM k8s.DEPLOYMENT_CONTAINER_VOLS WHERE metadata__namespace = '08abb0fc-f7af-4fe8-98d4-e76729567dc8';`<br/><br/>
* `SELECT * FROM k8s.DEPLOYMENT_CONTAINER_VOLS WHERE metadata__namespace = '08abb0fc-f7af-4fe8-98d4-e76729567dc8' and containerName = '1-nginx';`<br/><br/>
* `INSERT INTO k8s.DEPLOYMENT_CONTAINER
  (metadata__name, metadata__namespace, image, name)
  VALUES('nginx', '08abb0fc-f7af-4fe8-98d4-e76729567dc8', 'kubling.artifactory.internal/kubling-attached-nfs-server:23.5', 'nfs-server');`<br/><br/>
* `UPDATE k8s.DEPLOYMENT_CONTAINER
  SET image='kubling.artifactory.internal/kubling-attached-nfs-server:23.7'
  WHERE metadata__namespace = '08abb0fc-f7af-4fe8-98d4-e76729567dc8' and metadata__name = 'nginx';`<br/><br/>
* `UPDATE k8s.DEPLOYMENT_CONTAINER
  SET image='kubling.artifactory.internal/kubling-attached-nfs-server:23.7'
  WHERE metadata__namespace = '08abb0fc-f7af-4fe8-98d4-e76729567dc8' and metadata__name = 'nginx' and name = '2-nginx';`<br/><br/>
* `INSERT INTO k8s.DEPLOYMENT_CONTAINER_VOLS
  (metadata__name, metadata__namespace, containerName, mountPath, name, readOnly)
  VALUES('nginx', '08abb0fc-f7af-4fe8-98d4-e76729567dc8', '1-nginx', '/my/mnt', 'conf1-m0zhgq3', false);`<br/><br/>
* `UPDATE k8s.DEPLOYMENT_CONTAINER_VOLS SET mountPath = '/my/mnt2'
  WHERE metadata__namespace = '08abb0fc-f7af-4fe8-98d4-e76729567dc8' and metadata__name = 'nginx';`<br/><br/>
* `UPDATE k8s.DEPLOYMENT_CONTAINER_VOLS SET mountPath = '/my/mnt2'
  WHERE metadata__namespace = '08abb0fc-f7af-4fe8-98d4-e76729567dc8' and metadata__name = 'nginx' and (containerName = '1-nginx' or containerName = '2-nginx');`<br/><br/>
* `UPDATE k8s.DEPLOYMENT_CONTAINER_VOLS SET mountPath = '/my/mnt2'
  WHERE metadata__namespace = '08abb0fc-f7af-4fe8-98d4-e76729567dc8' and metadata__name = 'nginx' and containerName
  in (SELECT containerName FROM k8s.DEPLOYMENT_CONTAINER_VOLS WHERE metadata__namespace = '08abb0fc-f7af-4fe8-98d4-e76729567dc8');`<br/><br/>
