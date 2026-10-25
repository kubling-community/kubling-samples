CREATE FOREIGN TABLE CUSTOMERS (
    ID integer NOT NULL,
    NAME string(100) NOT NULL,
    REGION string(32) NOT NULL,
    PRIMARY KEY (ID)
)
OPTIONS (UPDATABLE TRUE, ANNOTATION 'Performance comparison customers');

CREATE FOREIGN TABLE ORDERS (
    ID integer NOT NULL,
    CUSTOMER_ID integer NOT NULL,
    AMOUNT bigdecimal(12,2) NOT NULL,
    STATUS string(32) NOT NULL,
    PRIMARY KEY (ID)
)
OPTIONS (UPDATABLE TRUE, ANNOTATION 'Performance comparison orders');
