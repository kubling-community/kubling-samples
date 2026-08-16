import { projectFixtures } from "../data/projects";

const stateKey = "synthetic_entities_projects";

function readProjects() {
    if (!global.containsKey(stateKey)) {
        global.put(stateKey, JSON.stringify(projectFixtures()));
    }

    return JSON.parse(String(global.get(stateKey)));
}

function writeProjects(projects) {
    global.put(stateKey, JSON.stringify(projects));
}

function persistProjects(documents, affectedRows) {
    let projects = readProjects();

    documents.forEach(function (document) {
        const updated = JSON.parse(String(document));

        projects = projects.map(function (project) {
            return project.project_id === updated.project_id ? updated : project;
        });
        affectedRows.increment();
    });

    writeProjects(projects);
}

function applyEqualityFilters(projects, queryFilter) {
    const filters = JSON.parse(String(queryFilter.json)).filters || [];

    return projects.filter(function (project) {
        return filters.every(function (filter) {
            if (!Object.prototype.hasOwnProperty.call(project, filter.field)) {
                return true;
            }

            const operation = typeof filter.operation === "string"
                ? filter.operation
                : filter.operation.value;

            return operation !== "EQUAL" || String(project[filter.field]) === String(filter.value);
        });
    });
}

export default {
    select(queryFilter, resultSet) {
        logger.debug("PROJECT query received:\n" + queryFilter.yaml);
        resultSet.dataFormat("JSON");

        applyEqualityFilters(readProjects(), queryFilter).forEach(function (project) {
            resultSet.addRow(JSON.stringify(project));
        });
    },

    update(updateOperation, affectedRows) {
        persistProjects(updateOperation.jsonList, affectedRows);
    }
};
