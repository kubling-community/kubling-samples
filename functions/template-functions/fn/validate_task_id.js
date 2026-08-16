function validate_task_id(args) {
    const taskId = String(args.taskId);

    if (!/^task-[A-Za-z0-9-]+$/.test(taskId)) {
        throw new Error("taskId must use the form task-<identifier>");
    }

    return taskId;
}
