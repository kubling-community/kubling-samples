const current = JSON.parse(String(global.get("scheduler_state")));
const generation = current.generation + 1;

global.put("scheduler_state", JSON.stringify({
    id: "scheduler",
    generation: generation,
    token: `token-${generation}`
}));
