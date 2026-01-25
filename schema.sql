--
-- PostgreSQL database dump
--

-- Dumped from database version 16.11
-- Dumped by pg_dump version 17.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: postgresadmin
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO postgresadmin;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: postgresadmin
--

COMMENT ON SCHEMA public IS '';


--
-- Name: merge_orders_stage(); Type: PROCEDURE; Schema: public; Owner: postgresadmin
--

CREATE PROCEDURE public.merge_orders_stage()
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_inserted INT;
  v_updated INT;
BEGIN
  -- ----------------------------------------
  -- Step 0: Remove duplicates from stage (keep latest by loaded_at)
  -- This handles if preactions truncate didn't work
  -- ----------------------------------------
 
 DELETE FROM orders_stage a
  USING orders_stage b
  WHERE a.caseid = b.caseid
    AND a.productid = b.productid
    AND a.submissiondate = b.submissiondate
    AND a.casedate = b.casedate
    AND a.patientname = b.patientname
    AND a.customerid = b.customerid
    AND a.loaded_at < b.loaded_at;

  -- ----------------------------------------
  -- Step 1: Capture old values for records that will be updated
  -- (needed for history logging after all transformations)
  -- ----------------------------------------
  CREATE TEMP TABLE _update_old_values AS
  SELECT c.*
  FROM orders_current c
  JOIN orders_stage s
    ON c.caseid = s.caseid
    AND c.productid = s.productid
    AND c.submissiondate = s.submissiondate
    AND c.casedate = s.casedate
    AND c.patientname = s.patientname
    AND c.customerid = s.customerid
  WHERE c.row_hash IS DISTINCT FROM s.row_hash;

  -- ----------------------------------------
  -- Step 2: Capture which records are new inserts
  -- (needed for history logging after all transformations)
  -- ----------------------------------------
  CREATE TEMP TABLE _new_inserts AS
  SELECT DISTINCT s.caseid, s.productid, s.submissiondate, s.casedate, s.patientname, s.customerid, s.source_file_key
  FROM orders_stage s
  LEFT JOIN orders_current c
    ON s.caseid = c.caseid
    AND s.productid = c.productid
    AND s.submissiondate = c.submissiondate
    AND s.casedate = c.casedate
    AND s.patientname = c.patientname
    AND s.customerid = c.customerid
  WHERE c.caseid IS NULL;


  -- ----------------------------------------
  -- Step 3: Insert new records into current
  -- ----------------------------------------
  INSERT INTO orders_current (
    caseid, productid, submissiondate, shippingdate, casedate,
    productdescription, quantity, productprice, patientname,
    customerid, customername, address, phonenumber, casestatus,
    holdreason, estimatecompletedate, requestedreturndate,
    trackingnumber, estimatedshipdate, holddate, deliverystatus,
    notes, onhold, shade, mold, doctorpreferences,
    productpreferences, comments, casetotal,
    lab_id, row_hash, last_updated_at
  )
  SELECT --DISTINCT ON (s.caseid, s.productid)
    s.caseid, s.productid, s.submissiondate, s.shippingdate, s.casedate,
    s.productdescription, s.quantity, s.productprice, s.patientname,
    s.customerid, s.customername, s.address, s.phonenumber, s.casestatus,
    s.holdreason, s.estimatecompletedate, s.requestedreturndate,
    s.trackingnumber, s.estimatedshipdate, s.holddate, s.deliverystatus,
    s.notes, s.onhold, s.shade, s.mold, s.doctorpreferences,
    s.productpreferences, s.comments, s.casetotal,
    s.lab_id, s.row_hash, now()
  FROM orders_stage s
  LEFT JOIN orders_current c
    ON s.caseid = c.caseid
    AND s.productid = c.productid
    AND s.submissiondate = c.submissiondate
    AND s.casedate = c.casedate
    AND s.patientname = c.patientname
    AND s.customerid = c.customerid
  WHERE c.caseid IS NULL;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  -- ----------------------------------------
  -- Step 4: Update existing records in current
  -- ----------------------------------------
  UPDATE orders_current AS c
  SET
    submissiondate = s.submissiondate,
    shippingdate = s.shippingdate,
    casedate = s.casedate,
    productdescription = s.productdescription,
    quantity = s.quantity,
    productprice = s.productprice,
    patientname = s.patientname,
    customerid = s.customerid,
    customername = s.customername,
    address = s.address,
    phonenumber = s.phonenumber,
    casestatus = s.casestatus,
    holdreason = s.holdreason,
    estimatecompletedate = s.estimatecompletedate,
    requestedreturndate = s.requestedreturndate,
    trackingnumber = s.trackingnumber,
    estimatedshipdate = s.estimatedshipdate,
    holddate = s.holddate,
    deliverystatus = s.deliverystatus,
    notes = s.notes,
    onhold = s.onhold,
    shade = s.shade,
    mold = s.mold,
    doctorpreferences = s.doctorpreferences,
    productpreferences = s.productpreferences,
    comments = s.comments,
    casetotal = s.casetotal,
    lab_id = s.lab_id,
    row_hash = s.row_hash,
    last_updated_at = now()
  FROM orders_stage s
  WHERE c.caseid = s.caseid
    AND c.productid = s.productid
    AND c.submissiondate = s.submissiondate
    AND c.casedate = s.casedate
    AND c.patientname = s.patientname
    AND c.customerid = s.customerid
    AND c.row_hash IS DISTINCT FROM s.row_hash;

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  -- ----------------------------------------
  -- Step 5: Insert new patients into patients table
  -- ----------------------------------------
  INSERT INTO patients (patient_name)
  SELECT DISTINCT patientname
  FROM orders_current
  WHERE patientname IS NOT NULL
    AND patientname <> ''
    AND patientname NOT IN (SELECT patient_name FROM patients);

  -- ----------------------------------------
  -- Step 6: Update incisive_product_id from lab_product_mapping
  -- ----------------------------------------
  UPDATE orders_current c
  SET incisive_product_id = lpm.incisive_product_id
  FROM lab_product_mapping lpm
  WHERE c.lab_id = lpm.lab_id
    AND c.productid = lpm.lab_product_id
    AND c.incisive_product_id IS NULL;

  -- ----------------------------------------
  -- Step 7: Update incisive_practice_id from lab_practice_mapping
  -- ----------------------------------------
  UPDATE orders_current c
  SET incisive_practice_id = lprm.practice_id
  FROM lab_practice_mapping lprm
  WHERE c.lab_id = lprm.lab_id
    AND c.customerid = lprm.lab_practice_id
    AND c.incisive_practice_id IS NULL;

  -- ----------------------------------------
  -- Step 8: Log new records to history (INSERT)
  -- Now includes incisive_product_id and incisive_practice_id
  -- ----------------------------------------
  INSERT INTO orders_history (caseid, productid, lab_id, change_type, new_row, source_file_key)
  SELECT
    c.caseid,
    c.productid,
    c.lab_id,
    'INSERT',
    to_jsonb(c),
    ni.source_file_key
  FROM orders_current c
  JOIN _new_inserts ni
    ON c.caseid = ni.caseid
    AND c.productid = ni.productid
    AND c.submissiondate = ni.submissiondate
    AND c.casedate = ni.casedate
    AND c.patientname = ni.patientname
    AND c.customerid = ni.customerid;

  -- ----------------------------------------
  -- Step 9: Log updates to history (UPDATE)
  -- Now includes incisive_product_id and incisive_practice_id
  -- ----------------------------------------
  INSERT INTO orders_history (caseid, productid, lab_id, change_type, changed_columns, old_row, new_row, source_file_key)
  SELECT
    c.caseid,
    c.productid,
    c.lab_id,
    'UPDATE',
    ARRAY(
      SELECT key
      FROM jsonb_each(to_jsonb(o)) AS old_kv(key, value)
      WHERE to_jsonb(o)->key IS DISTINCT FROM to_jsonb(c)->key
        AND key NOT IN ('last_updated_at', 'row_hash')
    ),
    to_jsonb(o),
    to_jsonb(c),
    s.source_file_key
  FROM orders_current c
  JOIN _update_old_values o
    ON c.caseid = o.caseid
    AND c.productid = o.productid
    AND c.submissiondate = o.submissiondate
    AND c.casedate = o.casedate
    AND c.patientname = o.patientname
    AND c.customerid = o.customerid
  JOIN orders_stage s
    ON c.caseid = s.caseid
    AND c.productid = s.productid
    AND c.submissiondate = s.submissiondate
    AND c.casedate = s.casedate
    AND c.patientname = s.patientname
    AND c.customerid = s.customerid;

  -- ----------------------------------------
  -- Step 10: Clean up temp tables
  -- ----------------------------------------
  DROP TABLE IF EXISTS _update_old_values;
  DROP TABLE IF EXISTS _new_inserts;

  -- Log results (optional: insert into a run log table)
  RAISE NOTICE 'Merge complete: % inserted, % updated', v_inserted, v_updated;

END;
$$;


ALTER PROCEDURE public.merge_orders_stage() OWNER TO postgresadmin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: dental_groups; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.dental_groups (
    dental_group_id bigint NOT NULL,
    name text NOT NULL,
    dental_group_sfdc_id text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    address text,
    address_2 text,
    city text,
    state text,
    zip text,
    account_type text,
    centralized_billing boolean,
    sales_channel text,
    sales_rep text
);


ALTER TABLE public.dental_groups OWNER TO postgresadmin;

--
-- Name: dental_practices; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.dental_practices (
    practice_id bigint NOT NULL,
    dental_group_id bigint,
    dental_group_name text,
    address text,
    address_2 text,
    city text,
    state text,
    zip text,
    phone text,
    clinical_email text,
    billing_email text,
    incisive_email text,
    preferred_contact_method text,
    fee_schedule text,
    status text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.dental_practices OWNER TO postgresadmin;

--
-- Name: fee_schedules; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.fee_schedules (
    schedule_name text NOT NULL
);


ALTER TABLE public.fee_schedules OWNER TO postgresadmin;

--
-- Name: incisive_product_catalog; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.incisive_product_catalog (
    incisive_id integer NOT NULL,
    incisive_name text NOT NULL,
    category text,
    sub_category text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.incisive_product_catalog OWNER TO postgresadmin;

--
-- Name: lab_practice_mapping; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.lab_practice_mapping (
    lab_practice_mapping_id bigint NOT NULL,
    lab_id bigint NOT NULL,
    practice_id bigint NOT NULL,
    lab_practice_id text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.lab_practice_mapping OWNER TO postgresadmin;

--
-- Name: lab_practice_mapping_lab_practice_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: postgresadmin
--

CREATE SEQUENCE public.lab_practice_mapping_lab_practice_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.lab_practice_mapping_lab_practice_mapping_id_seq OWNER TO postgresadmin;

--
-- Name: lab_practice_mapping_lab_practice_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgresadmin
--

ALTER SEQUENCE public.lab_practice_mapping_lab_practice_mapping_id_seq OWNED BY public.lab_practice_mapping.lab_practice_mapping_id;


--
-- Name: lab_product_mapping; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.lab_product_mapping (
    lab_product_mapping_id bigint NOT NULL,
    lab_id bigint NOT NULL,
    lab_product_id text,
    lab_product_name text,
    incisive_product_id integer,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.lab_product_mapping OWNER TO postgresadmin;

--
-- Name: lab_product_mapping_lab_product_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: postgresadmin
--

CREATE SEQUENCE public.lab_product_mapping_lab_product_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.lab_product_mapping_lab_product_mapping_id_seq OWNER TO postgresadmin;

--
-- Name: lab_product_mapping_lab_product_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgresadmin
--

ALTER SEQUENCE public.lab_product_mapping_lab_product_mapping_id_seq OWNED BY public.lab_product_mapping.lab_product_mapping_id;


--
-- Name: labs; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.labs (
    lab_id bigint NOT NULL,
    lab_name text NOT NULL,
    lab_sfdc_id text,
    partner_model text,
    is_active boolean DEFAULT true,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.labs OWNER TO postgresadmin;

--
-- Name: labs_lab_id_seq; Type: SEQUENCE; Schema: public; Owner: postgresadmin
--

CREATE SEQUENCE public.labs_lab_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.labs_lab_id_seq OWNER TO postgresadmin;

--
-- Name: labs_lab_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgresadmin
--

ALTER SEQUENCE public.labs_lab_id_seq OWNED BY public.labs.lab_id;


--
-- Name: orders_current; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.orders_current (
    caseid bigint NOT NULL,
    productid text NOT NULL,
    submissiondate text,
    shippingdate text,
    casedate text,
    productdescription text,
    quantity bigint,
    productprice text,
    patientname text,
    customerid text,
    customername text,
    address text,
    phonenumber text,
    casestatus text,
    holdreason text,
    estimatecompletedate text,
    requestedreturndate text,
    trackingnumber text,
    estimatedshipdate text,
    holddate text,
    deliverystatus text,
    notes text,
    onhold text,
    shade text,
    mold text,
    doctorpreferences text,
    productpreferences text,
    comments text,
    casetotal text,
    lab_id bigint,
    incisive_product_id integer,
    incisive_practice_id bigint,
    row_hash text,
    last_updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.orders_current OWNER TO postgresadmin;

--
-- Name: product_lab_markup; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.product_lab_markup (
    lab_id bigint NOT NULL,
    lab_product_id text NOT NULL,
    incisive_product_id integer,
    cost double precision,
    standard_price double precision,
    nf_price double precision,
    commitment_eligible boolean
);


ALTER TABLE public.product_lab_markup OWNER TO postgresadmin;

--
-- Name: product_lab_rev_share; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.product_lab_rev_share (
    lab_id bigint NOT NULL,
    lab_product_id text NOT NULL,
    incisive_product_id integer,
    fee_schedule_name text NOT NULL,
    revenue_share double precision,
    commitment_eligible boolean
);


ALTER TABLE public.product_lab_rev_share OWNER TO postgresadmin;

--
-- Name: orders_analytics; Type: VIEW; Schema: public; Owner: postgresadmin
--

CREATE VIEW public.orders_analytics AS
 SELECT oc.caseid,
    oc.productid,
    oc.submissiondate,
    oc.shippingdate,
    oc.casedate,
    oc.productdescription,
    oc.quantity,
    oc.productprice,
    (NULLIF(oc.productprice, ''::text))::numeric AS productprice_numeric,
    oc.patientname,
    oc.customerid,
    oc.customername,
    oc.address,
    oc.phonenumber,
    oc.casestatus,
    oc.holdreason,
    oc.estimatecompletedate,
    oc.requestedreturndate,
    oc.trackingnumber,
    oc.estimatedshipdate,
    oc.holddate,
    oc.deliverystatus,
    oc.notes,
    oc.onhold,
    oc.shade,
    oc.mold,
    oc.doctorpreferences,
    oc.productpreferences,
    oc.comments,
    oc.casetotal,
    (NULLIF(oc.casetotal, ''::text))::numeric AS casetotal_numeric,
    oc.last_updated_at,
        CASE
            WHEN ((lower(oc.onhold) = 'true'::text) OR (oc.casestatus ~~* '%hold%'::text)) THEN true
            ELSE false
        END AS is_on_hold,
        CASE
            WHEN ((oc.shippingdate IS NOT NULL) AND (oc.shippingdate <> ''::text)) THEN true
            ELSE false
        END AS is_shipped,
        CASE
            WHEN (oc.casestatus = 'Delivered'::text) THEN true
            ELSE false
        END AS is_delivered,
        CASE
            WHEN (oc.casestatus = ANY (ARRAY['Cancelled'::text, 'Canceled'::text])) THEN true
            ELSE false
        END AS is_cancelled,
    oc.lab_id,
    l.lab_name,
    oc.incisive_product_id,
    ipc.incisive_name AS product_name,
    ipc.category AS product_category,
    ipc.sub_category AS product_sub_category,
    oc.incisive_practice_id,
    dp.dental_group_name AS practice_name,
    dp.address AS practice_address,
    dp.address_2 AS practice_address_2,
    dp.city AS practice_city,
    dp.state AS practice_state,
    dp.zip AS practice_zip,
    dp.phone AS practice_phone,
    dp.clinical_email AS practice_clinical_email,
    dp.billing_email AS practice_billing_email,
    dp.incisive_email AS practice_incisive_email,
    dp.fee_schedule AS practice_fee_schedule,
    dp.status AS practice_status,
    dp.dental_group_id,
    dg.name AS dental_group_name,
    dg.address AS dental_group_address,
    dg.city AS dental_group_city,
    dg.state AS dental_group_state,
    dg.zip AS dental_group_zip,
    dg.account_type AS dental_group_account_type,
    dg.centralized_billing AS dental_group_centralized_billing,
    dg.sales_channel AS dental_group_sales_channel,
    dg.sales_rep AS dental_group_sales_rep,
    plm.cost AS product_cost,
    plm.standard_price AS product_price,
    ((oc.quantity)::double precision * plm.cost) AS tot_passthrough,
    ((oc.quantity)::double precision * plm.standard_price) AS incisive_gross_markup,
    (((oc.quantity)::double precision * plm.standard_price) - ((oc.quantity)::double precision * plm.cost)) AS incisive_net,
    plm.commitment_eligible AS commitment_eligible_markup,
    dp.fee_schedule,
    plrs.commitment_eligible AS qualifying,
    plrs.revenue_share,
    (plrs.revenue_share * ((NULLIF(oc.casetotal, ''::text))::numeric)::double precision) AS incisive_gross_revshare,
        CASE
            WHEN (oc.incisive_product_id IS NOT NULL) THEN true
            ELSE false
        END AS product_is_mapped,
        CASE
            WHEN (oc.incisive_practice_id IS NOT NULL) THEN true
            ELSE false
        END AS practice_is_mapped
   FROM ((((((public.orders_current oc
     LEFT JOIN public.labs l ON ((oc.lab_id = l.lab_id)))
     LEFT JOIN public.incisive_product_catalog ipc ON ((oc.incisive_product_id = ipc.incisive_id)))
     LEFT JOIN public.dental_practices dp ON ((oc.incisive_practice_id = dp.practice_id)))
     LEFT JOIN public.dental_groups dg ON ((dp.dental_group_id = dg.dental_group_id)))
     LEFT JOIN public.product_lab_markup plm ON (((oc.lab_id = plm.lab_id) AND (oc.productid = plm.lab_product_id))))
     LEFT JOIN public.product_lab_rev_share plrs ON (((oc.lab_id = plrs.lab_id) AND (oc.productid = plrs.lab_product_id) AND (dp.fee_schedule = plrs.fee_schedule_name))));


ALTER VIEW public.orders_analytics OWNER TO postgresadmin;

--
-- Name: orders_history; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.orders_history (
    history_id bigint NOT NULL,
    caseid bigint,
    productid text,
    lab_id bigint,
    change_type text,
    changed_columns text[],
    old_row jsonb,
    new_row jsonb,
    source_file_key text,
    changed_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.orders_history OWNER TO postgresadmin;

--
-- Name: orders_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgresadmin
--

CREATE SEQUENCE public.orders_history_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.orders_history_history_id_seq OWNER TO postgresadmin;

--
-- Name: orders_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgresadmin
--

ALTER SEQUENCE public.orders_history_history_id_seq OWNED BY public.orders_history.history_id;


--
-- Name: orders_stage; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.orders_stage (
    submissiondate text,
    shippingdate text,
    casedate text,
    caseid bigint,
    productid text,
    productdescription text,
    quantity bigint,
    productprice text,
    patientname text,
    customerid text,
    customername text,
    address text,
    phonenumber text,
    casestatus text,
    holdreason text,
    estimatecompletedate text,
    requestedreturndate text,
    trackingnumber text,
    estimatedshipdate text,
    holddate text,
    deliverystatus text,
    notes text,
    onhold text,
    shade text,
    mold text,
    doctorpreferences text,
    productpreferences text,
    comments text,
    casetotal text,
    lab_id bigint DEFAULT 2,
    source_file_key text,
    row_hash text,
    loaded_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.orders_stage OWNER TO postgresadmin;

--
-- Name: patients; Type: TABLE; Schema: public; Owner: postgresadmin
--

CREATE TABLE public.patients (
    patient_name text NOT NULL
);


ALTER TABLE public.patients OWNER TO postgresadmin;

--
-- Name: lab_practice_mapping lab_practice_mapping_id; Type: DEFAULT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.lab_practice_mapping ALTER COLUMN lab_practice_mapping_id SET DEFAULT nextval('public.lab_practice_mapping_lab_practice_mapping_id_seq'::regclass);


--
-- Name: lab_product_mapping lab_product_mapping_id; Type: DEFAULT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.lab_product_mapping ALTER COLUMN lab_product_mapping_id SET DEFAULT nextval('public.lab_product_mapping_lab_product_mapping_id_seq'::regclass);


--
-- Name: labs lab_id; Type: DEFAULT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.labs ALTER COLUMN lab_id SET DEFAULT nextval('public.labs_lab_id_seq'::regclass);


--
-- Name: orders_history history_id; Type: DEFAULT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.orders_history ALTER COLUMN history_id SET DEFAULT nextval('public.orders_history_history_id_seq'::regclass);


--
-- Name: dental_groups dental_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.dental_groups
    ADD CONSTRAINT dental_groups_pkey PRIMARY KEY (dental_group_id);


--
-- Name: dental_practices dental_practices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.dental_practices
    ADD CONSTRAINT dental_practices_pkey PRIMARY KEY (practice_id);


--
-- Name: fee_schedules fee_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.fee_schedules
    ADD CONSTRAINT fee_schedules_pkey PRIMARY KEY (schedule_name);


--
-- Name: incisive_product_catalog incisive_product_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.incisive_product_catalog
    ADD CONSTRAINT incisive_product_catalog_pkey PRIMARY KEY (incisive_id);


--
-- Name: lab_practice_mapping lab_practice_mapping_lab_id_lab_practice_id_key; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.lab_practice_mapping
    ADD CONSTRAINT lab_practice_mapping_lab_id_lab_practice_id_key UNIQUE (lab_id, lab_practice_id);


--
-- Name: lab_practice_mapping lab_practice_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.lab_practice_mapping
    ADD CONSTRAINT lab_practice_mapping_pkey PRIMARY KEY (lab_practice_mapping_id);


--
-- Name: lab_product_mapping lab_product_mapping_lab_id_product_id_key; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.lab_product_mapping
    ADD CONSTRAINT lab_product_mapping_lab_id_product_id_key UNIQUE (lab_id, lab_product_id);


--
-- Name: lab_product_mapping lab_product_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.lab_product_mapping
    ADD CONSTRAINT lab_product_mapping_pkey PRIMARY KEY (lab_product_mapping_id);


--
-- Name: labs labs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.labs
    ADD CONSTRAINT labs_pkey PRIMARY KEY (lab_id);


--
-- Name: orders_history orders_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.orders_history
    ADD CONSTRAINT orders_history_pkey PRIMARY KEY (history_id);


--
-- Name: patients patients_pkey; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_pkey PRIMARY KEY (patient_name);


--
-- Name: product_lab_markup product_lab_markup_pkey; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.product_lab_markup
    ADD CONSTRAINT product_lab_markup_pkey PRIMARY KEY (lab_id, lab_product_id);


--
-- Name: product_lab_rev_share product_lab_rev_share_pkey; Type: CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.product_lab_rev_share
    ADD CONSTRAINT product_lab_rev_share_pkey PRIMARY KEY (lab_id, lab_product_id, fee_schedule_name);


--
-- Name: idx_dental_groups_sfdc_id; Type: INDEX; Schema: public; Owner: postgresadmin
--

CREATE INDEX idx_dental_groups_sfdc_id ON public.dental_groups USING btree (dental_group_sfdc_id);


--
-- Name: idx_dental_practices_group_id; Type: INDEX; Schema: public; Owner: postgresadmin
--

CREATE INDEX idx_dental_practices_group_id ON public.dental_practices USING btree (dental_group_id);


--
-- Name: idx_lab_practice_mapping_lab_id; Type: INDEX; Schema: public; Owner: postgresadmin
--

CREATE INDEX idx_lab_practice_mapping_lab_id ON public.lab_practice_mapping USING btree (lab_id);


--
-- Name: idx_lab_practice_mapping_practice_id; Type: INDEX; Schema: public; Owner: postgresadmin
--

CREATE INDEX idx_lab_practice_mapping_practice_id ON public.lab_practice_mapping USING btree (practice_id);


--
-- Name: idx_lab_product_mapping_incisive_id; Type: INDEX; Schema: public; Owner: postgresadmin
--

CREATE INDEX idx_lab_product_mapping_incisive_id ON public.lab_product_mapping USING btree (incisive_product_id);


--
-- Name: idx_lab_product_mapping_lab_id; Type: INDEX; Schema: public; Owner: postgresadmin
--

CREATE INDEX idx_lab_product_mapping_lab_id ON public.lab_product_mapping USING btree (lab_id);


--
-- Name: idx_labs_sfdc_id; Type: INDEX; Schema: public; Owner: postgresadmin
--

CREATE INDEX idx_labs_sfdc_id ON public.labs USING btree (lab_sfdc_id);


--
-- Name: idx_orders_history_caseid_productid; Type: INDEX; Schema: public; Owner: postgresadmin
--

CREATE INDEX idx_orders_history_caseid_productid ON public.orders_history USING btree (caseid, productid);


--
-- Name: idx_product_catalog_category; Type: INDEX; Schema: public; Owner: postgresadmin
--

CREATE INDEX idx_product_catalog_category ON public.incisive_product_catalog USING btree (category);


--
-- Name: dental_practices dental_practices_dental_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.dental_practices
    ADD CONSTRAINT dental_practices_dental_group_id_fkey FOREIGN KEY (dental_group_id) REFERENCES public.dental_groups(dental_group_id);


--
-- Name: dental_practices fk_dental_practices_fee_schedule; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.dental_practices
    ADD CONSTRAINT fk_dental_practices_fee_schedule FOREIGN KEY (fee_schedule) REFERENCES public.fee_schedules(schedule_name);


--
-- Name: lab_practice_mapping lab_practice_mapping_lab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.lab_practice_mapping
    ADD CONSTRAINT lab_practice_mapping_lab_id_fkey FOREIGN KEY (lab_id) REFERENCES public.labs(lab_id);


--
-- Name: lab_practice_mapping lab_practice_mapping_practice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.lab_practice_mapping
    ADD CONSTRAINT lab_practice_mapping_practice_id_fkey FOREIGN KEY (practice_id) REFERENCES public.dental_practices(practice_id);


--
-- Name: lab_product_mapping lab_product_mapping_incisive_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.lab_product_mapping
    ADD CONSTRAINT lab_product_mapping_incisive_product_id_fkey FOREIGN KEY (incisive_product_id) REFERENCES public.incisive_product_catalog(incisive_id);


--
-- Name: lab_product_mapping lab_product_mapping_lab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.lab_product_mapping
    ADD CONSTRAINT lab_product_mapping_lab_id_fkey FOREIGN KEY (lab_id) REFERENCES public.labs(lab_id);


--
-- Name: orders_current orders_current_incisive_practice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.orders_current
    ADD CONSTRAINT orders_current_incisive_practice_id_fkey FOREIGN KEY (incisive_practice_id) REFERENCES public.dental_practices(practice_id);


--
-- Name: orders_current orders_current_incisive_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.orders_current
    ADD CONSTRAINT orders_current_incisive_product_id_fkey FOREIGN KEY (incisive_product_id) REFERENCES public.incisive_product_catalog(incisive_id);


--
-- Name: product_lab_markup product_lab_markup_incisive_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.product_lab_markup
    ADD CONSTRAINT product_lab_markup_incisive_product_id_fkey FOREIGN KEY (incisive_product_id) REFERENCES public.incisive_product_catalog(incisive_id);


--
-- Name: product_lab_markup product_lab_markup_lab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.product_lab_markup
    ADD CONSTRAINT product_lab_markup_lab_id_fkey FOREIGN KEY (lab_id) REFERENCES public.labs(lab_id);


--
-- Name: product_lab_rev_share product_lab_rev_share_fee_schedule_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.product_lab_rev_share
    ADD CONSTRAINT product_lab_rev_share_fee_schedule_name_fkey FOREIGN KEY (fee_schedule_name) REFERENCES public.fee_schedules(schedule_name);


--
-- Name: product_lab_rev_share product_lab_rev_share_incisive_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.product_lab_rev_share
    ADD CONSTRAINT product_lab_rev_share_incisive_product_id_fkey FOREIGN KEY (incisive_product_id) REFERENCES public.incisive_product_catalog(incisive_id);


--
-- Name: product_lab_rev_share product_lab_rev_share_lab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgresadmin
--

ALTER TABLE ONLY public.product_lab_rev_share
    ADD CONSTRAINT product_lab_rev_share_lab_id_fkey FOREIGN KEY (lab_id) REFERENCES public.labs(lab_id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgresadmin
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO incisive_dev_glue_user;


--
-- Name: PROCEDURE merge_orders_stage(); Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT ALL ON PROCEDURE public.merge_orders_stage() TO incisive_dev_glue_user;


--
-- Name: TABLE dental_groups; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.dental_groups TO incisive_dev_glue_user;


--
-- Name: TABLE dental_practices; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.dental_practices TO incisive_dev_glue_user;


--
-- Name: TABLE fee_schedules; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.fee_schedules TO incisive_dev_glue_user;


--
-- Name: TABLE incisive_product_catalog; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.incisive_product_catalog TO incisive_dev_glue_user;


--
-- Name: TABLE lab_practice_mapping; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.lab_practice_mapping TO incisive_dev_glue_user;


--
-- Name: SEQUENCE lab_practice_mapping_lab_practice_mapping_id_seq; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,USAGE ON SEQUENCE public.lab_practice_mapping_lab_practice_mapping_id_seq TO incisive_dev_glue_user;


--
-- Name: TABLE lab_product_mapping; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.lab_product_mapping TO incisive_dev_glue_user;


--
-- Name: SEQUENCE lab_product_mapping_lab_product_mapping_id_seq; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,USAGE ON SEQUENCE public.lab_product_mapping_lab_product_mapping_id_seq TO incisive_dev_glue_user;


--
-- Name: TABLE labs; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.labs TO incisive_dev_glue_user;


--
-- Name: SEQUENCE labs_lab_id_seq; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,USAGE ON SEQUENCE public.labs_lab_id_seq TO incisive_dev_glue_user;


--
-- Name: TABLE orders_current; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.orders_current TO incisive_dev_glue_user;


--
-- Name: TABLE product_lab_markup; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.product_lab_markup TO incisive_dev_glue_user;


--
-- Name: TABLE product_lab_rev_share; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.product_lab_rev_share TO incisive_dev_glue_user;


--
-- Name: TABLE orders_analytics; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.orders_analytics TO incisive_dev_glue_user;


--
-- Name: TABLE orders_history; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.orders_history TO incisive_dev_glue_user;


--
-- Name: SEQUENCE orders_history_history_id_seq; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,USAGE ON SEQUENCE public.orders_history_history_id_seq TO incisive_dev_glue_user;


--
-- Name: TABLE orders_stage; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.orders_stage TO incisive_dev_glue_user;


--
-- Name: TABLE patients; Type: ACL; Schema: public; Owner: postgresadmin
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.patients TO incisive_dev_glue_user;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgresadmin
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgresadmin IN SCHEMA public GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO incisive_dev_glue_user;


--
-- PostgreSQL database dump complete
--

