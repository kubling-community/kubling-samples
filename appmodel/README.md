# App Model Sample

> [!WARNING]
> Legacy reference: this sample is not validated with Kubling 26.4. It combines retired built-in adapters, external infrastructure, old image tags, and superseded commands. Use its functions and endpoint definitions as source material, not as a runnable deployment guide. Start with the [supported Quickstart](../quickstart/README.md).

Goal
: Explore a real example, using a hypothetical scenario in which a company, that has hundred of applications, 
wants to generate an application model and allow users and systems interact with it

Difficulty
: High

## Template functions
In this sample we introduce the "custom template function" feature that gives users the possibility to define
custom functions that can be invoked when evaluating templates.
Functions are bundled in a separate module file, for more info please see [the bundle info](modules/functions/bundle-function-info.yaml)

## Using PostgreSQL as DB for JOIN info.
In case you don't want to lose data when stopping the container, create a PostgreSQL container using the following command:
```
  docker run -d --name some-postgres \
    -e POSTGRES_PASSWORD=[PASSWORD] \
    -e PGDATA=/var/lib/postgresql/data/pgdata \
    -v [LOCAL PATH]:/var/lib/postgresql/data \
    -p 5432:5432 \
    postgres
```
Inject the required information as environment variables (`PG_X`) using in [properties file](app.properties)

Then connect to the postgres instance and execute:
```
  create table APPLICATION (id varchar(40) not null, name varchar(255) unique, primary key (id));
  create table COMPONENT (id varchar(40) not null, name varchar(255), application_id varchar(40), primary key (id), constraint idx_component unique (id, name));
  
  create table COMPONENT_CODE_REPO_JOIN (component_id varchar(40) not null, code_repo_org varchar(255) not null, code_repo_name varchar(255) not null);
  create table COMPONENT_DEPLOYMENT_JOIN (component_id varchar(40) not null, environment varchar(5), deployment_identifier varchar(512) not null);
  
  create index idx_application on APPLICATION (id);
  alter table if exists COMPONENT add constraint FK7p951ujm4jv7l8i1jc5he7mcf foreign key (application_id) references APPLICATION;
```

Tables will be created in database `postgres`, schema `public`, which for this demo should not be a problem.

## How to test it

### Run integration tests
Kubling modules, as any other JavaScript project, must be tested using the well-known standard: Unit tests, Integration tests and Functional tests.

Unit tests are performed locally using 100% JavaScript while functional tests can be performed using containers, that is,
within a build-chain that generates all modules and runs a local full-server container (you can use the free CE), so you only run a client
to make all the necessary operations and verify results.
Take into account that `app-config` and `properties` must be pointing to mock servers or upstream systems you use for testing.

However, integration tests are challenging since the only thing we need out of them is knowing whether a query executes
or not, by analyzing results in the form of rows and columns and/or update counts when INSERTING, UPDATING or DELETING, without having
to initialize the whole server in a container, that is, in a lighter way, since we don't need, for example, `initializer`s, `RBAC` and the `scheduler`.

That is why `kdv` offers the `test` command which has a subcommand `integration` that picks up a manifest file and
executes a tiny workflow to prepare the context and call your integration test JavaScript files.

`integration` subcommand has also the ability to start one or more mock servers, using same approach [followed here](https://github.com/kubling-community/dbvirt-mock-upstream), in fact
it starts embedded servers.

Please see the [test plan file](integration-test-plan.yaml) for more information, and also have a look at the [integration
tests script](test/script/github_tests.js).

Assuming that you cloned the repo in `~/dbvirt-samples`, just run:<br>
```docker run --rm -v $HOME/dbvirt-samples/:/dbvirt-samples kubling/kubling-cli:latest test integration /dbvirt-samples/appmodel/integration-test-plan.yaml```

### Run the server as in the rest of the samples

#### 1. Generate bundle files
Execute [the gen-bundle script](gen-bundles.sh) to generate the zip files.

#### 2. Follow the standard procedure explained in the rest of the examples

#### 3. Run container
This sample works well with our Community Edition, just replace the environment variables and run:

```
docker run --rm \ 
    -e DESCRIPTOR_BUNDLE=[/path/to/appmodel-descriptor-bundle.zip] \
    -e APP_CONFIG=[/path/to/app-config.yaml] \
    -e MODULE_BUNDLE=[/path/to/appmodel-module-bundle.zip] \
    -e TEMPLATE_FUNCTIONS_BUNDLE=[/path/to/appmodel-functions-bundle.zip] \
    -e PROPS_FILE=[/path/to/app.properties] \
    -p 35432:35432 -p 35482:35482 -p 8282:8282 \
    -v [/path/to/dbvirt-samples]:[mount/path] \
    kubling/kubling:latest
```

Or, assuming that you cloned the repo in `~/dbvirt-samples`, just run:
```
docker run --rm \
    -e DESCRIPTOR_BUNDLE=/dbvirt-samples/appmodel/appmodel-descriptor-bundle.zip \
    -e APP_CONFIG=/dbvirt-samples/appmodel/app-config.yaml \
    -e MODULE_BUNDLE=/dbvirt-samples/appmodel/modules/appmodel-module-bundle.zip \
    -e TEMPLATE_FUNCTIONS_BUNDLE=/dbvirt-samples/appmodel/modules/appmodel-functions-bundle.zip \
    -e PROPS_FILE=/dbvirt-samples/appmodel/app.properties \
    -p 35432:35432 -p 35482:35482 -p 8282:8282 \
    -v ~/dbvirt-samples:/dbvirt-samples \
    kubling/kubling:latest
```

#### 4. Endpoints
Once the container is running, use the following commands to start testing:

##### Create a new app:
* ```
  curl --location 'http://localhost:8282/api/v1/actions/run/new_app' \
    --header 'Content-Type: application/json' \
    --data '{ "app_name": "my-new-app" }'
  ```
##### Get App Info:
* ```
  curl --location 'http://localhost:8282/api/v1/query/perform/get_apps_full' \
    --header 'Content-Type: application/json' \
    --data '{ "app_name": "my-new-app" }'
  ```
  
##### Add a component to the app a new app:
* ```
    curl --location 'http://localhost:8282/api/v1/actions/run/add_component' \
      --header 'Content-Type: application/json' \
      --data '{
          "app_id": "[REPLACE BY my-new-app ID]",
          "component_name": "app-backend",
          "component_description": "This is the backend"
      }'
  ```
**_Tip:_** Use the info retrieved when calling `get_apps_full` to get my-new-app ID.

If you are using the mock server, you'll receive an error indicating that 'Code Repository app-backend already exists.'.
That is because we first check that actually the repository does not exist already in GitHub.

To fix it, comment [the following section](https://github.com/kubling-community/dbvirt-mock-upstream/blob/master/src/main/resources/github_server_expect.yaml#L46), regenerate the server and try again.
Once the operation done, uncomment it, so we are able to fetch info.

##### Deploy a component to Kubernetes:
* ```
  curl --location 'http://localhost:8282/api/v1/actions/run/deploy_component' \
  --header 'Content-Type: application/json' \
  --data '{
      "component_id": [REPLACE BY component ID],
      "env": "env",
      "containers": [
        {
          "name": "my-container",
          "image": "nginx",
          "cpuRequest": "250m",
          "memRequest": "250M",
          "env": [
            {
              "name": "env1",
              "value": "val1"
            }
          ],
          "ports": [
            {
              "portNumber": 80
            }
          ]
        }
      ]
  }'
  ```
**_Tip:_** Call `get_apps_full` again and copy one of the associated component ID.  

The strategy followed in this example, is creating a namespace named after the `component_id`.
Therefore, you will need to adapt the mock server based on the namespace name. Go to [this file](https://github.com/kubling-community/dbvirt-mock-upstream/blob/master/src/main/resources/kubernetes_server_1_expect.yaml#L58) and replace the
field selector by the component ID.

##### Get last deploy transition (status):
* ```
  curl --location 'http://localhost:8282/api/v1/query/perform/get_app_component_deploy_last_transition' \
  --header 'Content-Type: application/json' \
  --data '{
      "component_id": [REPLACE BY component ID],
      "env": "dev"
  }'
  ```

#### 5. Queries
At this point, we hope you're already familiar with queries, so we recommend trying queries with different complexity,
as you were operating this company's IT/Cloud Infra. Enjoy!
