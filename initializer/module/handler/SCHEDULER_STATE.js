export default {
    select(queryFilter, resultSet) {
        const state = JSON.parse(String(global.get("scheduler_state")));

        resultSet.dataFormat("JSON");
        resultSet.addRow(JSON.stringify(state));
    }
};
