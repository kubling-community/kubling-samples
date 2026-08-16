CREATE FOREIGN TABLE PROJECT
(
    project_id string NOT NULL,
    name string NOT NULL,
    members json OPTIONS(parser_format 'asJsonPretty'),

    identifier string OPTIONS(val_pk 'project_id'),
    PRIMARY KEY(identifier),
    UNIQUE(project_id)
)
OPTIONS(
    updatable true,
    supports_idempotency false,
    ANNOTATION 'Physical project documents containing a nested members array'
);

CREATE FOREIGN TABLE PROJECT_MEMBER
(
    project_id string NOT NULL OPTIONS(synthetic_type 'parent'),

    member_id string NOT NULL,
    display_name string NOT NULL,
    role string NOT NULL,

    identifier string OPTIONS(val_pk 'project_id+member_id'),
    PRIMARY KEY(identifier),
    UNIQUE(project_id, member_id)
)
OPTIONS(
    updatable true,
    synthetic_parent 'synthetic.PROJECT',
    synthetic_path 'members',
    synthetic_allow_bulk_insert false,
    ANNOTATION 'Synthetic relational projection of the PROJECT members array'
);
