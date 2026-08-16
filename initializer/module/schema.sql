CREATE FOREIGN TABLE SCHEDULER_STATE
(
    id string NOT NULL,
    generation integer NOT NULL,
    token string NOT NULL,

    PRIMARY KEY(id)
)
OPTIONS(
    updatable false,
    ANNOTATION 'State established by initialization and advanced by a scheduled script'
);
