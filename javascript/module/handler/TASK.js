import { taskFixtures } from "../data/tasks";

export default {
    select(queryFilter, resultSet) {
        logger.debug("TASK query received:\n" + queryFilter.yaml);
        resultSet.dataFormat("JSON");

        taskFixtures().forEach(function (task) {
            resultSet.addRow(JSON.stringify(task));
        });
    },

    insert(insertOperation, affectedRows) {
        insertOperation.jsonList.forEach(function (document) {
            const task = JSON.parse(document);

            if (!task.id || !task.title) {
                throw new Error("TASK inserts require id and title");
            }

            logger.debug("TASK insert received: " + JSON.stringify(task));
            affectedRows.increment();
        });
    }
};
