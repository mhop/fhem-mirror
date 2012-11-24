--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'SQL_ASCII';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

--
-- Name: fhem; Type: SCHEMA; Schema: -; Owner: fhem
--

CREATE SCHEMA fhem;


ALTER SCHEMA fhem OWNER TO fhem;

--
-- Name: SCHEMA fhem; Type: COMMENT; Schema: -; Owner: fhem
--

COMMENT ON SCHEMA fhem IS 'standard fhem schema';


SET search_path = fhem, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: current; Type: TABLE; Schema: fhem; Owner: fhem; Tablespace: 
--

CREATE TABLE current (
    "timestamp" timestamp without time zone,
    device character varying(64),
    type character varying(64),
    event character varying(512),
    reading character varying(64),
    value character varying(128),
    unit character varying(32)
);


ALTER TABLE fhem.current OWNER TO fhem;

--
-- Name: history; Type: TABLE; Schema: fhem; Owner: fhem; Tablespace: 
--

CREATE TABLE history (
    "timestamp" timestamp without time zone,
    device character varying(64),
    type character varying(64),
    event character varying(512),
    reading character varying(64),
    value character varying(128),
    unit character varying(32)
);


ALTER TABLE fhem.history OWNER TO fhem;

--
-- Name: reading; Type: INDEX; Schema: fhem; Owner: fhem; Tablespace: 
--

CREATE INDEX reading ON history USING btree (((((device)::text || '|'::text) || (reading)::text)), "timestamp");


--
-- PostgreSQL database dump complete
--

