CREATE FOREIGN TABLE TASK
(
    id string NOT NULL,
    title string NOT NULL,
    priority integer NOT NULL,
    completed boolean NOT NULL,

    PRIMARY KEY(id)
)
OPTIONS(
    updatable true,
    ANNOTATION 'Deterministic tasks served by the JavaScript sample module'
);
