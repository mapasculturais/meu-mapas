--
-- PostgreSQL database dump
--

-- Dumped from database version 11.2 (Debian 11.2-1.pgdg90+1)
-- Dumped by pg_dump version 11.2 (Debian 11.2-1.pgdg90+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: tiger; Type: SCHEMA; Schema: -; Owner: mapas
--

CREATE SCHEMA tiger;


ALTER SCHEMA tiger OWNER TO mapas;

--
-- Name: tiger_data; Type: SCHEMA; Schema: -; Owner: mapas
--

CREATE SCHEMA tiger_data;


ALTER SCHEMA tiger_data OWNER TO mapas;

--
-- Name: topology; Type: SCHEMA; Schema: -; Owner: mapas
--

CREATE SCHEMA topology;


ALTER SCHEMA topology OWNER TO mapas;

--
-- Name: SCHEMA topology; Type: COMMENT; Schema: -; Owner: mapas
--

COMMENT ON SCHEMA topology IS 'PostGIS Topology schema';


--
-- Name: fuzzystrmatch; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch WITH SCHEMA public;


--
-- Name: EXTENSION fuzzystrmatch; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION fuzzystrmatch IS 'determine similarities and distance between strings';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


--
-- Name: postgis_tiger_geocoder; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder WITH SCHEMA tiger;


--
-- Name: EXTENSION postgis_tiger_geocoder; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis_tiger_geocoder IS 'PostGIS tiger geocoder and reverse geocoder';


--
-- Name: postgis_topology; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS postgis_topology WITH SCHEMA topology;


--
-- Name: EXTENSION postgis_topology; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis_topology IS 'PostGIS topology spatial types and functions';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: frequency; Type: DOMAIN; Schema: public; Owner: mapas
--

CREATE DOMAIN public.frequency AS character varying
	CONSTRAINT frequency_check CHECK (((VALUE)::text = ANY (ARRAY[('once'::character varying)::text, ('daily'::character varying)::text, ('weekly'::character varying)::text, ('monthly'::character varying)::text, ('yearly'::character varying)::text])));


ALTER DOMAIN public.frequency OWNER TO mapas;

--
-- Name: days_in_month(date); Type: FUNCTION; Schema: public; Owner: mapas
--

CREATE FUNCTION public.days_in_month(check_date date) RETURNS integer
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
  first_of_month DATE := check_date - ((extract(day from check_date) - 1)||' days')::interval;
BEGIN
  RETURN extract(day from first_of_month + '1 month'::interval - first_of_month);
END;
$$;


ALTER FUNCTION public.days_in_month(check_date date) OWNER TO mapas;

--
-- Name: generate_recurrences(interval, date, date, date, date, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: mapas
--

CREATE FUNCTION public.generate_recurrences(duration interval, original_start_date date, original_end_date date, range_start date, range_end date, repeat_month integer, repeat_week integer, repeat_day integer) RETURNS SETOF date
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
  start_date DATE := original_start_date;
  next_date DATE;
  intervals INT := FLOOR(intervals_between(original_start_date, range_start, duration));
  current_month INT;
  current_week INT;
BEGIN
  IF repeat_month IS NOT NULL THEN
    start_date := start_date + (((12 + repeat_month - cast(extract(month from start_date) as int)) % 12) || ' months')::interval;
  END IF;
  IF repeat_week IS NULL AND repeat_day IS NOT NULL THEN
    IF duration = '7 days'::interval THEN
      start_date := start_date + (((7 + repeat_day - cast(extract(dow from start_date) as int)) % 7) || ' days')::interval;
    ELSE
      start_date := start_date + (repeat_day - extract(day from start_date) || ' days')::interval;
    END IF;
  END IF;
  LOOP
    next_date := start_date + duration * intervals;
    IF repeat_week IS NOT NULL AND repeat_day IS NOT NULL THEN
      current_month := extract(month from next_date);
      next_date := next_date + (((7 + repeat_day - cast(extract(dow from next_date) as int)) % 7) || ' days')::interval;
      IF extract(month from next_date) != current_month THEN
        next_date := next_date - '7 days'::interval;
      END IF;
      IF repeat_week > 0 THEN
        current_week := CEIL(extract(day from next_date) / 7);
      ELSE
        current_week := -CEIL((1 + days_in_month(next_date) - extract(day from next_date)) / 7);
      END IF;
      next_date := next_date + (repeat_week - current_week) * '7 days'::interval;
    END IF;
    EXIT WHEN next_date > range_end;

    IF next_date >= range_start AND next_date >= original_start_date THEN
      RETURN NEXT next_date;
    END IF;

    if original_end_date IS NOT NULL AND range_start >= original_start_date + (duration*intervals) AND range_start <= original_end_date + (duration*intervals) THEN
      RETURN NEXT next_date;
    END IF;
    intervals := intervals + 1;
  END LOOP;
END;
$$;


ALTER FUNCTION public.generate_recurrences(duration interval, original_start_date date, original_end_date date, range_start date, range_end date, repeat_month integer, repeat_week integer, repeat_day integer) OWNER TO mapas;

--
-- Name: interval_for(public.frequency); Type: FUNCTION; Schema: public; Owner: mapas
--

CREATE FUNCTION public.interval_for(recurs public.frequency) RETURNS interval
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  IF recurs = 'daily' THEN
    RETURN '1 day'::interval;
  ELSIF recurs = 'weekly' THEN
    RETURN '7 days'::interval;
  ELSIF recurs = 'monthly' THEN
    RETURN '1 month'::interval;
  ELSIF recurs = 'yearly' THEN
    RETURN '1 year'::interval;
  ELSE
    RAISE EXCEPTION 'Recurrence % not supported by generate_recurrences()', recurs;
  END IF;
END;
$$;


ALTER FUNCTION public.interval_for(recurs public.frequency) OWNER TO mapas;

--
-- Name: intervals_between(date, date, interval); Type: FUNCTION; Schema: public; Owner: mapas
--

CREATE FUNCTION public.intervals_between(start_date date, end_date date, duration interval) RETURNS double precision
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
  count FLOAT := 0;
  multiplier INT := 512;
BEGIN
  IF start_date > end_date THEN
    RETURN 0;
  END IF;
  LOOP
    WHILE start_date + (count + multiplier) * duration < end_date LOOP
      count := count + multiplier;
    END LOOP;
    EXIT WHEN multiplier = 1;
    multiplier := multiplier / 2;
  END LOOP;
  count := count + (extract(epoch from end_date) - extract(epoch from (start_date + count * duration))) / (extract(epoch from end_date + duration) - extract(epoch from end_date))::int;
  RETURN count;
END
$$;


ALTER FUNCTION public.intervals_between(start_date date, end_date date, duration interval) OWNER TO mapas;

--
-- Name: pseudo_random_id_generator(); Type: FUNCTION; Schema: public; Owner: mapas
--

CREATE FUNCTION public.pseudo_random_id_generator() RETURNS integer
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
                DECLARE
                    l1 int;
                    l2 int;
                    r1 int;
                    r2 int;
                    VALUE int;
                    i int:=0;
                BEGIN
                    VALUE:= nextval('pseudo_random_id_seq');
                    l1:= (VALUE >> 16) & 65535;
                    r1:= VALUE & 65535;
                    WHILE i < 3 LOOP
                        l2 := r1;
                        r2 := l1 # ((((1366 * r1 + 150889) % 714025) / 714025.0) * 32767)::int;
                        l1 := l2;
                        r1 := r2;
                        i := i + 1;
                    END LOOP;
                    RETURN ((r1 << 16) + l1);
                END;
            $$;


ALTER FUNCTION public.pseudo_random_id_generator() OWNER TO mapas;

--
-- Name: random_id_generator(character varying, bigint); Type: FUNCTION; Schema: public; Owner: mapas
--

CREATE FUNCTION public.random_id_generator(table_name character varying, initial_range bigint) RETURNS bigint
    LANGUAGE plpgsql
    AS $$DECLARE
              rand_int INTEGER;
              count INTEGER := 1;
              statement TEXT;
            BEGIN
              WHILE count > 0 LOOP
                initial_range := initial_range * 10;

                rand_int := (RANDOM() * initial_range)::BIGINT + initial_range / 10;

                statement := CONCAT('SELECT count(id) FROM ', table_name, ' WHERE id = ', rand_int);

                EXECUTE statement;
                IF NOT FOUND THEN
                  count := 0;
                END IF;

              END LOOP;
              RETURN rand_int;
            END;
            $$;


ALTER FUNCTION public.random_id_generator(table_name character varying, initial_range bigint) OWNER TO mapas;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: event_occurrence; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.event_occurrence (
    id integer NOT NULL,
    space_id integer NOT NULL,
    event_id integer NOT NULL,
    rule text,
    starts_on date,
    ends_on date,
    starts_at timestamp without time zone,
    ends_at timestamp without time zone,
    frequency public.frequency,
    separation integer DEFAULT 1 NOT NULL,
    count integer,
    until date,
    timezone_name text DEFAULT 'Etc/UTC'::text NOT NULL,
    status integer DEFAULT 1 NOT NULL,
    CONSTRAINT positive_separation CHECK ((separation > 0))
);


ALTER TABLE public.event_occurrence OWNER TO mapas;

--
-- Name: recurrences_for(public.event_occurrence, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: mapas
--

CREATE FUNCTION public.recurrences_for(event public.event_occurrence, range_start timestamp without time zone, range_end timestamp without time zone) RETURNS SETOF date
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  recurrence event_occurrence_recurrence;
  recurrences_start DATE := COALESCE(event.starts_at::date, event.starts_on);
  recurrences_end DATE := range_end;
  duration INTERVAL := interval_for(event.frequency) * event.separation;
  next_date DATE;
BEGIN
  IF event.until IS NOT NULL AND event.until < recurrences_end THEN
    recurrences_end := event.until;
  END IF;
  IF event.count IS NOT NULL AND recurrences_start + (event.count - 1) * duration < recurrences_end THEN
    recurrences_end := recurrences_start + (event.count - 1) * duration;
  END IF;

  FOR recurrence IN
    SELECT event_occurrence_recurrence.*
      FROM (SELECT NULL) AS foo
      LEFT JOIN event_occurrence_recurrence
        ON event_occurrence_id = event.id
  LOOP
    FOR next_date IN
      SELECT *
        FROM generate_recurrences(
          duration,
          recurrences_start,
          COALESCE(event.ends_at::date, event.ends_on),
          range_start::date,
          recurrences_end,
          recurrence.month,
          recurrence.week,
          recurrence.day
        )
    LOOP
      RETURN NEXT next_date;
    END LOOP;
  END LOOP;
  RETURN;
END;
$$;


ALTER FUNCTION public.recurrences_for(event public.event_occurrence, range_start timestamp without time zone, range_end timestamp without time zone) OWNER TO mapas;

--
-- Name: recurring_event_occurrence_for(timestamp without time zone, timestamp without time zone, character varying, integer); Type: FUNCTION; Schema: public; Owner: mapas
--

CREATE FUNCTION public.recurring_event_occurrence_for(range_start timestamp without time zone, range_end timestamp without time zone, time_zone character varying, event_occurrence_limit integer) RETURNS SETOF public.event_occurrence
    LANGUAGE plpgsql STABLE
    AS $$
            DECLARE
              event event_occurrence;
              original_date DATE;
              original_date_in_zone DATE;
              start_time TIME;
              start_time_in_zone TIME;
              next_date DATE;
              next_time_in_zone TIME;
              duration INTERVAL;
              time_offset INTERVAL;
              r_start DATE := (timezone('UTC', range_start) AT TIME ZONE time_zone)::DATE;
              r_end DATE := (timezone('UTC', range_end) AT TIME ZONE time_zone)::DATE;

              recurrences_start DATE := CASE WHEN r_start < range_start THEN r_start ELSE range_start END;
              recurrences_end DATE := CASE WHEN r_end > range_end THEN r_end ELSE range_end END;

              inc_interval INTERVAL := '2 hours'::INTERVAL;

              ext_start TIMESTAMP := range_start::TIMESTAMP - inc_interval;
              ext_end   TIMESTAMP := range_end::TIMESTAMP   + inc_interval;
            BEGIN
              FOR event IN
                SELECT *
                  FROM event_occurrence
                  WHERE
                    status > 0
                    AND
                    (
                      (frequency = 'once' AND
                      ((starts_on IS NOT NULL AND ends_on IS NOT NULL AND starts_on <= r_end AND ends_on >= r_start) OR
                       (starts_on IS NOT NULL AND starts_on <= r_end AND starts_on >= r_start) OR
                       (starts_at <= range_end AND ends_at >= range_start)))

                      OR

                      (
                        frequency <> 'once' AND
                        (
                          ( starts_on IS NOT NULL AND starts_on <= ext_end ) OR
                          ( starts_at IS NOT NULL AND starts_at <= ext_end )
                        ) AND (
                          (until IS NULL AND ends_at IS NULL AND ends_on IS NULL) OR
                          (until IS NOT NULL AND until >= ext_start) OR
                          (ends_on IS NOT NULL AND ends_on >= ext_start) OR
                          (ends_at IS NOT NULL AND ends_at >= ext_start)
                        )
                      )
                    )

              LOOP
                IF event.frequency = 'once' THEN
                  RETURN NEXT event;
                  CONTINUE;
                END IF;

                -- All-day event
                IF event.starts_on IS NOT NULL AND event.ends_on IS NULL THEN
                  original_date := event.starts_on;
                  duration := '1 day'::interval;
                -- Multi-day event
                ELSIF event.starts_on IS NOT NULL AND event.ends_on IS NOT NULL THEN
                  original_date := event.starts_on;
                  duration := timezone(time_zone, event.ends_on) - timezone(time_zone, event.starts_on);
                -- Timespan event
                ELSE
                  original_date := event.starts_at::date;
                  original_date_in_zone := (timezone('UTC', event.starts_at) AT TIME ZONE event.timezone_name)::date;
                  start_time := event.starts_at::time;
                  start_time_in_zone := (timezone('UTC', event.starts_at) AT time ZONE event.timezone_name)::time;
                  duration := event.ends_at - event.starts_at;
                END IF;

                IF event.count IS NOT NULL THEN
                  recurrences_start := original_date;
                END IF;

                FOR next_date IN
                  SELECT occurrence
                    FROM (
                      SELECT * FROM recurrences_for(event, recurrences_start, recurrences_end) AS occurrence
                      UNION SELECT original_date
                      LIMIT event.count
                    ) AS occurrences
                    WHERE
                      occurrence::date <= recurrences_end AND
                      (occurrence + duration)::date >= recurrences_start AND
                      occurrence NOT IN (SELECT date FROM event_occurrence_cancellation WHERE event_occurrence_id = event.id)
                    LIMIT event_occurrence_limit
                LOOP
                  -- All-day event
                  IF event.starts_on IS NOT NULL AND event.ends_on IS NULL THEN
                    CONTINUE WHEN next_date < r_start OR next_date > r_end;
                    event.starts_on := next_date;

                  -- Multi-day event
                  ELSIF event.starts_on IS NOT NULL AND event.ends_on IS NOT NULL THEN
                    event.starts_on := next_date;
                    CONTINUE WHEN event.starts_on > r_end;
                    event.ends_on := next_date + duration;
                    CONTINUE WHEN event.ends_on < r_start;

                  -- Timespan event
                  ELSE
                    next_time_in_zone := (timezone('UTC', (next_date + start_time)) at time zone event.timezone_name)::time;
                    time_offset := (original_date_in_zone + next_time_in_zone) - (original_date_in_zone + start_time_in_zone);
                    event.starts_at := next_date + start_time - time_offset;

                    CONTINUE WHEN event.starts_at > range_end;
                    event.ends_at := event.starts_at + duration;
                    CONTINUE WHEN event.ends_at < range_start;
                  END IF;

                  RETURN NEXT event;
                END LOOP;
              END LOOP;
              RETURN;
            END;
            $$;


ALTER FUNCTION public.recurring_event_occurrence_for(range_start timestamp without time zone, range_end timestamp without time zone, time_zone character varying, event_occurrence_limit integer) OWNER TO mapas;

--
-- Name: _mesoregiao; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public._mesoregiao (
    gid integer NOT NULL,
    id double precision,
    nm_meso character varying(100),
    cd_geocodu character varying(2),
    geom public.geometry(MultiPolygon,4326)
);


ALTER TABLE public._mesoregiao OWNER TO mapas;

--
-- Name: _mesoregiao_gid_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public._mesoregiao_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public._mesoregiao_gid_seq OWNER TO mapas;

--
-- Name: _mesoregiao_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public._mesoregiao_gid_seq OWNED BY public._mesoregiao.gid;


--
-- Name: _microregiao; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public._microregiao (
    gid integer NOT NULL,
    id double precision,
    nm_micro character varying(100),
    cd_geocodu character varying(2),
    geom public.geometry(MultiPolygon,4326)
);


ALTER TABLE public._microregiao OWNER TO mapas;

--
-- Name: _microregiao_gid_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public._microregiao_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public._microregiao_gid_seq OWNER TO mapas;

--
-- Name: _microregiao_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public._microregiao_gid_seq OWNED BY public._microregiao.gid;


--
-- Name: _municipios; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public._municipios (
    gid integer NOT NULL,
    id double precision,
    cd_geocodm character varying(20),
    nm_municip character varying(60),
    geom public.geometry(MultiPolygon,4326)
);


ALTER TABLE public._municipios OWNER TO mapas;

--
-- Name: _municipios_gid_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public._municipios_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public._municipios_gid_seq OWNER TO mapas;

--
-- Name: _municipios_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public._municipios_gid_seq OWNED BY public._municipios.gid;


--
-- Name: agent_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.agent_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.agent_id_seq OWNER TO mapas;

--
-- Name: agent; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.agent (
    id integer DEFAULT nextval('public.agent_id_seq'::regclass) NOT NULL,
    parent_id integer,
    user_id integer NOT NULL,
    type smallint NOT NULL,
    name character varying(255) NOT NULL,
    location point,
    _geo_location public.geography,
    short_description text,
    long_description text,
    create_timestamp timestamp without time zone NOT NULL,
    status smallint NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    public_location boolean,
    update_timestamp timestamp(0) without time zone,
    subsite_id integer
);


ALTER TABLE public.agent OWNER TO mapas;

--
-- Name: COLUMN agent.location; Type: COMMENT; Schema: public; Owner: mapas
--

COMMENT ON COLUMN public.agent.location IS 'type=POINT';


--
-- Name: agent_meta; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.agent_meta (
    object_id integer NOT NULL,
    key character varying(255) NOT NULL,
    value text,
    id integer NOT NULL
);


ALTER TABLE public.agent_meta OWNER TO mapas;

--
-- Name: agent_meta_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.agent_meta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.agent_meta_id_seq OWNER TO mapas;

--
-- Name: agent_meta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.agent_meta_id_seq OWNED BY public.agent_meta.id;


--
-- Name: agent_relation; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.agent_relation (
    id integer NOT NULL,
    agent_id integer NOT NULL,
    object_type character varying(255) NOT NULL,
    object_id integer NOT NULL,
    type character varying(64),
    has_control boolean DEFAULT false NOT NULL,
    create_timestamp timestamp without time zone,
    status smallint
);


ALTER TABLE public.agent_relation OWNER TO mapas;

--
-- Name: agent_relation_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.agent_relation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.agent_relation_id_seq OWNER TO mapas;

--
-- Name: agent_relation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.agent_relation_id_seq OWNED BY public.agent_relation.id;


--
-- Name: db_update; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.db_update (
    name character varying(255) NOT NULL,
    exec_time timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.db_update OWNER TO mapas;

--
-- Name: entity_revision; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.entity_revision (
    id integer NOT NULL,
    user_id integer,
    object_id integer NOT NULL,
    object_type character varying(255) NOT NULL,
    create_timestamp timestamp(0) without time zone NOT NULL,
    action character varying(255) NOT NULL,
    message text NOT NULL
);


ALTER TABLE public.entity_revision OWNER TO mapas;

--
-- Name: entity_revision_data; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.entity_revision_data (
    id integer NOT NULL,
    "timestamp" timestamp(0) without time zone NOT NULL,
    key character varying(255) NOT NULL,
    value text
);


ALTER TABLE public.entity_revision_data OWNER TO mapas;

--
-- Name: entity_revision_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.entity_revision_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.entity_revision_id_seq OWNER TO mapas;

--
-- Name: entity_revision_revision_data; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.entity_revision_revision_data (
    revision_id integer NOT NULL,
    revision_data_id integer NOT NULL
);


ALTER TABLE public.entity_revision_revision_data OWNER TO mapas;

--
-- Name: evaluation_method_configuration; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.evaluation_method_configuration (
    id integer NOT NULL,
    opportunity_id integer NOT NULL,
    type character varying(255) NOT NULL
);


ALTER TABLE public.evaluation_method_configuration OWNER TO mapas;

--
-- Name: evaluation_method_configuration_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.evaluation_method_configuration_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.evaluation_method_configuration_id_seq OWNER TO mapas;

--
-- Name: evaluation_method_configuration_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.evaluation_method_configuration_id_seq OWNED BY public.evaluation_method_configuration.id;


--
-- Name: evaluationmethodconfiguration_meta; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.evaluationmethodconfiguration_meta (
    id integer NOT NULL,
    object_id integer NOT NULL,
    key character varying(255) NOT NULL,
    value text
);


ALTER TABLE public.evaluationmethodconfiguration_meta OWNER TO mapas;

--
-- Name: evaluationmethodconfiguration_meta_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.evaluationmethodconfiguration_meta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.evaluationmethodconfiguration_meta_id_seq OWNER TO mapas;

--
-- Name: event; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.event (
    id integer NOT NULL,
    project_id integer,
    name character varying(255) NOT NULL,
    short_description text NOT NULL,
    long_description text,
    rules text,
    create_timestamp timestamp without time zone NOT NULL,
    status smallint NOT NULL,
    agent_id integer,
    is_verified boolean DEFAULT false NOT NULL,
    type smallint NOT NULL,
    update_timestamp timestamp(0) without time zone,
    subsite_id integer
);


ALTER TABLE public.event OWNER TO mapas;

--
-- Name: event_attendance; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.event_attendance (
    id integer NOT NULL,
    user_id integer NOT NULL,
    event_occurrence_id integer NOT NULL,
    event_id integer NOT NULL,
    space_id integer NOT NULL,
    type character varying(255) NOT NULL,
    reccurrence_string text,
    start_timestamp timestamp(0) without time zone NOT NULL,
    end_timestamp timestamp(0) without time zone NOT NULL,
    create_timestamp timestamp(0) without time zone NOT NULL
);


ALTER TABLE public.event_attendance OWNER TO mapas;

--
-- Name: event_attendance_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.event_attendance_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.event_attendance_id_seq OWNER TO mapas;

--
-- Name: event_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.event_id_seq OWNER TO mapas;

--
-- Name: event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.event_id_seq OWNED BY public.event.id;


--
-- Name: event_meta; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.event_meta (
    key character varying(255) NOT NULL,
    object_id integer NOT NULL,
    value text,
    id integer NOT NULL
);


ALTER TABLE public.event_meta OWNER TO mapas;

--
-- Name: event_meta_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.event_meta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.event_meta_id_seq OWNER TO mapas;

--
-- Name: event_meta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.event_meta_id_seq OWNED BY public.event_meta.id;


--
-- Name: event_occurrence_cancellation; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.event_occurrence_cancellation (
    id integer NOT NULL,
    event_occurrence_id integer,
    date date
);


ALTER TABLE public.event_occurrence_cancellation OWNER TO mapas;

--
-- Name: event_occurrence_cancellation_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.event_occurrence_cancellation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.event_occurrence_cancellation_id_seq OWNER TO mapas;

--
-- Name: event_occurrence_cancellation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.event_occurrence_cancellation_id_seq OWNED BY public.event_occurrence_cancellation.id;


--
-- Name: event_occurrence_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.event_occurrence_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.event_occurrence_id_seq OWNER TO mapas;

--
-- Name: event_occurrence_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.event_occurrence_id_seq OWNED BY public.event_occurrence.id;


--
-- Name: event_occurrence_recurrence; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.event_occurrence_recurrence (
    id integer NOT NULL,
    event_occurrence_id integer,
    month integer,
    day integer,
    week integer
);


ALTER TABLE public.event_occurrence_recurrence OWNER TO mapas;

--
-- Name: event_occurrence_recurrence_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.event_occurrence_recurrence_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.event_occurrence_recurrence_id_seq OWNER TO mapas;

--
-- Name: event_occurrence_recurrence_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.event_occurrence_recurrence_id_seq OWNED BY public.event_occurrence_recurrence.id;


--
-- Name: file_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.file_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.file_id_seq OWNER TO mapas;

--
-- Name: file; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.file (
    id integer DEFAULT nextval('public.file_id_seq'::regclass) NOT NULL,
    md5 character varying(32) NOT NULL,
    mime_type character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    object_type character varying(255) NOT NULL,
    object_id integer NOT NULL,
    create_timestamp timestamp without time zone DEFAULT now() NOT NULL,
    grp character varying(32) NOT NULL,
    description character varying(255),
    parent_id integer,
    path character varying(1024) DEFAULT NULL::character varying,
    private boolean DEFAULT false NOT NULL
);


ALTER TABLE public.file OWNER TO mapas;

--
-- Name: geo_division_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.geo_division_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.geo_division_id_seq OWNER TO mapas;

--
-- Name: geo_division; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.geo_division (
    id integer DEFAULT nextval('public.geo_division_id_seq'::regclass) NOT NULL,
    parent_id integer,
    type character varying(32) NOT NULL,
    cod character varying(32),
    name character varying(128) NOT NULL,
    geom public.geometry,
    CONSTRAINT enforce_dims_geom CHECK ((public.st_ndims(geom) = 2)),
    CONSTRAINT enforce_geotype_geom CHECK (((public.geometrytype(geom) = 'MULTIPOLYGON'::text) OR (geom IS NULL))),
    CONSTRAINT enforce_srid_geom CHECK ((public.st_srid(geom) = 4326))
);


ALTER TABLE public.geo_division OWNER TO mapas;

--
-- Name: metadata; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.metadata (
    object_id integer NOT NULL,
    object_type character varying(255) NOT NULL,
    key character varying(32) NOT NULL,
    value text
);


ALTER TABLE public.metadata OWNER TO mapas;

--
-- Name: metalist_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.metalist_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.metalist_id_seq OWNER TO mapas;

--
-- Name: metalist; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.metalist (
    id integer DEFAULT nextval('public.metalist_id_seq'::regclass) NOT NULL,
    object_type character varying(255) NOT NULL,
    object_id integer NOT NULL,
    grp character varying(32) NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    value character varying(2048) NOT NULL,
    create_timestamp timestamp without time zone DEFAULT now() NOT NULL,
    "order" smallint
);


ALTER TABLE public.metalist OWNER TO mapas;

--
-- Name: notification_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.notification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.notification_id_seq OWNER TO mapas;

--
-- Name: notification; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.notification (
    id integer DEFAULT nextval('public.notification_id_seq'::regclass) NOT NULL,
    user_id integer NOT NULL,
    request_id integer,
    message text NOT NULL,
    create_timestamp timestamp without time zone DEFAULT now() NOT NULL,
    action_timestamp timestamp without time zone,
    status smallint NOT NULL
);


ALTER TABLE public.notification OWNER TO mapas;

--
-- Name: notification_meta; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.notification_meta (
    id integer NOT NULL,
    object_id integer NOT NULL,
    key character varying(255) NOT NULL,
    value text
);


ALTER TABLE public.notification_meta OWNER TO mapas;

--
-- Name: notification_meta_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.notification_meta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.notification_meta_id_seq OWNER TO mapas;

--
-- Name: occurrence_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.occurrence_id_seq
    START WITH 100000
    INCREMENT BY 1
    MINVALUE 100000
    NO MAXVALUE
    CACHE 1
    CYCLE;


ALTER TABLE public.occurrence_id_seq OWNER TO mapas;

--
-- Name: opportunity_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.opportunity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.opportunity_id_seq OWNER TO mapas;

--
-- Name: opportunity; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.opportunity (
    id integer DEFAULT nextval('public.opportunity_id_seq'::regclass) NOT NULL,
    parent_id integer,
    agent_id integer NOT NULL,
    type smallint,
    name character varying(255) NOT NULL,
    short_description text,
    long_description text,
    registration_from timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    registration_to timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    published_registrations boolean NOT NULL,
    registration_categories text,
    create_timestamp timestamp(0) without time zone NOT NULL,
    update_timestamp timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    status smallint NOT NULL,
    subsite_id integer,
    object_type character varying(255) NOT NULL,
    object_id integer NOT NULL
);


ALTER TABLE public.opportunity OWNER TO mapas;

--
-- Name: opportunity_meta_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.opportunity_meta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.opportunity_meta_id_seq OWNER TO mapas;

--
-- Name: opportunity_meta; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.opportunity_meta (
    id integer DEFAULT nextval('public.opportunity_meta_id_seq'::regclass) NOT NULL,
    object_id integer NOT NULL,
    key character varying(255) NOT NULL,
    value text
);


ALTER TABLE public.opportunity_meta OWNER TO mapas;

--
-- Name: pcache_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.pcache_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.pcache_id_seq OWNER TO mapas;

--
-- Name: pcache; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.pcache (
    id integer DEFAULT nextval('public.pcache_id_seq'::regclass) NOT NULL,
    user_id integer NOT NULL,
    action character varying(255) NOT NULL,
    create_timestamp timestamp(0) without time zone NOT NULL,
    object_type character varying(255) NOT NULL,
    object_id integer
);


ALTER TABLE public.pcache OWNER TO mapas;

--
-- Name: permission_cache_pending; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.permission_cache_pending (
    id integer NOT NULL,
    object_id integer NOT NULL,
    object_type character varying(255) NOT NULL
);


ALTER TABLE public.permission_cache_pending OWNER TO mapas;

--
-- Name: permission_cache_pending_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.permission_cache_pending_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.permission_cache_pending_seq OWNER TO mapas;

--
-- Name: procuration; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.procuration (
    token character varying(32) NOT NULL,
    usr_id integer NOT NULL,
    attorney_user_id integer NOT NULL,
    action character varying(255) NOT NULL,
    create_timestamp timestamp(0) without time zone NOT NULL,
    valid_until_timestamp timestamp(0) without time zone DEFAULT NULL::timestamp without time zone
);


ALTER TABLE public.procuration OWNER TO mapas;

--
-- Name: project; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.project (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    short_description text,
    long_description text,
    create_timestamp timestamp without time zone NOT NULL,
    status smallint NOT NULL,
    agent_id integer,
    is_verified boolean DEFAULT false NOT NULL,
    type smallint NOT NULL,
    parent_id integer,
    registration_from timestamp without time zone,
    registration_to timestamp without time zone,
    update_timestamp timestamp(0) without time zone,
    subsite_id integer
);


ALTER TABLE public.project OWNER TO mapas;

--
-- Name: project_event; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.project_event (
    id integer NOT NULL,
    event_id integer NOT NULL,
    project_id integer NOT NULL,
    type smallint NOT NULL,
    status smallint NOT NULL
);


ALTER TABLE public.project_event OWNER TO mapas;

--
-- Name: project_event_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.project_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.project_event_id_seq OWNER TO mapas;

--
-- Name: project_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.project_event_id_seq OWNED BY public.project_event.id;


--
-- Name: project_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.project_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.project_id_seq OWNER TO mapas;

--
-- Name: project_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.project_id_seq OWNED BY public.project.id;


--
-- Name: project_meta; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.project_meta (
    object_id integer NOT NULL,
    key character varying(255) NOT NULL,
    value text,
    id integer NOT NULL
);


ALTER TABLE public.project_meta OWNER TO mapas;

--
-- Name: project_meta_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.project_meta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.project_meta_id_seq OWNER TO mapas;

--
-- Name: project_meta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.project_meta_id_seq OWNED BY public.project_meta.id;


--
-- Name: pseudo_random_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.pseudo_random_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.pseudo_random_id_seq OWNER TO mapas;

--
-- Name: registration; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.registration (
    id integer DEFAULT public.pseudo_random_id_generator() NOT NULL,
    opportunity_id integer NOT NULL,
    category character varying(255),
    agent_id integer NOT NULL,
    create_timestamp timestamp without time zone DEFAULT now() NOT NULL,
    sent_timestamp timestamp without time zone,
    status smallint NOT NULL,
    agents_data text,
    subsite_id integer,
    consolidated_result character varying(255) DEFAULT NULL::character varying,
    number character varying(24),
    valuers_exceptions_list text DEFAULT '{"include": [], "exclude": []}'::text NOT NULL,
    space_data text
);


ALTER TABLE public.registration OWNER TO mapas;

--
-- Name: registration_evaluation; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.registration_evaluation (
    id integer NOT NULL,
    registration_id integer DEFAULT public.pseudo_random_id_generator() NOT NULL,
    user_id integer NOT NULL,
    result character varying(255) DEFAULT NULL::character varying,
    evaluation_data text NOT NULL,
    status smallint
);


ALTER TABLE public.registration_evaluation OWNER TO mapas;

--
-- Name: registration_evaluation_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.registration_evaluation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.registration_evaluation_id_seq OWNER TO mapas;

--
-- Name: registration_field_configuration; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.registration_field_configuration (
    id integer NOT NULL,
    opportunity_id integer,
    title character varying(255) NOT NULL,
    description text,
    categories text,
    required boolean NOT NULL,
    field_type character varying(255) NOT NULL,
    field_options text NOT NULL,
    max_size text,
    display_order smallint DEFAULT 255,
    config text
);


ALTER TABLE public.registration_field_configuration OWNER TO mapas;

--
-- Name: COLUMN registration_field_configuration.categories; Type: COMMENT; Schema: public; Owner: mapas
--

COMMENT ON COLUMN public.registration_field_configuration.categories IS '(DC2Type:array)';


--
-- Name: registration_field_configuration_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.registration_field_configuration_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.registration_field_configuration_id_seq OWNER TO mapas;

--
-- Name: registration_file_configuration; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.registration_file_configuration (
    id integer NOT NULL,
    opportunity_id integer,
    title character varying(255) NOT NULL,
    description text,
    required boolean NOT NULL,
    categories text,
    display_order smallint DEFAULT 255
);


ALTER TABLE public.registration_file_configuration OWNER TO mapas;

--
-- Name: COLUMN registration_file_configuration.categories; Type: COMMENT; Schema: public; Owner: mapas
--

COMMENT ON COLUMN public.registration_file_configuration.categories IS '(DC2Type:array)';


--
-- Name: registration_file_configuration_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.registration_file_configuration_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.registration_file_configuration_id_seq OWNER TO mapas;

--
-- Name: registration_file_configuration_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.registration_file_configuration_id_seq OWNED BY public.registration_file_configuration.id;


--
-- Name: registration_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.registration_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.registration_id_seq OWNER TO mapas;

--
-- Name: registration_meta; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.registration_meta (
    object_id integer NOT NULL,
    key character varying(255) NOT NULL,
    value text,
    id integer NOT NULL
);


ALTER TABLE public.registration_meta OWNER TO mapas;

--
-- Name: registration_meta_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.registration_meta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.registration_meta_id_seq OWNER TO mapas;

--
-- Name: registration_meta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.registration_meta_id_seq OWNED BY public.registration_meta.id;


--
-- Name: request_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.request_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.request_id_seq OWNER TO mapas;

--
-- Name: request; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.request (
    id integer DEFAULT nextval('public.request_id_seq'::regclass) NOT NULL,
    request_uid character varying(32) NOT NULL,
    requester_user_id integer NOT NULL,
    origin_type character varying(255) NOT NULL,
    origin_id integer NOT NULL,
    destination_type character varying(255) NOT NULL,
    destination_id integer NOT NULL,
    metadata text,
    type character varying(255) NOT NULL,
    create_timestamp timestamp without time zone DEFAULT now() NOT NULL,
    action_timestamp timestamp without time zone,
    status smallint NOT NULL
);


ALTER TABLE public.request OWNER TO mapas;

--
-- Name: revision_data_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.revision_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.revision_data_id_seq OWNER TO mapas;

--
-- Name: role; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.role (
    id integer NOT NULL,
    usr_id integer,
    name character varying(32) NOT NULL,
    subsite_id integer
);


ALTER TABLE public.role OWNER TO mapas;

--
-- Name: role_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.role_id_seq OWNER TO mapas;

--
-- Name: role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.role_id_seq OWNED BY public.role.id;


--
-- Name: seal; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.seal (
    id integer NOT NULL,
    agent_id integer NOT NULL,
    name character varying(255) NOT NULL,
    short_description text,
    long_description text,
    valid_period smallint NOT NULL,
    create_timestamp timestamp(0) without time zone NOT NULL,
    status smallint NOT NULL,
    certificate_text text,
    update_timestamp timestamp(0) without time zone,
    subsite_id integer
);


ALTER TABLE public.seal OWNER TO mapas;

--
-- Name: seal_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.seal_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.seal_id_seq OWNER TO mapas;

--
-- Name: seal_meta; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.seal_meta (
    id integer NOT NULL,
    object_id integer NOT NULL,
    key character varying(255) NOT NULL,
    value text
);


ALTER TABLE public.seal_meta OWNER TO mapas;

--
-- Name: seal_meta_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.seal_meta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.seal_meta_id_seq OWNER TO mapas;

--
-- Name: seal_relation; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.seal_relation (
    id integer NOT NULL,
    seal_id integer,
    object_id integer NOT NULL,
    create_timestamp timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    status smallint,
    object_type character varying(255) NOT NULL,
    agent_id integer NOT NULL,
    owner_id integer,
    validate_date date,
    renovation_request boolean
);


ALTER TABLE public.seal_relation OWNER TO mapas;

--
-- Name: seal_relation_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.seal_relation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.seal_relation_id_seq OWNER TO mapas;

--
-- Name: space; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.space (
    id integer NOT NULL,
    parent_id integer,
    location point,
    _geo_location public.geography,
    name character varying(255) NOT NULL,
    short_description text,
    long_description text,
    create_timestamp timestamp without time zone DEFAULT now() NOT NULL,
    status smallint NOT NULL,
    type smallint NOT NULL,
    agent_id integer,
    is_verified boolean DEFAULT false NOT NULL,
    public boolean DEFAULT false NOT NULL,
    update_timestamp timestamp(0) without time zone,
    subsite_id integer
);


ALTER TABLE public.space OWNER TO mapas;

--
-- Name: COLUMN space.location; Type: COMMENT; Schema: public; Owner: mapas
--

COMMENT ON COLUMN public.space.location IS 'type=POINT';


--
-- Name: space_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.space_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.space_id_seq OWNER TO mapas;

--
-- Name: space_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.space_id_seq OWNED BY public.space.id;


--
-- Name: space_meta; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.space_meta (
    object_id integer NOT NULL,
    key character varying(255) NOT NULL,
    value text,
    id integer NOT NULL
);


ALTER TABLE public.space_meta OWNER TO mapas;

--
-- Name: space_meta_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.space_meta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.space_meta_id_seq OWNER TO mapas;

--
-- Name: space_meta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.space_meta_id_seq OWNED BY public.space_meta.id;


--
-- Name: space_relation; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.space_relation (
    id integer NOT NULL,
    space_id integer,
    object_id integer NOT NULL,
    create_timestamp timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    status smallint,
    object_type character varying(255) NOT NULL
);


ALTER TABLE public.space_relation OWNER TO mapas;

--
-- Name: space_relation_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.space_relation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.space_relation_id_seq OWNER TO mapas;

--
-- Name: subsite; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.subsite (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    create_timestamp timestamp(0) without time zone NOT NULL,
    status smallint NOT NULL,
    agent_id integer NOT NULL,
    url character varying(255) NOT NULL,
    namespace character varying(50) NOT NULL,
    alias_url character varying(255) DEFAULT NULL::character varying,
    verified_seals character varying(512) DEFAULT '[]'::character varying
);


ALTER TABLE public.subsite OWNER TO mapas;

--
-- Name: subsite_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.subsite_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.subsite_id_seq OWNER TO mapas;

--
-- Name: subsite_meta; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.subsite_meta (
    object_id integer NOT NULL,
    key character varying(255) NOT NULL,
    value text,
    id integer NOT NULL
);


ALTER TABLE public.subsite_meta OWNER TO mapas;

--
-- Name: subsite_meta_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.subsite_meta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.subsite_meta_id_seq OWNER TO mapas;

--
-- Name: term; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.term (
    id integer NOT NULL,
    taxonomy character varying(64) NOT NULL,
    term character varying(255) NOT NULL,
    description text
);


ALTER TABLE public.term OWNER TO mapas;

--
-- Name: COLUMN term.taxonomy; Type: COMMENT; Schema: public; Owner: mapas
--

COMMENT ON COLUMN public.term.taxonomy IS '1=tag';


--
-- Name: term_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.term_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.term_id_seq OWNER TO mapas;

--
-- Name: term_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.term_id_seq OWNED BY public.term.id;


--
-- Name: term_relation; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.term_relation (
    term_id integer NOT NULL,
    object_type character varying(255) NOT NULL,
    object_id integer NOT NULL,
    id integer NOT NULL
);


ALTER TABLE public.term_relation OWNER TO mapas;

--
-- Name: term_relation_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.term_relation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.term_relation_id_seq OWNER TO mapas;

--
-- Name: term_relation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mapas
--

ALTER SEQUENCE public.term_relation_id_seq OWNED BY public.term_relation.id;


--
-- Name: user_app; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.user_app (
    public_key character varying(64) NOT NULL,
    private_key character varying(128) NOT NULL,
    user_id integer NOT NULL,
    name text NOT NULL,
    status integer NOT NULL,
    create_timestamp timestamp without time zone NOT NULL,
    subsite_id integer
);


ALTER TABLE public.user_app OWNER TO mapas;

--
-- Name: user_meta; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.user_meta (
    object_id integer NOT NULL,
    key character varying(255) NOT NULL,
    value text,
    id integer NOT NULL
);


ALTER TABLE public.user_meta OWNER TO mapas;

--
-- Name: user_meta_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.user_meta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.user_meta_id_seq OWNER TO mapas;

--
-- Name: usr_id_seq; Type: SEQUENCE; Schema: public; Owner: mapas
--

CREATE SEQUENCE public.usr_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.usr_id_seq OWNER TO mapas;

--
-- Name: usr; Type: TABLE; Schema: public; Owner: mapas
--

CREATE TABLE public.usr (
    id integer DEFAULT nextval('public.usr_id_seq'::regclass) NOT NULL,
    auth_provider smallint NOT NULL,
    auth_uid character varying(512) NOT NULL,
    email character varying(255) NOT NULL,
    last_login_timestamp timestamp without time zone NOT NULL,
    create_timestamp timestamp without time zone DEFAULT now() NOT NULL,
    status smallint NOT NULL,
    profile_id integer
);


ALTER TABLE public.usr OWNER TO mapas;

--
-- Name: COLUMN usr.auth_provider; Type: COMMENT; Schema: public; Owner: mapas
--

COMMENT ON COLUMN public.usr.auth_provider IS '1=openid';


--
-- Name: _mesoregiao gid; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public._mesoregiao ALTER COLUMN gid SET DEFAULT nextval('public._mesoregiao_gid_seq'::regclass);


--
-- Name: _microregiao gid; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public._microregiao ALTER COLUMN gid SET DEFAULT nextval('public._microregiao_gid_seq'::regclass);


--
-- Name: _municipios gid; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public._municipios ALTER COLUMN gid SET DEFAULT nextval('public._municipios_gid_seq'::regclass);


--
-- Name: agent_relation id; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.agent_relation ALTER COLUMN id SET DEFAULT nextval('public.agent_relation_id_seq'::regclass);


--
-- Name: evaluation_method_configuration id; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.evaluation_method_configuration ALTER COLUMN id SET DEFAULT nextval('public.evaluation_method_configuration_id_seq'::regclass);


--
-- Name: event id; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event ALTER COLUMN id SET DEFAULT nextval('public.event_id_seq'::regclass);


--
-- Name: event_occurrence id; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_occurrence ALTER COLUMN id SET DEFAULT nextval('public.event_occurrence_id_seq'::regclass);


--
-- Name: event_occurrence_cancellation id; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_occurrence_cancellation ALTER COLUMN id SET DEFAULT nextval('public.event_occurrence_cancellation_id_seq'::regclass);


--
-- Name: event_occurrence_recurrence id; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_occurrence_recurrence ALTER COLUMN id SET DEFAULT nextval('public.event_occurrence_recurrence_id_seq'::regclass);


--
-- Name: project id; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.project ALTER COLUMN id SET DEFAULT nextval('public.project_id_seq'::regclass);


--
-- Name: project_event id; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.project_event ALTER COLUMN id SET DEFAULT nextval('public.project_event_id_seq'::regclass);


--
-- Name: space id; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.space ALTER COLUMN id SET DEFAULT nextval('public.space_id_seq'::regclass);


--
-- Name: term id; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.term ALTER COLUMN id SET DEFAULT nextval('public.term_id_seq'::regclass);


--
-- Name: term_relation id; Type: DEFAULT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.term_relation ALTER COLUMN id SET DEFAULT nextval('public.term_relation_id_seq'::regclass);


--
-- Data for Name: _mesoregiao; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public._mesoregiao (gid, id, nm_meso, cd_geocodu, geom) FROM stdin;
\.


--
-- Data for Name: _microregiao; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public._microregiao (gid, id, nm_micro, cd_geocodu, geom) FROM stdin;
\.


--
-- Data for Name: _municipios; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public._municipios (gid, id, cd_geocodm, nm_municip, geom) FROM stdin;
\.


--
-- Data for Name: agent; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.agent (id, parent_id, user_id, type, name, location, _geo_location, short_description, long_description, create_timestamp, status, is_verified, public_location, update_timestamp, subsite_id) FROM stdin;
46	\N	12	1	teste	(0,0)	\N	\N	\N	2020-08-27 13:25:49	1	f	f	\N	\N
38	\N	2	2	Cooletivo	(0,0)	0101000020E610000000000000000000000000000000000000	Cooletivo é uma cooperativa massa	\N	2020-08-24 18:05:02	1	f	t	2020-08-24 21:56:16	\N
5	\N	4	2		(0,0)	\N	Coletivo muito maneiro	\N	2020-08-24 06:05:04	1	f	f	2020-08-24 06:43:48	\N
4	\N	4	1	Rafa Chaves	(-48.5411803391000021,-27.6039300011999984)	0101000020E61000001BD6B865454548C02C3A14289B9A3BC0	RAFA		2020-08-21 07:01:32	1	f	t	2020-08-25 21:42:19	\N
1	\N	1	1	Rafa	(0,0)	0101000020E610000000000000000000000000000000000000	asd asd asd asd		2019-03-07 00:00:00	1	f	f	2020-08-19 20:51:10	\N
3	\N	3	1	Teste 1	(0,0)	\N		\N	2020-08-20 23:28:10	1	f	f	2020-08-20 23:29:10	\N
2	\N	2	1	hacklab/ serviços de tecnologia	(0,0)	0101000020E610000000000000000000000000000000000000	Rafael Freitas		2020-08-15 22:06:30	1	f	t	2020-08-24 21:56:16	\N
39	\N	5	1	Rafael	(-46.6467483999999999,-23.5465762000000005)	0101000020E6100000C35ECDA6C85247C09FC5F76AEC8B37C0	Uma monstra demoníaca		2020-08-25 21:42:52	1	f	t	2020-08-26 06:44:20	\N
40	\N	6	1	Rudá	(0,0)	0101000020E610000000000000000000000000000000000000	\N	\N	2020-08-26 07:06:58	1	f	t	2020-08-26 07:09:37	\N
41	\N	7	1	Sardinha	(0,0)	0101000020E610000000000000000000000000000000000000	\N	\N	2020-08-26 07:15:10	1	f	t	2020-08-26 07:16:41	\N
42	\N	8	1	Praga	(0,0)	\N	\N	\N	2020-08-26 07:23:01	1	f	f	\N	\N
43	\N	9	1	adasdas	(0,0)	\N	\N	\N	2020-08-26 07:42:57	1	f	f	\N	\N
44	\N	10	1	teste123	(0,0)	\N	\N	\N	2020-08-26 07:44:46	1	f	f	\N	\N
45	\N	11	1	rafael chaves	(0,0)	0101000020E610000000000000000000000000000000000000	\N	\N	2020-08-26 07:47:45	1	f	t	2020-08-26 07:49:07	\N
\.


--
-- Data for Name: agent_meta; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.agent_meta (object_id, key, value, id) FROM stdin;
2	aldirblanc_inciso1_registration	735327624	2
2	En_Num		62
39	orientacaoSexual	Outras	70
39	raca	Preta	71
39	endereco	Rua Rego Freitas, 530, apto D4, República, 01220-010, São Paulo, SP	74
2	emailPrivado	rafael@hacklab.com.br	8
1	aldirblanc_inciso1_registration	1731020007	9
39	En_CEP	01220-010	75
39	En_Nome_Logradouro	Rua Rego Freitas	76
39	En_Num	530	77
1	emailPrivado	rafael@hacklab.com.br	13
1	genero	Homem Trans.	14
1	telefone1	(11) 9332-2123	12
39	En_Complemento	apto D4	78
1	telefone2	(11) 1234-1233	16
39	En_Bairro	República	79
39	En_Municipio	São Paulo	80
39	En_Estado	SP	81
38	En_Municipio	Fortaleza	53
38	En_Estado	CE	54
1	dataDeNascimento	2020-08-07	1
1	nomeCompleto	Rafael Chaves	11
3	aldirblanc_inciso1_registration	792482838	17
3	nomeCompleto	Rafael Chaves	19
3	dataDeNascimento	1981-09-30	20
3	telefone1	(11) 964655828	21
3	documento	123.321.123-12	18
1	raca		15
1	documento	050.913.009-70	10
2	nomeCompleto	Rafael Chaves	6
2	documento	050.913.009-70	3
1	En_CEP	01232-12	22
1	En_Num	35	24
1	En_Complemento	apto 91A	25
1	En_Bairro	Bila Madalena	26
1	En_Municipio	São Paulo	27
5	En_CEP		43
5	En_Nome_Logradouro		44
5	En_Num		45
1	En_Nome_Logradouro		23
2	telefone1	11 12321231	28
2	dataDeNascimento	2020-08-26	5
5	En_Bairro		46
3	En_CEP	12332-12	29
4	aldirblanc_inciso1_registration	1020199467	30
39	aldirblanc_inciso1_registration	1970483263	82
5	En_Municipio		47
5	En_Estado		48
42	documento	1	110
39	dataDeNascimento	2020-01-27	68
39	genero	ASDASDASD	69
2	genero	Homem Transexual	4
39	documento	050.913.009-70	67
2	raca	Branca	7
40	aldirblanc_inciso1_registration	902053773	84
40	nomeCompleto	Rudá Freitas Medeiros	85
40	En_CEP	05453-060	86
40	En_Nome_Logradouro	Praça Japuba	87
38	En_CEP	60714-730	51
38	En_Bairro	Dendê	50
38	En_Nome_Logradouro	Rua Campo Maior	52
2	En_CEP	01220-010	57
2	En_Municipio	São Paulo	60
2	En_Estado	SP	61
2	En_Nome_Logradouro	Rua Rego Freitas	58
2	En_Bairro	República	59
40	En_Bairro	Vila Madalena	88
4	En_Num		36
4	endereco		49
4	En_Estado		42
40	En_Municipio	São Paulo	89
40	En_Estado	SP	90
4	En_Municipio		38
4	En_Nome_Logradouro		35
4	En_Bairro		39
4	En_CEP		34
4	En_Complemento		37
39	telefone1	11999999999	73
40	En_Num	35	91
39	telefone2	1	83
40	En_Complemento	apto 91A	92
40	documento	050.913.009-70	93
41	aldirblanc_inciso1_registration	1715162904	94
41	En_CEP	05453-060	95
41	En_Nome_Logradouro	Praça Japuba	96
41	En_Num	35	97
41	En_Complemento	apto 91a	98
41	En_Bairro	Vila Madalena	99
38	En_Num	530	55
38	En_Complemento	apto D4	56
4	genero	""	40
4	telefone1		63
4	raca	Branca	41
4	dataDeNascimento	2020-08-19	33
4	telefone2		64
4	emailPrivado		65
41	En_Municipio	São Paulo	100
4	nomeCompleto	Rafael Chaves Freitas	32
39	emailPrivado	sarda@asd.com	72
41	En_Estado	SP	101
41	documento	050.913.009-70	102
41	nomeCompleto	Rafael Freitas	103
41	dataDeNascimento	2020-08-12	104
41	telefone1	123123123	105
41	telefone2	123123123	106
41	emailPrivado	rafafafa@asdasda.cm	107
41	raca	Amarela	108
42	aldirblanc_inciso1_registration	905535019	109
43	aldirblanc_inciso1_registration	1750691250	111
44	aldirblanc_inciso1_registration	413170950	113
4	documento	050.913.009-70	31
43	documento	111.1	112
44	nomeCompleto	1233	114
45	aldirblanc_inciso1_registration	1066273876	115
45	nomeCompleto	rafael freitas	117
45	telefone1	11232323123	118
45	telefone2	32312312323123	119
45	emailPrivado	raaasfas@asdasd.com	120
45	En_CEP	01220-010	121
45	En_Nome_Logradouro	Rua Rego Freitas	122
45	En_Num	530	123
45	En_Bairro	República	124
45	En_Municipio	São Paulo	125
45	En_Estado	SP	126
39	nomeCompleto	Rafael	66
45	En_Complemento	d4	127
45	genero	Homem	128
45	raca	Parda	129
45	dataDeNascimento	2020-08-13	130
45	documento	050.913.009-70	116
46	aldirblanc_inciso1_registration	1076435879	131
\.


--
-- Data for Name: agent_relation; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.agent_relation (id, agent_id, object_type, object_id, type, has_control, create_timestamp, status) FROM stdin;
1	1	MapasCulturais\\Entities\\Agent	3	group-admin	t	2020-08-22 01:48:41	-5
2	5	MapasCulturais\\Entities\\Registration	1967657373	coletivo	f	2020-08-24 06:05:16	1
35	38	MapasCulturais\\Entities\\Registration	763896078	coletivo	f	2020-08-24 18:05:12	1
\.


--
-- Data for Name: db_update; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.db_update (name, exec_time) FROM stdin;
alter tablel term taxonomy type	2019-03-07 23:54:06.885661
new random id generator	2019-03-07 23:54:06.885661
migrate gender	2019-03-07 23:54:06.885661
create table user apps	2019-03-07 23:54:06.885661
create table user_meta	2019-03-07 23:54:06.885661
create seal and seal relation tables	2019-03-07 23:54:06.885661
resize entity meta key columns	2019-03-07 23:54:06.885661
create registration field configuration table	2019-03-07 23:54:06.885661
alter table registration_file_configuration add categories	2019-03-07 23:54:06.885661
create saas tables	2019-03-07 23:54:06.885661
rename saas tables to subsite	2019-03-07 23:54:06.885661
remove parent_url and add alias_url	2019-03-07 23:54:06.885661
verified seal migration	2019-03-07 23:54:06.885661
create update timestamp entities	2019-03-07 23:54:06.885661
alter table role add column subsite_id	2019-03-07 23:54:06.885661
Fix field options field type from registration field configuration	2019-03-07 23:54:06.885661
ADD columns subsite_id	2019-03-07 23:54:06.885661
remove subsite slug column	2019-03-07 23:54:06.885661
add subsite verified_seals column	2019-03-07 23:54:06.885661
update entities last_update_timestamp with user last log timestamp	2019-03-07 23:54:06.885661
Created owner seal relation field	2019-03-07 23:54:06.885661
create table pcache	2019-03-07 23:54:06.885661
function create pcache id sequence 2	2019-03-07 23:54:06.885661
Add field for maximum size from registration field configuration	2019-03-07 23:54:06.885661
Add notification type for compliant and suggestion messages	2019-03-07 23:54:06.885661
create entity revision tables	2019-03-07 23:54:06.885661
ALTER TABLE file ADD COLUMN path	2019-03-07 23:54:06.885661
*_meta drop all indexes again	2019-03-07 23:54:06.885661
recreate *_meta indexes	2019-03-07 23:54:06.885661
create permission cache pending table2	2019-03-07 23:54:06.885661
create opportunity tables	2019-03-07 23:54:06.885661
DROP CONSTRAINT registration_project_fk");	2019-03-07 23:54:06.885661
fix opportunity parent FK	2019-03-07 23:54:06.885661
fix opportunity type 35	2019-03-07 23:54:06.885661
create opportunity sequence	2019-03-07 23:54:06.885661
update opportunity_meta_id sequence	2019-03-07 23:54:06.885661
rename opportunity_meta key isProjectPhase to isOpportunityPhase	2019-03-07 23:54:06.885661
migrate introInscricoes value to shortDescription	2019-03-07 23:54:06.885661
ALTER TABLE registration ADD consolidated_result	2019-03-07 23:54:06.885661
create evaluation methods tables	2019-03-07 23:54:06.885661
create registration_evaluation table	2019-03-07 23:54:06.885661
ALTER TABLE opportunity ALTER type DROP NOT NULL;	2019-03-07 23:54:06.885661
create seal relation renovation flag field	2019-03-07 23:54:06.885661
create seal relation validate date	2019-03-07 23:54:06.885661
update seal_relation set validate_date	2019-03-07 23:54:06.885661
refactor of entity meta keky value indexes	2019-03-07 23:54:06.885661
DROP index registration_meta_value_idx	2019-03-07 23:54:06.885661
altertable registration_file_and_files_add_order	2019-03-07 23:54:06.885661
replace subsite entidades_habilitadas values	2019-03-07 23:54:06.885661
replace subsite cor entidades values	2019-03-07 23:54:06.885661
ALTER TABLE file ADD private and update	2019-03-07 23:54:06.885661
move private files	2019-03-07 23:54:06.885661
create permission cache sequence	2019-03-07 23:54:06.885661
create evaluation methods sequence	2019-03-07 23:54:06.885661
change opportunity field agent_id not null	2019-03-07 23:54:06.885661
alter table registration add column number	2019-03-07 23:54:06.885661
update registrations set number fixed	2019-03-07 23:54:06.885661
alter table registration add column valuers_exceptions_list	2019-03-07 23:54:06.885661
update taxonomy slug tag	2019-03-07 23:54:06.885661
update taxonomy slug area	2019-03-07 23:54:06.885661
update taxonomy slug linguagem	2019-03-07 23:54:06.885661
recreate pcache	2019-03-07 23:54:19.344941
generate file path	2019-03-07 23:54:19.352266
create entities history entries	2019-03-07 23:54:19.357385
create entities updated revision	2019-03-07 23:54:19.362878
fix update timestamp of revisioned entities	2019-03-07 23:54:19.367904
consolidate registration result	2019-03-07 23:54:19.3728
create avatar thumbs	2019-03-07 23:55:16.963658
create event attendance table	2020-07-18 01:17:40.827672
create procuration table	2020-07-18 01:17:40.827672
CREATE SEQUENCE REGISTRATION SPACE RELATION registration_space_relation_id_seq	2020-08-12 16:09:39.152195
CREATE TABLE spacerelation	2020-08-12 16:09:39.152195
ALTER TABLE registration	2020-08-12 16:09:39.152195
alter table registration_field_configuration add column config	2020-08-18 03:30:51.948148
\.


--
-- Data for Name: entity_revision; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.entity_revision (id, user_id, object_id, object_type, create_timestamp, action, message) FROM stdin;
1	1	1	MapasCulturais\\Entities\\Agent	2019-03-07 00:00:00	created	Registro criado.
2	1	1	MapasCulturais\\Entities\\Agent	2020-08-05 12:54:05	modified	Registro atualizado.
3	2	2	MapasCulturais\\Entities\\Agent	2020-08-15 22:06:30	created	Registro criado.
4	2	2	MapasCulturais\\Entities\\Agent	2020-08-15 22:06:30	modified	Registro atualizado.
5	2	2	MapasCulturais\\Entities\\Agent	2020-08-15 22:20:53	modified	Registro atualizado.
6	2	2	MapasCulturais\\Entities\\Agent	2020-08-17 19:58:02	modified	Registro atualizado.
7	2	2	MapasCulturais\\Entities\\Agent	2020-08-18 03:31:31	modified	Registro atualizado.
8	1	2	MapasCulturais\\Entities\\Agent	2020-08-18 05:02:28	modified	Registro atualizado.
9	1	2	MapasCulturais\\Entities\\Agent	2020-08-18 05:12:06	modified	Registro atualizado.
10	1	2	MapasCulturais\\Entities\\Agent	2020-08-18 05:16:00	modified	Registro atualizado.
11	1	2	MapasCulturais\\Entities\\Agent	2020-08-18 05:44:55	modified	Registro atualizado.
12	1	2	MapasCulturais\\Entities\\Agent	2020-08-18 06:04:34	modified	Registro atualizado.
13	1	2	MapasCulturais\\Entities\\Agent	2020-08-18 06:05:48	modified	Registro atualizado.
14	1	2	MapasCulturais\\Entities\\Agent	2020-08-18 06:23:36	modified	Registro atualizado.
15	1	2	MapasCulturais\\Entities\\Agent	2020-08-18 07:02:36	modified	Registro atualizado.
16	2	2	MapasCulturais\\Entities\\Agent	2020-08-18 18:56:09	modified	Registro atualizado.
17	2	2	MapasCulturais\\Entities\\Agent	2020-08-18 18:56:09	modified	Registro atualizado.
18	2	2	MapasCulturais\\Entities\\Agent	2020-08-18 18:56:09	modified	Registro atualizado.
19	2	2	MapasCulturais\\Entities\\Agent	2020-08-18 18:56:09	modified	Registro atualizado.
20	2	2	MapasCulturais\\Entities\\Agent	2020-08-18 18:56:10	modified	Registro atualizado.
21	2	2	MapasCulturais\\Entities\\Agent	2020-08-18 18:58:31	modified	Registro atualizado.
22	2	2	MapasCulturais\\Entities\\Agent	2020-08-18 19:00:59	modified	Registro atualizado.
23	2	2	MapasCulturais\\Entities\\Agent	2020-08-18 19:03:24	modified	Registro atualizado.
24	2	2	MapasCulturais\\Entities\\Agent	2020-08-18 19:04:23	modified	Registro atualizado.
25	2	2	MapasCulturais\\Entities\\Agent	2020-08-18 19:05:26	modified	Registro atualizado.
26	2	2	MapasCulturais\\Entities\\Agent	2020-08-18 19:07:45	modified	Registro atualizado.
27	1	2	MapasCulturais\\Entities\\Agent	2020-08-18 23:38:50	modified	Registro atualizado.
28	1	2	MapasCulturais\\Entities\\Agent	2020-08-18 23:47:19	modified	Registro atualizado.
29	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:11:06	modified	Registro atualizado.
30	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:14:15	modified	Registro atualizado.
31	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:14:15	modified	Registro atualizado.
32	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:15:29	modified	Registro atualizado.
33	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:16:01	modified	Registro atualizado.
34	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:16:12	modified	Registro atualizado.
35	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:16:20	modified	Registro atualizado.
36	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:16:27	modified	Registro atualizado.
37	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:16:45	modified	Registro atualizado.
38	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:17:09	modified	Registro atualizado.
39	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:17:19	modified	Registro atualizado.
40	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:25:26	modified	Registro atualizado.
41	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:32:09	modified	Registro atualizado.
42	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:42:28	modified	Registro atualizado.
43	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:47:19	modified	Registro atualizado.
44	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:47:20	modified	Registro atualizado.
45	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:47:45	modified	Registro atualizado.
46	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:47:45	modified	Registro atualizado.
47	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:48:05	modified	Registro atualizado.
48	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:48:24	modified	Registro atualizado.
49	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:48:25	modified	Registro atualizado.
50	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:49:44	modified	Registro atualizado.
51	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:49:44	modified	Registro atualizado.
52	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:50:30	modified	Registro atualizado.
53	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:51:00	modified	Registro atualizado.
54	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:51:10	modified	Registro atualizado.
55	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:51:10	modified	Registro atualizado.
56	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:52:55	modified	Registro atualizado.
57	1	1	MapasCulturais\\Entities\\Agent	2020-08-19 20:53:11	modified	Registro atualizado.
58	1	1	MapasCulturais\\Entities\\Agent	2020-08-20 23:22:39	modified	Registro atualizado.
59	1	3	MapasCulturais\\Entities\\Agent	2020-08-20 23:28:10	created	Registro criado.
60	1	3	MapasCulturais\\Entities\\Agent	2020-08-20 23:28:10	modified	Registro atualizado.
61	3	3	MapasCulturais\\Entities\\Agent	2020-08-20 23:28:25	modified	Registro atualizado.
62	3	3	MapasCulturais\\Entities\\Agent	2020-08-20 23:29:10	modified	Registro atualizado.
63	3	3	MapasCulturais\\Entities\\Agent	2020-08-20 23:29:10	modified	Registro atualizado.
64	3	3	MapasCulturais\\Entities\\Agent	2020-08-20 23:36:16	modified	Registro atualizado.
65	3	3	MapasCulturais\\Entities\\Agent	2020-08-20 23:36:58	modified	Registro atualizado.
66	3	3	MapasCulturais\\Entities\\Agent	2020-08-20 23:37:27	modified	Registro atualizado.
67	3	3	MapasCulturais\\Entities\\Agent	2020-08-21 01:07:13	modified	Registro atualizado.
68	1	1	MapasCulturais\\Entities\\Agent	2020-08-21 04:37:05	modified	Registro atualizado.
69	1	1	MapasCulturais\\Entities\\Agent	2020-08-21 04:37:05	modified	Registro atualizado.
70	1	1	MapasCulturais\\Entities\\Agent	2020-08-21 04:37:40	modified	Registro atualizado.
71	1	2	MapasCulturais\\Entities\\Agent	2020-08-21 04:39:06	modified	Registro atualizado.
72	1	2	MapasCulturais\\Entities\\Agent	2020-08-21 04:39:06	modified	Registro atualizado.
73	1	2	MapasCulturais\\Entities\\Agent	2020-08-21 04:39:06	modified	Registro atualizado.
74	1	2	MapasCulturais\\Entities\\Agent	2020-08-21 04:39:26	modified	Registro atualizado.
75	1	1	MapasCulturais\\Entities\\Agent	2020-08-21 05:43:36	modified	Registro atualizado.
76	1	1	MapasCulturais\\Entities\\Agent	2020-08-21 05:46:47	modified	Registro atualizado.
77	1	1	MapasCulturais\\Entities\\Agent	2020-08-21 05:47:25	modified	Registro atualizado.
78	1	1	MapasCulturais\\Entities\\Agent	2020-08-21 05:47:49	modified	Registro atualizado.
79	1	2	MapasCulturais\\Entities\\Agent	2020-08-21 05:56:49	modified	Registro atualizado.
80	1	2	MapasCulturais\\Entities\\Agent	2020-08-21 05:57:03	modified	Registro atualizado.
81	1	2	MapasCulturais\\Entities\\Agent	2020-08-21 05:57:14	modified	Registro atualizado.
82	1	1	MapasCulturais\\Entities\\Agent	2020-08-21 06:11:49	modified	Registro atualizado.
83	1	1	MapasCulturais\\Entities\\Agent	2020-08-21 06:12:35	modified	Registro atualizado.
84	1	1	MapasCulturais\\Entities\\Agent	2020-08-21 06:12:38	modified	Registro atualizado.
85	1	2	MapasCulturais\\Entities\\Agent	2020-08-21 06:29:11	modified	Registro atualizado.
86	1	2	MapasCulturais\\Entities\\Agent	2020-08-21 06:29:11	modified	Registro atualizado.
87	1	2	MapasCulturais\\Entities\\Agent	2020-08-21 06:57:35	modified	Registro atualizado.
88	1	3	MapasCulturais\\Entities\\Agent	2020-08-21 06:58:39	modified	Registro atualizado.
89	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 07:01:32	created	Registro criado.
90	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 07:01:32	modified	Registro atualizado.
91	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 07:01:37	modified	Registro atualizado.
92	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 07:02:01	modified	Registro atualizado.
93	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 07:02:02	modified	Registro atualizado.
94	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 07:02:55	modified	Registro atualizado.
95	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 07:16:24	modified	Registro atualizado.
96	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 07:16:24	modified	Registro atualizado.
97	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 07:17:37	modified	Registro atualizado.
98	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 18:28:28	modified	Registro atualizado.
99	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 18:28:46	modified	Registro atualizado.
100	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 18:31:08	modified	Registro atualizado.
101	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 18:33:23	modified	Registro atualizado.
102	4	4	MapasCulturais\\Entities\\Agent	2020-08-21 18:36:30	modified	Registro atualizado.
103	1	4	MapasCulturais\\Entities\\Agent	2020-08-21 18:40:26	modified	Registro atualizado.
104	1	2	MapasCulturais\\Entities\\Agent	2020-08-22 00:39:27	modified	Registro atualizado.
105	1	2	MapasCulturais\\Entities\\Agent	2020-08-22 00:39:27	modified	Registro atualizado.
106	1	2	MapasCulturais\\Entities\\Agent	2020-08-22 00:39:28	modified	Registro atualizado.
107	1	2	MapasCulturais\\Entities\\Agent	2020-08-22 00:39:50	modified	Registro atualizado.
108	1	2	MapasCulturais\\Entities\\Agent	2020-08-22 00:42:17	modified	Registro atualizado.
109	1	2	MapasCulturais\\Entities\\Agent	2020-08-22 00:42:21	modified	Registro atualizado.
110	1	2	MapasCulturais\\Entities\\Agent	2020-08-22 00:42:22	modified	Registro atualizado.
111	1	2	MapasCulturais\\Entities\\Agent	2020-08-22 00:42:28	modified	Registro atualizado.
112	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:01:47	modified	Registro atualizado.
113	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:01:47	modified	Registro atualizado.
114	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:01:50	modified	Registro atualizado.
115	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:09:39	modified	Registro atualizado.
116	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:12:12	modified	Registro atualizado.
117	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:12:34	modified	Registro atualizado.
118	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:12:47	modified	Registro atualizado.
119	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:15:28	modified	Registro atualizado.
120	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:15:41	modified	Registro atualizado.
121	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:16:14	modified	Registro atualizado.
122	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:16:21	modified	Registro atualizado.
123	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:17:50	modified	Registro atualizado.
124	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:18:34	modified	Registro atualizado.
125	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:19:04	modified	Registro atualizado.
126	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:19:05	modified	Registro atualizado.
127	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:19:16	modified	Registro atualizado.
128	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:19:21	modified	Registro atualizado.
129	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:19:49	modified	Registro atualizado.
130	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:20:10	modified	Registro atualizado.
131	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:20:19	modified	Registro atualizado.
132	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:20:23	modified	Registro atualizado.
133	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:20:56	modified	Registro atualizado.
134	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:20:59	modified	Registro atualizado.
135	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:21:08	modified	Registro atualizado.
136	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:24:41	modified	Registro atualizado.
137	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:24:48	modified	Registro atualizado.
138	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:25:05	modified	Registro atualizado.
139	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:27:00	modified	Registro atualizado.
140	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:27:35	modified	Registro atualizado.
141	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:27:44	modified	Registro atualizado.
142	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:27:54	modified	Registro atualizado.
143	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:29:20	modified	Registro atualizado.
144	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:29:28	modified	Registro atualizado.
145	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:29:42	modified	Registro atualizado.
146	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 05:31:58	modified	Registro atualizado.
147	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:26:08	modified	Registro atualizado.
148	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:26:53	modified	Registro atualizado.
149	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:26:57	modified	Registro atualizado.
150	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:32:36	modified	Registro atualizado.
151	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:32:38	modified	Registro atualizado.
152	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:32:42	modified	Registro atualizado.
153	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:36:16	modified	Registro atualizado.
154	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:36:43	modified	Registro atualizado.
155	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:47:20	modified	Registro atualizado.
156	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:47:24	modified	Registro atualizado.
157	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:47:46	modified	Registro atualizado.
158	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:48:43	modified	Registro atualizado.
159	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:48:47	modified	Registro atualizado.
160	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:48:57	modified	Registro atualizado.
161	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:49:21	modified	Registro atualizado.
162	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:49:24	modified	Registro atualizado.
163	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:52:05	modified	Registro atualizado.
164	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:52:13	modified	Registro atualizado.
165	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:52:24	modified	Registro atualizado.
166	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:52:58	modified	Registro atualizado.
167	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:53:00	modified	Registro atualizado.
168	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:57:56	modified	Registro atualizado.
169	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:57:59	modified	Registro atualizado.
170	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:58:00	modified	Registro atualizado.
171	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:58:23	modified	Registro atualizado.
172	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:58:24	modified	Registro atualizado.
173	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:58:47	modified	Registro atualizado.
174	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 06:58:48	modified	Registro atualizado.
175	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 07:05:13	modified	Registro atualizado.
176	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 07:05:21	modified	Registro atualizado.
177	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 07:05:26	modified	Registro atualizado.
178	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 07:05:42	modified	Registro atualizado.
179	4	4	MapasCulturais\\Entities\\Agent	2020-08-22 07:05:56	modified	Registro atualizado.
180	4	4	MapasCulturais\\Entities\\Agent	2020-08-23 21:42:44	modified	Registro atualizado.
181	4	4	MapasCulturais\\Entities\\Agent	2020-08-23 22:45:02	modified	Registro atualizado.
182	4	4	MapasCulturais\\Entities\\Agent	2020-08-23 22:45:51	modified	Registro atualizado.
183	4	4	MapasCulturais\\Entities\\Agent	2020-08-23 22:49:35	modified	Registro atualizado.
184	4	4	MapasCulturais\\Entities\\Agent	2020-08-23 22:50:36	modified	Registro atualizado.
185	4	4	MapasCulturais\\Entities\\Agent	2020-08-23 22:50:37	modified	Registro atualizado.
186	4	4	MapasCulturais\\Entities\\Agent	2020-08-23 22:51:06	modified	Registro atualizado.
187	4	4	MapasCulturais\\Entities\\Agent	2020-08-23 22:51:07	modified	Registro atualizado.
188	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:16:18	modified	Registro atualizado.
189	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:16:54	modified	Registro atualizado.
190	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:18:49	modified	Registro atualizado.
191	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:19:16	modified	Registro atualizado.
192	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:21:30	modified	Registro atualizado.
193	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:22:49	modified	Registro atualizado.
194	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:23:24	modified	Registro atualizado.
195	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:24:15	modified	Registro atualizado.
196	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:24:40	modified	Registro atualizado.
197	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:26:28	modified	Registro atualizado.
198	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:26:29	modified	Registro atualizado.
199	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:26:39	modified	Registro atualizado.
200	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:27:23	modified	Registro atualizado.
201	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:44:38	modified	Registro atualizado.
202	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:45:50	modified	Registro atualizado.
203	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:45:51	modified	Registro atualizado.
204	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:46:50	modified	Registro atualizado.
205	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:46:51	modified	Registro atualizado.
206	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:49:38	modified	Registro atualizado.
207	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:49:40	modified	Registro atualizado.
208	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:49:56	modified	Registro atualizado.
209	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:50:20	modified	Registro atualizado.
210	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:51:08	modified	Registro atualizado.
211	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:51:11	modified	Registro atualizado.
212	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:51:55	modified	Registro atualizado.
213	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:51:56	modified	Registro atualizado.
214	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:52:03	modified	Registro atualizado.
215	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:52:05	modified	Registro atualizado.
216	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:52:07	modified	Registro atualizado.
217	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:52:09	modified	Registro atualizado.
218	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:58:46	modified	Registro atualizado.
219	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 00:59:23	modified	Registro atualizado.
220	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:13:37	modified	Registro atualizado.
221	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:13:40	modified	Registro atualizado.
222	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:13:42	modified	Registro atualizado.
223	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:13:46	modified	Registro atualizado.
224	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:23:56	modified	Registro atualizado.
225	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:23:58	modified	Registro atualizado.
226	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:24:00	modified	Registro atualizado.
227	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:25:19	modified	Registro atualizado.
228	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:25:36	modified	Registro atualizado.
229	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:25:55	modified	Registro atualizado.
230	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:26:39	modified	Registro atualizado.
231	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:26:40	modified	Registro atualizado.
232	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:27:05	modified	Registro atualizado.
233	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:27:08	modified	Registro atualizado.
234	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:27:15	modified	Registro atualizado.
235	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:27:21	modified	Registro atualizado.
236	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:27:23	modified	Registro atualizado.
237	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:42:07	modified	Registro atualizado.
238	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:42:12	modified	Registro atualizado.
239	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:42:35	modified	Registro atualizado.
240	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:43:09	modified	Registro atualizado.
241	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:43:35	modified	Registro atualizado.
242	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:44:09	modified	Registro atualizado.
243	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:45:17	modified	Registro atualizado.
244	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 01:46:21	modified	Registro atualizado.
245	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 02:00:03	modified	Registro atualizado.
246	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 02:00:05	modified	Registro atualizado.
247	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 02:00:10	modified	Registro atualizado.
248	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 02:00:27	modified	Registro atualizado.
249	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:19:39	modified	Registro atualizado.
250	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:20:12	modified	Registro atualizado.
251	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:21:22	modified	Registro atualizado.
252	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:21:50	modified	Registro atualizado.
253	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:22:45	modified	Registro atualizado.
254	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:22:48	modified	Registro atualizado.
255	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:22:58	modified	Registro atualizado.
256	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:23:00	modified	Registro atualizado.
257	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:24:32	modified	Registro atualizado.
258	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:24:36	modified	Registro atualizado.
259	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:24:43	modified	Registro atualizado.
260	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:24:49	modified	Registro atualizado.
261	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:25:02	modified	Registro atualizado.
262	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:25:04	modified	Registro atualizado.
263	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:25:07	modified	Registro atualizado.
264	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:25:21	modified	Registro atualizado.
265	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:25:25	modified	Registro atualizado.
266	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:25:26	modified	Registro atualizado.
267	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:25:42	modified	Registro atualizado.
268	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:25:44	modified	Registro atualizado.
269	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:25:45	modified	Registro atualizado.
270	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:26:07	modified	Registro atualizado.
271	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:26:19	modified	Registro atualizado.
272	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:26:22	modified	Registro atualizado.
273	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:26:35	modified	Registro atualizado.
274	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:26:44	modified	Registro atualizado.
275	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:26:56	modified	Registro atualizado.
276	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:27:04	modified	Registro atualizado.
277	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:27:10	modified	Registro atualizado.
278	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:27:13	modified	Registro atualizado.
279	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:27:44	modified	Registro atualizado.
280	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:27:48	modified	Registro atualizado.
281	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:27:54	modified	Registro atualizado.
282	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:29:21	modified	Registro atualizado.
283	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:29:31	modified	Registro atualizado.
284	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:29:37	modified	Registro atualizado.
285	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:30:17	modified	Registro atualizado.
286	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:30:21	modified	Registro atualizado.
287	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:30:24	modified	Registro atualizado.
288	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:31:54	modified	Registro atualizado.
289	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:31:56	modified	Registro atualizado.
290	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:32:02	modified	Registro atualizado.
291	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:32:03	modified	Registro atualizado.
292	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:32:04	modified	Registro atualizado.
293	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:32:51	modified	Registro atualizado.
294	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:34:32	modified	Registro atualizado.
295	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:35:03	modified	Registro atualizado.
296	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:36:01	modified	Registro atualizado.
297	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:36:02	modified	Registro atualizado.
298	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:36:10	modified	Registro atualizado.
299	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:36:11	modified	Registro atualizado.
300	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:36:23	modified	Registro atualizado.
301	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:36:24	modified	Registro atualizado.
302	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:37:44	modified	Registro atualizado.
303	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:37:46	modified	Registro atualizado.
304	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:38:11	modified	Registro atualizado.
305	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:38:11	modified	Registro atualizado.
306	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:38:15	modified	Registro atualizado.
307	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:38:16	modified	Registro atualizado.
308	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:57:48	modified	Registro atualizado.
309	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:57:53	modified	Registro atualizado.
310	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:57:54	modified	Registro atualizado.
311	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:57:59	modified	Registro atualizado.
312	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:58:16	modified	Registro atualizado.
313	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:59:13	modified	Registro atualizado.
314	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:59:14	modified	Registro atualizado.
315	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:59:26	modified	Registro atualizado.
316	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:59:58	modified	Registro atualizado.
317	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 03:59:59	modified	Registro atualizado.
318	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:03:12	modified	Registro atualizado.
319	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:03:43	modified	Registro atualizado.
320	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:04:19	modified	Registro atualizado.
321	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:04:20	modified	Registro atualizado.
322	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:04:23	modified	Registro atualizado.
323	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:06:56	modified	Registro atualizado.
324	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:06:58	modified	Registro atualizado.
325	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:07:00	modified	Registro atualizado.
326	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:07:03	modified	Registro atualizado.
327	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:07:06	modified	Registro atualizado.
328	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:07:17	modified	Registro atualizado.
329	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:07:18	modified	Registro atualizado.
330	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:08:38	modified	Registro atualizado.
331	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:11:55	modified	Registro atualizado.
332	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:12:07	modified	Registro atualizado.
333	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:12:11	modified	Registro atualizado.
334	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:12:15	modified	Registro atualizado.
335	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:12:33	modified	Registro atualizado.
336	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:12:36	modified	Registro atualizado.
337	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:14:08	modified	Registro atualizado.
338	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:17:34	modified	Registro atualizado.
339	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:17:39	modified	Registro atualizado.
340	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:17:45	modified	Registro atualizado.
341	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:17:55	modified	Registro atualizado.
342	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:17:58	modified	Registro atualizado.
343	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:18:01	modified	Registro atualizado.
344	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:18:05	modified	Registro atualizado.
345	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:18:09	modified	Registro atualizado.
346	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:18:17	modified	Registro atualizado.
347	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:24:34	modified	Registro atualizado.
348	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:30:15	modified	Registro atualizado.
349	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 04:30:19	modified	Registro atualizado.
350	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 05:02:51	modified	Registro atualizado.
351	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 05:02:57	modified	Registro atualizado.
352	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 05:02:59	modified	Registro atualizado.
353	4	5	MapasCulturais\\Entities\\Agent	2020-08-24 06:05:04	created	Registro criado.
354	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:05:25	modified	Registro atualizado.
355	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:05:25	modified	Registro atualizado.
356	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:05:29	modified	Registro atualizado.
357	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:05:30	modified	Registro atualizado.
358	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:05:39	modified	Registro atualizado.
359	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:05:39	modified	Registro atualizado.
360	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:05:40	modified	Registro atualizado.
361	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:05:40	modified	Registro atualizado.
362	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:05:44	modified	Registro atualizado.
363	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:05:44	modified	Registro atualizado.
364	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:07:20	modified	Registro atualizado.
365	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:07:21	modified	Registro atualizado.
386	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:08:14	modified	Registro atualizado.
387	4	5	MapasCulturais\\Entities\\Agent	2020-08-24 06:08:14	modified	Registro atualizado.
388	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:43:47	modified	Registro atualizado.
389	4	5	MapasCulturais\\Entities\\Agent	2020-08-24 06:43:48	modified	Registro atualizado.
390	4	5	MapasCulturais\\Entities\\Agent	2020-08-24 06:43:48	modified	Registro atualizado.
391	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:43:52	modified	Registro atualizado.
392	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:43:57	modified	Registro atualizado.
393	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:44:56	created	Registro criado.
394	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:45:13	modified	Registro atualizado.
395	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:45:14	modified	Registro atualizado.
396	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:52:41	modified	Registro atualizado.
397	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:52:41	modified	Registro atualizado.
398	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:52:49	modified	Registro atualizado.
399	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:52:49	modified	Registro atualizado.
400	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:52:50	modified	Registro atualizado.
401	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:52:51	modified	Registro atualizado.
402	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:52:52	modified	Registro atualizado.
403	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:52:53	modified	Registro atualizado.
404	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:53:49	modified	Registro atualizado.
405	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:53:50	modified	Registro atualizado.
406	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:54:47	modified	Registro atualizado.
407	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:54:48	modified	Registro atualizado.
408	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:55:23	modified	Registro atualizado.
409	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:55:24	modified	Registro atualizado.
410	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:56:18	modified	Registro atualizado.
411	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:56:18	modified	Registro atualizado.
412	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:56:47	modified	Registro atualizado.
413	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:56:47	modified	Registro atualizado.
414	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:57:56	modified	Registro atualizado.
415	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:57:56	modified	Registro atualizado.
416	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:58:30	modified	Registro atualizado.
417	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:58:30	modified	Registro atualizado.
418	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:59:20	modified	Registro atualizado.
419	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:59:20	modified	Registro atualizado.
420	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:59:33	modified	Registro atualizado.
421	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:59:33	modified	Registro atualizado.
422	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 06:59:44	modified	Registro atualizado.
423	4	1	MapasCulturais\\Entities\\Space	2020-08-24 06:59:45	modified	Registro atualizado.
424	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:00:07	modified	Registro atualizado.
425	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:00:07	modified	Registro atualizado.
426	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:00:25	modified	Registro atualizado.
427	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:00:26	modified	Registro atualizado.
428	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:00:32	modified	Registro atualizado.
429	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:00:33	modified	Registro atualizado.
430	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:00:41	modified	Registro atualizado.
431	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:00:42	modified	Registro atualizado.
432	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:00:44	modified	Registro atualizado.
433	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:00:44	modified	Registro atualizado.
434	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:01:08	modified	Registro atualizado.
435	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:01:09	modified	Registro atualizado.
436	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:02:33	modified	Registro atualizado.
437	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:02:33	modified	Registro atualizado.
438	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:02:36	modified	Registro atualizado.
439	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:02:37	modified	Registro atualizado.
440	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:02:48	modified	Registro atualizado.
441	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:02:49	modified	Registro atualizado.
442	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:04:56	modified	Registro atualizado.
443	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:04:57	modified	Registro atualizado.
444	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:05:03	modified	Registro atualizado.
445	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:05:04	modified	Registro atualizado.
446	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:05:23	modified	Registro atualizado.
447	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:05:23	modified	Registro atualizado.
448	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:06:48	modified	Registro atualizado.
449	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:06:49	modified	Registro atualizado.
450	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:07:04	modified	Registro atualizado.
451	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:07:04	modified	Registro atualizado.
452	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:07:05	modified	Registro atualizado.
453	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:07:05	modified	Registro atualizado.
454	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:07:36	modified	Registro atualizado.
455	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:07:36	modified	Registro atualizado.
456	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:07:38	modified	Registro atualizado.
457	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:07:39	modified	Registro atualizado.
458	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:08:01	modified	Registro atualizado.
459	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:08:02	modified	Registro atualizado.
460	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:09:34	modified	Registro atualizado.
461	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:09:35	modified	Registro atualizado.
462	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:09:36	modified	Registro atualizado.
463	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:09:36	modified	Registro atualizado.
464	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:09:41	modified	Registro atualizado.
465	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:09:42	modified	Registro atualizado.
466	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:12:26	modified	Registro atualizado.
467	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:12:27	modified	Registro atualizado.
468	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:12:28	modified	Registro atualizado.
469	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:12:29	modified	Registro atualizado.
470	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:12:35	modified	Registro atualizado.
471	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:12:35	modified	Registro atualizado.
472	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:12:37	modified	Registro atualizado.
473	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:12:37	modified	Registro atualizado.
474	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:12:48	modified	Registro atualizado.
475	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:12:49	modified	Registro atualizado.
476	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:12:54	modified	Registro atualizado.
477	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:12:54	modified	Registro atualizado.
478	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:12:55	modified	Registro atualizado.
479	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:12:56	modified	Registro atualizado.
480	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:12:59	modified	Registro atualizado.
481	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:13:00	modified	Registro atualizado.
482	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:16:56	modified	Registro atualizado.
483	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:16:57	modified	Registro atualizado.
484	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:16:59	modified	Registro atualizado.
485	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:16:59	modified	Registro atualizado.
486	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:17:06	modified	Registro atualizado.
487	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:17:07	modified	Registro atualizado.
488	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:17:13	modified	Registro atualizado.
489	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:17:13	modified	Registro atualizado.
490	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:17:14	modified	Registro atualizado.
491	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:17:15	modified	Registro atualizado.
492	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:18:09	modified	Registro atualizado.
493	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:18:09	modified	Registro atualizado.
494	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:18:16	modified	Registro atualizado.
495	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:18:16	modified	Registro atualizado.
496	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:18:22	modified	Registro atualizado.
497	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:18:22	modified	Registro atualizado.
498	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:18:48	modified	Registro atualizado.
499	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:18:48	modified	Registro atualizado.
500	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:18:55	modified	Registro atualizado.
501	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:18:55	modified	Registro atualizado.
502	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:23:17	modified	Registro atualizado.
503	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:23:17	modified	Registro atualizado.
504	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:23:42	modified	Registro atualizado.
505	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:23:43	modified	Registro atualizado.
506	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:24:15	modified	Registro atualizado.
507	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:24:16	modified	Registro atualizado.
508	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:24:19	modified	Registro atualizado.
509	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:24:20	modified	Registro atualizado.
510	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:24:29	modified	Registro atualizado.
511	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:24:30	modified	Registro atualizado.
512	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:24:43	modified	Registro atualizado.
513	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:24:44	modified	Registro atualizado.
514	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:25:01	modified	Registro atualizado.
515	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:25:01	modified	Registro atualizado.
516	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:25:05	modified	Registro atualizado.
517	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:25:05	modified	Registro atualizado.
518	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:25:44	modified	Registro atualizado.
519	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:25:45	modified	Registro atualizado.
520	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:28:01	modified	Registro atualizado.
521	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:28:01	modified	Registro atualizado.
522	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:29:31	modified	Registro atualizado.
523	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:29:31	modified	Registro atualizado.
524	4	4	MapasCulturais\\Entities\\Agent	2020-08-24 07:29:39	modified	Registro atualizado.
525	4	1	MapasCulturais\\Entities\\Space	2020-08-24 07:29:39	modified	Registro atualizado.
526	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:05:02	created	Registro criado.
527	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:15:56	modified	Registro atualizado.
528	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:15:56	modified	Registro atualizado.
529	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:16:49	modified	Registro atualizado.
530	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:17:02	modified	Registro atualizado.
531	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:17:22	modified	Registro atualizado.
532	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:17:22	modified	Registro atualizado.
533	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 18:21:36	modified	Registro atualizado.
534	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:21:36	modified	Registro atualizado.
535	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 18:21:45	modified	Registro atualizado.
536	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:21:46	modified	Registro atualizado.
537	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 18:21:52	modified	Registro atualizado.
538	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:21:52	modified	Registro atualizado.
539	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 18:21:55	modified	Registro atualizado.
540	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:21:55	modified	Registro atualizado.
541	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 18:25:48	modified	Registro atualizado.
542	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:25:48	modified	Registro atualizado.
543	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 18:28:35	modified	Registro atualizado.
544	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:28:35	modified	Registro atualizado.
545	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 18:29:08	modified	Registro atualizado.
546	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:29:08	modified	Registro atualizado.
547	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 18:30:49	modified	Registro atualizado.
548	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:30:50	modified	Registro atualizado.
549	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 18:30:58	modified	Registro atualizado.
550	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:30:59	modified	Registro atualizado.
551	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 18:31:31	modified	Registro atualizado.
552	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 18:31:31	modified	Registro atualizado.
553	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:20:35	modified	Registro atualizado.
554	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:20:35	modified	Registro atualizado.
555	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:20:37	modified	Registro atualizado.
556	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:20:37	modified	Registro atualizado.
557	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:20:40	modified	Registro atualizado.
558	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:20:40	modified	Registro atualizado.
559	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:20:48	modified	Registro atualizado.
560	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:20:48	modified	Registro atualizado.
561	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:20:56	modified	Registro atualizado.
562	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:20:57	modified	Registro atualizado.
563	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:21:00	modified	Registro atualizado.
564	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:21:00	modified	Registro atualizado.
565	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:21:09	modified	Registro atualizado.
566	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:21:09	modified	Registro atualizado.
567	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:21:13	modified	Registro atualizado.
568	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:21:13	modified	Registro atualizado.
569	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:21:17	modified	Registro atualizado.
570	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:21:17	modified	Registro atualizado.
571	2	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:21:20	modified	Registro atualizado.
572	2	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:21:20	modified	Registro atualizado.
573	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:36:23	modified	Registro atualizado.
574	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:36:23	modified	Registro atualizado.
575	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:36:29	modified	Registro atualizado.
576	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:36:29	modified	Registro atualizado.
577	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:36:34	modified	Registro atualizado.
578	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:36:34	modified	Registro atualizado.
579	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:36:37	modified	Registro atualizado.
580	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:36:37	modified	Registro atualizado.
581	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:37:13	modified	Registro atualizado.
582	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:37:13	modified	Registro atualizado.
583	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:37:26	modified	Registro atualizado.
584	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:37:27	modified	Registro atualizado.
585	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:37:29	modified	Registro atualizado.
586	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:37:29	modified	Registro atualizado.
587	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:37:31	modified	Registro atualizado.
588	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:37:31	modified	Registro atualizado.
589	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:37:36	modified	Registro atualizado.
590	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:37:36	modified	Registro atualizado.
591	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:38:04	modified	Registro atualizado.
592	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:38:04	modified	Registro atualizado.
593	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:38:42	modified	Registro atualizado.
594	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:38:43	modified	Registro atualizado.
595	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:38:44	modified	Registro atualizado.
596	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:38:44	modified	Registro atualizado.
597	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:38:46	modified	Registro atualizado.
598	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:38:46	modified	Registro atualizado.
599	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:38:48	modified	Registro atualizado.
600	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:38:49	modified	Registro atualizado.
601	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:38:51	modified	Registro atualizado.
602	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:38:51	modified	Registro atualizado.
603	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:39:07	modified	Registro atualizado.
604	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:39:07	modified	Registro atualizado.
605	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:39:09	modified	Registro atualizado.
606	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:39:10	modified	Registro atualizado.
607	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:39:11	modified	Registro atualizado.
608	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:39:11	modified	Registro atualizado.
609	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:39:53	modified	Registro atualizado.
610	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:39:53	modified	Registro atualizado.
611	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 19:39:56	modified	Registro atualizado.
612	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 19:39:56	modified	Registro atualizado.
613	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 21:56:07	modified	Registro atualizado.
614	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 21:56:07	modified	Registro atualizado.
615	1	2	MapasCulturais\\Entities\\Agent	2020-08-24 21:56:16	modified	Registro atualizado.
616	1	38	MapasCulturais\\Entities\\Agent	2020-08-24 21:56:16	modified	Registro atualizado.
617	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:25	modified	Registro atualizado.
618	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:25	modified	Registro atualizado.
619	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:25	modified	Registro atualizado.
620	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:25	modified	Registro atualizado.
621	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:25	modified	Registro atualizado.
622	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:26	modified	Registro atualizado.
623	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:26	modified	Registro atualizado.
624	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:26	modified	Registro atualizado.
625	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:50	modified	Registro atualizado.
626	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:50	modified	Registro atualizado.
627	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:51	modified	Registro atualizado.
628	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:51	modified	Registro atualizado.
629	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:51	modified	Registro atualizado.
630	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:51	modified	Registro atualizado.
631	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:51	modified	Registro atualizado.
632	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:51	modified	Registro atualizado.
633	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:36:55	modified	Registro atualizado.
634	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:38:08	modified	Registro atualizado.
635	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:41:33	modified	Registro atualizado.
636	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:41:47	modified	Registro atualizado.
637	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:41:47	modified	Registro atualizado.
638	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:41:54	modified	Registro atualizado.
639	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:41:55	modified	Registro atualizado.
640	4	4	MapasCulturais\\Entities\\Agent	2020-08-25 21:42:19	modified	Registro atualizado.
641	4	39	MapasCulturais\\Entities\\Agent	2020-08-25 21:42:52	created	Registro criado.
642	4	39	MapasCulturais\\Entities\\Agent	2020-08-25 21:42:52	modified	Registro atualizado.
643	5	39	MapasCulturais\\Entities\\Agent	2020-08-25 21:45:07	modified	Registro atualizado.
644	5	39	MapasCulturais\\Entities\\Agent	2020-08-25 21:45:23	modified	Registro atualizado.
645	5	39	MapasCulturais\\Entities\\Agent	2020-08-25 21:53:27	modified	Registro atualizado.
646	5	39	MapasCulturais\\Entities\\Agent	2020-08-25 21:53:28	modified	Registro atualizado.
647	5	39	MapasCulturais\\Entities\\Agent	2020-08-25 21:58:12	modified	Registro atualizado.
648	5	39	MapasCulturais\\Entities\\Agent	2020-08-25 23:50:08	modified	Registro atualizado.
649	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 01:14:40	modified	Registro atualizado.
650	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 01:14:40	modified	Registro atualizado.
651	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 01:14:52	modified	Registro atualizado.
652	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 01:33:41	modified	Registro atualizado.
653	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 01:35:52	modified	Registro atualizado.
654	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 01:42:44	modified	Registro atualizado.
655	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 01:43:00	modified	Registro atualizado.
656	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 01:43:00	modified	Registro atualizado.
657	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 01:43:09	modified	Registro atualizado.
658	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:03:01	modified	Registro atualizado.
659	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:05:17	modified	Registro atualizado.
660	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:13:03	modified	Registro atualizado.
661	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:13:15	modified	Registro atualizado.
662	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:13:42	modified	Registro atualizado.
663	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:13:42	modified	Registro atualizado.
664	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:15:26	modified	Registro atualizado.
665	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:15:27	modified	Registro atualizado.
666	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:15:34	modified	Registro atualizado.
667	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:17:57	modified	Registro atualizado.
668	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:18:26	modified	Registro atualizado.
669	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:18:30	modified	Registro atualizado.
670	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 02:18:30	modified	Registro atualizado.
671	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:54:33	modified	Registro atualizado.
672	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:54:34	modified	Registro atualizado.
673	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:54:48	modified	Registro atualizado.
674	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:54:48	modified	Registro atualizado.
675	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:55:23	modified	Registro atualizado.
676	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:55:45	modified	Registro atualizado.
677	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:55:46	modified	Registro atualizado.
678	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:57:32	modified	Registro atualizado.
679	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:57:35	modified	Registro atualizado.
680	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:57:49	modified	Registro atualizado.
681	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:57:59	modified	Registro atualizado.
682	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:58:00	modified	Registro atualizado.
683	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:58:07	modified	Registro atualizado.
684	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:58:13	modified	Registro atualizado.
685	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:58:13	modified	Registro atualizado.
686	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 03:59:08	modified	Registro atualizado.
687	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:00:51	modified	Registro atualizado.
688	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:01:53	modified	Registro atualizado.
689	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:18:56	modified	Registro atualizado.
690	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:18:56	modified	Registro atualizado.
691	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:19:05	modified	Registro atualizado.
692	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:19:05	modified	Registro atualizado.
693	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:27:51	modified	Registro atualizado.
694	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:27:52	modified	Registro atualizado.
695	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:29:35	modified	Registro atualizado.
696	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:30:31	modified	Registro atualizado.
697	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:31:46	modified	Registro atualizado.
698	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:32:42	modified	Registro atualizado.
699	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:33:15	modified	Registro atualizado.
700	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:34:43	modified	Registro atualizado.
701	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:35:00	modified	Registro atualizado.
702	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:43:22	modified	Registro atualizado.
703	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 04:45:01	modified	Registro atualizado.
704	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 05:21:12	modified	Registro atualizado.
705	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 05:21:15	modified	Registro atualizado.
706	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 05:21:18	modified	Registro atualizado.
707	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 05:21:25	modified	Registro atualizado.
708	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 05:56:46	modified	Registro atualizado.
709	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 05:56:56	modified	Registro atualizado.
710	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 05:57:53	modified	Registro atualizado.
711	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 05:58:56	modified	Registro atualizado.
712	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 05:59:09	modified	Registro atualizado.
713	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:00:36	modified	Registro atualizado.
714	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:05:28	modified	Registro atualizado.
715	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:08:19	modified	Registro atualizado.
716	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:08:41	modified	Registro atualizado.
717	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:09:02	modified	Registro atualizado.
718	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:10:21	modified	Registro atualizado.
719	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:10:30	modified	Registro atualizado.
720	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:10:45	modified	Registro atualizado.
721	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:14:06	modified	Registro atualizado.
722	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:14:51	modified	Registro atualizado.
723	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:25:00	modified	Registro atualizado.
724	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:25:12	modified	Registro atualizado.
725	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:25:28	modified	Registro atualizado.
726	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:25:47	modified	Registro atualizado.
727	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:25:57	modified	Registro atualizado.
728	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:26:36	modified	Registro atualizado.
729	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:26:43	modified	Registro atualizado.
730	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:27:28	modified	Registro atualizado.
731	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:27:44	modified	Registro atualizado.
732	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:28:05	modified	Registro atualizado.
733	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:29:05	modified	Registro atualizado.
734	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:32:14	modified	Registro atualizado.
735	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:32:18	modified	Registro atualizado.
736	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:32:34	modified	Registro atualizado.
737	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:35:37	modified	Registro atualizado.
738	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:37:07	modified	Registro atualizado.
739	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:37:23	modified	Registro atualizado.
740	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:38:54	modified	Registro atualizado.
741	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:39:19	modified	Registro atualizado.
742	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:39:53	modified	Registro atualizado.
743	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:40:17	modified	Registro atualizado.
744	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:40:28	modified	Registro atualizado.
745	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:43:21	modified	Registro atualizado.
746	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:44:20	modified	Registro atualizado.
747	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:48:30	modified	Registro atualizado.
748	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:50:13	modified	Registro atualizado.
749	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:51:31	modified	Registro atualizado.
750	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:52:48	modified	Registro atualizado.
751	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 06:52:56	modified	Registro atualizado.
752	6	40	MapasCulturais\\Entities\\Agent	2020-08-26 07:06:58	created	Registro criado.
753	6	40	MapasCulturais\\Entities\\Agent	2020-08-26 07:06:58	modified	Registro atualizado.
754	6	40	MapasCulturais\\Entities\\Agent	2020-08-26 07:07:04	modified	Registro atualizado.
755	6	40	MapasCulturais\\Entities\\Agent	2020-08-26 07:07:59	modified	Registro atualizado.
756	6	40	MapasCulturais\\Entities\\Agent	2020-08-26 07:09:30	modified	Registro atualizado.
757	6	40	MapasCulturais\\Entities\\Agent	2020-08-26 07:09:37	modified	Registro atualizado.
758	6	40	MapasCulturais\\Entities\\Agent	2020-08-26 07:14:32	modified	Registro atualizado.
759	6	40	MapasCulturais\\Entities\\Agent	2020-08-26 07:14:36	modified	Registro atualizado.
760	7	41	MapasCulturais\\Entities\\Agent	2020-08-26 07:15:10	created	Registro criado.
761	7	41	MapasCulturais\\Entities\\Agent	2020-08-26 07:15:10	modified	Registro atualizado.
762	7	41	MapasCulturais\\Entities\\Agent	2020-08-26 07:15:24	modified	Registro atualizado.
763	7	41	MapasCulturais\\Entities\\Agent	2020-08-26 07:16:41	modified	Registro atualizado.
764	7	41	MapasCulturais\\Entities\\Agent	2020-08-26 07:19:09	modified	Registro atualizado.
765	7	41	MapasCulturais\\Entities\\Agent	2020-08-26 07:19:37	modified	Registro atualizado.
766	7	41	MapasCulturais\\Entities\\Agent	2020-08-26 07:19:46	modified	Registro atualizado.
767	7	41	MapasCulturais\\Entities\\Agent	2020-08-26 07:19:48	modified	Registro atualizado.
768	7	41	MapasCulturais\\Entities\\Agent	2020-08-26 07:19:49	modified	Registro atualizado.
769	7	41	MapasCulturais\\Entities\\Agent	2020-08-26 07:19:57	modified	Registro atualizado.
770	7	41	MapasCulturais\\Entities\\Agent	2020-08-26 07:20:13	modified	Registro atualizado.
771	8	42	MapasCulturais\\Entities\\Agent	2020-08-26 07:23:01	created	Registro criado.
772	8	42	MapasCulturais\\Entities\\Agent	2020-08-26 07:23:01	modified	Registro atualizado.
773	8	42	MapasCulturais\\Entities\\Agent	2020-08-26 07:23:05	modified	Registro atualizado.
774	8	42	MapasCulturais\\Entities\\Agent	2020-08-26 07:27:24	modified	Registro atualizado.
775	8	42	MapasCulturais\\Entities\\Agent	2020-08-26 07:27:28	modified	Registro atualizado.
776	8	42	MapasCulturais\\Entities\\Agent	2020-08-26 07:36:38	modified	Registro atualizado.
777	8	42	MapasCulturais\\Entities\\Agent	2020-08-26 07:36:42	modified	Registro atualizado.
778	8	42	MapasCulturais\\Entities\\Agent	2020-08-26 07:41:25	modified	Registro atualizado.
779	8	42	MapasCulturais\\Entities\\Agent	2020-08-26 07:42:23	modified	Registro atualizado.
780	8	42	MapasCulturais\\Entities\\Agent	2020-08-26 07:42:30	modified	Registro atualizado.
781	9	43	MapasCulturais\\Entities\\Agent	2020-08-26 07:42:57	created	Registro criado.
782	9	43	MapasCulturais\\Entities\\Agent	2020-08-26 07:42:58	modified	Registro atualizado.
783	9	43	MapasCulturais\\Entities\\Agent	2020-08-26 07:43:01	modified	Registro atualizado.
784	9	43	MapasCulturais\\Entities\\Agent	2020-08-26 07:43:32	modified	Registro atualizado.
785	9	43	MapasCulturais\\Entities\\Agent	2020-08-26 07:43:53	modified	Registro atualizado.
786	10	44	MapasCulturais\\Entities\\Agent	2020-08-26 07:44:46	created	Registro criado.
787	10	44	MapasCulturais\\Entities\\Agent	2020-08-26 07:44:46	modified	Registro atualizado.
788	10	44	MapasCulturais\\Entities\\Agent	2020-08-26 07:44:55	modified	Registro atualizado.
789	10	44	MapasCulturais\\Entities\\Agent	2020-08-26 07:47:09	modified	Registro atualizado.
790	10	44	MapasCulturais\\Entities\\Agent	2020-08-26 07:47:19	modified	Registro atualizado.
791	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:47:45	created	Registro criado.
792	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:47:45	modified	Registro atualizado.
793	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:47:49	modified	Registro atualizado.
794	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:48:14	modified	Registro atualizado.
795	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:48:26	modified	Registro atualizado.
796	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:48:33	modified	Registro atualizado.
797	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:48:34	modified	Registro atualizado.
798	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:48:48	modified	Registro atualizado.
799	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:48:50	modified	Registro atualizado.
800	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:48:56	modified	Registro atualizado.
801	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:49:04	modified	Registro atualizado.
802	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:49:07	modified	Registro atualizado.
803	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:49:08	modified	Registro atualizado.
804	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:49:12	modified	Registro atualizado.
805	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:50:19	modified	Registro atualizado.
806	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:58:44	modified	Registro atualizado.
807	11	45	MapasCulturais\\Entities\\Agent	2020-08-26 07:58:54	modified	Registro atualizado.
808	5	39	MapasCulturais\\Entities\\Agent	2020-08-26 20:13:48	modified	Registro atualizado.
809	4	4	MapasCulturais\\Entities\\Agent	2020-08-26 22:44:47	modified	Registro atualizado.
810	4	4	MapasCulturais\\Entities\\Agent	2020-08-26 22:44:48	modified	Registro atualizado.
811	4	4	MapasCulturais\\Entities\\Agent	2020-08-26 22:44:59	modified	Registro atualizado.
812	12	46	MapasCulturais\\Entities\\Agent	2020-08-27 13:25:49	created	Registro criado.
813	12	46	MapasCulturais\\Entities\\Agent	2020-08-27 13:25:50	modified	Registro atualizado.
814	12	46	MapasCulturais\\Entities\\Agent	2020-08-27 13:25:54	modified	Registro atualizado.
\.


--
-- Data for Name: entity_revision_data; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.entity_revision_data (id, "timestamp", key, value) FROM stdin;
1	2019-03-07 23:54:19	_type	1
2	2019-03-07 23:54:19	name	"Admin@local"
3	2019-03-07 23:54:19	publicLocation	null
4	2019-03-07 23:54:19	location	{"latitude":0,"longitude":0}
5	2019-03-07 23:54:19	shortDescription	null
6	2019-03-07 23:54:19	longDescription	null
7	2019-03-07 23:54:19	createTimestamp	{"date":"2019-03-07 00:00:00.000000","timezone_type":3,"timezone":"UTC"}
8	2019-03-07 23:54:19	status	1
9	2019-03-07 23:54:19	updateTimestamp	{"date":"2019-03-07 00:00:00.000000","timezone_type":3,"timezone":"UTC"}
10	2019-03-07 23:54:19	_subsiteId	null
11	2020-08-05 12:54:05	publicLocation	false
12	2020-08-05 12:54:05	location	{"latitude":"0","longitude":"0"}
13	2020-08-05 12:54:05	shortDescription	"asd asd asd asd "
14	2020-08-05 12:54:05	longDescription	""
15	2020-08-05 12:54:05	updateTimestamp	{"date":"2020-08-05 12:54:05.000000","timezone_type":3,"timezone":"UTC"}
16	2020-08-05 12:54:05	dataDeNascimento	"2004-07-01"
17	2020-08-05 12:54:05	_terms	{"":["Arquitetura-Urbanismo"]}
18	2020-08-05 12:54:05	_seals	[{"id":1,"name":"Selo Mapas","revision":0}]
19	2020-08-15 22:06:30	_type	1
20	2020-08-15 22:06:30	name	"Rafael Freitas"
21	2020-08-15 22:06:30	publicLocation	false
22	2020-08-15 22:06:30	location	{"latitude":0,"longitude":0}
23	2020-08-15 22:06:30	shortDescription	null
24	2020-08-15 22:06:30	longDescription	null
25	2020-08-15 22:06:30	createTimestamp	{"date":"2020-08-15 22:06:30.106046","timezone_type":3,"timezone":"UTC"}
26	2020-08-15 22:06:30	status	1
27	2020-08-15 22:06:30	updateTimestamp	null
28	2020-08-15 22:06:30	_subsiteId	null
29	2020-08-15 22:06:30	location	{"latitude":"0","longitude":"0"}
30	2020-08-15 22:06:30	createTimestamp	{"date":"2020-08-15 22:06:30.000000","timezone_type":3,"timezone":"UTC"}
31	2020-08-15 22:20:53	aldirblanc_inciso1_registration	"971249312"
32	2020-08-17 19:58:02	aldirblanc_inciso1_registration	"1926833684"
33	2020-08-18 03:31:31	aldirblanc_inciso1_registration	"735327624"
34	2020-08-18 05:02:28	documento	"05091300970"
35	2020-08-18 05:12:06	documento	"3212323123123123123"
36	2020-08-18 05:16:00	documento	"321.233.231-23"
37	2020-08-18 05:44:55	genero	"Mulher Trans\\/Travesti."
38	2020-08-18 06:04:34	dataDeNascimento	"2020-08-13"
39	2020-08-18 06:05:48	dataDeNascimento	"2020-08-05"
40	2020-08-18 06:23:36	nomeCompleto	"Rafael Chaves Freitas"
41	2020-08-18 07:02:36	raca	"Parda."
42	2020-08-18 18:56:09	documento	"323.232.312-31"
43	2020-08-18 18:56:09	name	""
44	2020-08-18 18:56:09	updateTimestamp	{"date":"2020-08-18 18:56:09.000000","timezone_type":3,"timezone":"UTC"}
45	2020-08-18 18:56:09	nomeCompleto	""
46	2020-08-18 18:56:09	genero	""
47	2020-08-18 18:56:10	raca	""
48	2020-08-18 18:58:31	raca	"Branca."
49	2020-08-18 19:00:59	raca	"Ind\\u00edgena."
50	2020-08-18 19:03:24	nomeCompleto	"Rafael Chaves Freitas"
51	2020-08-18 19:04:23	dataDeNascimento	"2020-08-26"
52	2020-08-18 19:05:26	genero	"Mulher Trans\\/Travesti."
53	2020-08-18 19:07:45	name	"Rafael"
54	2020-08-18 19:07:45	shortDescription	"asda sda sd asd asd "
55	2020-08-18 19:07:45	longDescription	""
56	2020-08-18 19:07:45	updateTimestamp	{"date":"2020-08-18 19:07:45.000000","timezone_type":3,"timezone":"UTC"}
57	2020-08-18 19:07:45	_terms	{"":["Arte de Rua","Arquitetura-Urbanismo"]}
58	2020-08-18 23:38:50	name	"Rafael Freitas"
59	2020-08-18 23:38:50	updateTimestamp	{"date":"2020-08-18 23:38:50.000000","timezone_type":3,"timezone":"UTC"}
60	2020-08-18 23:47:19	emailPrivado	"rafael@hacklab.com.br"
61	2020-08-19 20:11:06	aldirblanc_inciso1_registration	"1731020007"
62	2020-08-19 20:14:15	documento	"050.913.009-70"
63	2020-08-19 20:14:15	name	""
64	2020-08-19 20:14:15	updateTimestamp	{"date":"2020-08-19 20:14:15.000000","timezone_type":3,"timezone":"UTC"}
65	2020-08-19 20:15:29	nomeCompleto	"Rafael Chaves Freitas"
66	2020-08-19 20:16:01	dataDeNascimento	"2020-08-05"
67	2020-08-19 20:16:12	telefone1	"11 991123321"
68	2020-08-19 20:16:20	telefone1	""
69	2020-08-19 20:16:27	telefone1	"11 93322-12332"
70	2020-08-19 20:16:45	emailPrivado	"rafael@hacklab.com.br"
71	2020-08-19 20:17:09	genero	"Homem Trans."
72	2020-08-19 20:17:19	raca	"Amarela."
73	2020-08-19 20:25:26	name	"teste"
74	2020-08-19 20:25:26	shortDescription	"asd asd asd asd"
75	2020-08-19 20:25:26	updateTimestamp	{"date":"2020-08-19 20:25:26.000000","timezone_type":3,"timezone":"UTC"}
76	2020-08-19 20:25:26	telefone1	"(11) 9332-2123"
77	2020-08-19 20:32:09	nomeCompleto	"Rafael Chaves Freitas asd asd "
78	2020-08-19 20:42:28	telefone2	"(11) 1234-1233"
79	2020-08-19 20:47:19	documento	""
80	2020-08-19 20:47:20	name	"Rafael Freitas"
81	2020-08-19 20:47:20	updateTimestamp	{"date":"2020-08-19 20:47:20.000000","timezone_type":3,"timezone":"UTC"}
82	2020-08-19 20:47:45	documento	"123.123.123-12"
83	2020-08-19 20:47:45	name	"Rafael Freitas asdasd"
84	2020-08-19 20:47:45	updateTimestamp	{"date":"2020-08-19 20:47:45.000000","timezone_type":3,"timezone":"UTC"}
85	2020-08-19 20:48:05	nomeCompleto	"Rafael Chaves Freitas"
86	2020-08-19 20:48:24	documento	"123.123.123"
87	2020-08-19 20:48:25	name	"Rafael Freitas"
88	2020-08-19 20:48:25	updateTimestamp	{"date":"2020-08-19 20:48:25.000000","timezone_type":3,"timezone":"UTC"}
89	2020-08-19 20:49:44	documento	"123.123.123-33"
90	2020-08-19 20:49:44	name	"Rafael"
91	2020-08-19 20:49:44	updateTimestamp	{"date":"2020-08-19 20:49:44.000000","timezone_type":3,"timezone":"UTC"}
92	2020-08-19 20:50:30	dataDeNascimento	"2020-08-20"
93	2020-08-19 20:51:00	dataDeNascimento	"2020-08-07"
94	2020-08-19 20:51:10	documento	"123.123.123"
95	2020-08-19 20:51:10	name	"Rafa"
96	2020-08-19 20:51:10	updateTimestamp	{"date":"2020-08-19 20:51:10.000000","timezone_type":3,"timezone":"UTC"}
97	2020-08-19 20:52:55	nomeCompleto	"Rafael Chaves"
98	2020-08-19 20:53:11	nomeCompleto	"Rafael Chaves Freitas"
99	2020-08-20 23:22:39	nomeCompleto	"Rafael Chaves"
100	2020-08-20 23:28:10	_type	1
101	2020-08-20 23:28:10	name	"Teste 1"
102	2020-08-20 23:28:10	publicLocation	false
103	2020-08-20 23:28:10	location	{"latitude":0,"longitude":0}
104	2020-08-20 23:28:10	shortDescription	null
105	2020-08-20 23:28:10	longDescription	null
106	2020-08-20 23:28:10	createTimestamp	{"date":"2020-08-20 23:28:10.464215","timezone_type":3,"timezone":"UTC"}
107	2020-08-20 23:28:10	status	1
108	2020-08-20 23:28:10	updateTimestamp	null
109	2020-08-20 23:28:10	_subsiteId	null
110	2020-08-20 23:28:10	location	{"latitude":"0","longitude":"0"}
111	2020-08-20 23:28:10	createTimestamp	{"date":"2020-08-20 23:28:10.000000","timezone_type":3,"timezone":"UTC"}
112	2020-08-20 23:28:25	aldirblanc_inciso1_registration	"792482838"
113	2020-08-20 23:29:10	documento	"050.913.009-70"
114	2020-08-20 23:29:10	shortDescription	""
115	2020-08-20 23:29:10	updateTimestamp	{"date":"2020-08-20 23:29:10.000000","timezone_type":3,"timezone":"UTC"}
116	2020-08-20 23:36:16	nomeCompleto	"Rafael Chaves"
117	2020-08-20 23:36:58	dataDeNascimento	"1981-09-30"
118	2020-08-20 23:37:27	telefone1	"(11) 964655828"
119	2020-08-21 01:07:13	documento	"123.321.123-12"
120	2020-08-21 04:37:05	documento	""
121	2020-08-21 04:37:05	raca	""
122	2020-08-21 04:37:40	documento	"050.913.009-70"
123	2020-08-21 04:39:06	nomeCompleto	"Rafael Chaves"
124	2020-08-21 04:39:06	shortDescription	"Rafael Freitas"
125	2020-08-21 04:39:06	updateTimestamp	{"date":"2020-08-21 04:39:06.000000","timezone_type":3,"timezone":"UTC"}
126	2020-08-21 04:39:06	documento	"050.913.009-70"
127	2020-08-21 04:39:26	dataDeNascimento	"1981-09-30"
128	2020-08-21 05:43:36	En_CEP	"01232-12"
129	2020-08-21 05:46:47	En_Nome_Logradouro	"Pra\\u00e7a Japu\\u00e1"
130	2020-08-21 05:46:47	En_Num	"35"
131	2020-08-21 05:47:25	En_Complemento	"apto 91A"
132	2020-08-21 05:47:49	En_Bairro	"Bila Madalena"
133	2020-08-21 05:47:49	En_Municipio	"S\\u00e3o Paulo"
134	2020-08-21 05:56:49	genero	"N\\u00e3o-Bin\\u00e1rie\\/Outra variabilidade."
135	2020-08-21 05:57:03	dataDeNascimento	"2020-08-13"
136	2020-08-21 05:57:14	dataDeNascimento	"2020-08-3"
137	2020-08-21 06:11:49	En_Nome_Logradouro	""
138	2020-08-21 06:12:35	En_Nome_Logradouro	"asd asd"
139	2020-08-21 06:12:38	En_Nome_Logradouro	""
140	2020-08-21 06:29:11	telefone1	"11 12321231"
141	2020-08-21 06:29:11	dataDeNascimento	"2020-08-26"
142	2020-08-21 06:57:35	genero	""
143	2020-08-21 06:58:39	En_CEP	"12332-12"
144	2020-08-21 07:01:32	_type	1
145	2020-08-21 07:01:32	name	"Rafa Chaves"
146	2020-08-21 07:01:32	publicLocation	false
147	2020-08-21 07:01:32	location	{"latitude":0,"longitude":0}
148	2020-08-21 07:01:32	shortDescription	null
149	2020-08-21 07:01:32	longDescription	null
150	2020-08-21 07:01:32	createTimestamp	{"date":"2020-08-21 07:01:32.173039","timezone_type":3,"timezone":"UTC"}
151	2020-08-21 07:01:32	status	1
152	2020-08-21 07:01:32	updateTimestamp	null
153	2020-08-21 07:01:32	_subsiteId	null
154	2020-08-21 07:01:32	location	{"latitude":"0","longitude":"0"}
155	2020-08-21 07:01:32	createTimestamp	{"date":"2020-08-21 07:01:32.000000","timezone_type":3,"timezone":"UTC"}
156	2020-08-21 07:01:37	aldirblanc_inciso1_registration	"1020199467"
157	2020-08-21 07:02:01	documento	"050.913.009-70"
158	2020-08-21 07:02:02	shortDescription	""
159	2020-08-21 07:02:02	updateTimestamp	{"date":"2020-08-21 07:02:02.000000","timezone_type":3,"timezone":"UTC"}
160	2020-08-21 07:02:55	nomeCompleto	"Rafael Chaves"
161	2020-08-21 07:16:24	nomeCompleto	"Rafael Chaves asd asd"
162	2020-08-21 07:16:24	shortDescription	"RAFA"
163	2020-08-21 07:16:24	updateTimestamp	{"date":"2020-08-21 07:16:24.000000","timezone_type":3,"timezone":"UTC"}
164	2020-08-21 07:17:37	documento	"050.913.009-79"
165	2020-08-21 18:28:28	documento	"050.913.009-7"
166	2020-08-21 18:28:46	documento	"050.913.009-70"
167	2020-08-21 18:31:08	documento	"050.913.009-78"
168	2020-08-21 18:33:23	documento	"050.913.009-90"
169	2020-08-21 18:36:30	dataDeNascimento	"2020-08-13"
170	2020-08-21 18:40:26	longDescription	""
171	2020-08-21 18:40:26	updateTimestamp	{"date":"2020-08-21 18:40:26.000000","timezone_type":3,"timezone":"UTC"}
172	2020-08-21 18:40:26	_terms	{"":["Arquivo","Arquitetura-Urbanismo"]}
173	2020-08-22 00:39:27	genero	"Homem Transexual"
174	2020-08-22 00:39:27	name	""
175	2020-08-22 00:39:27	updateTimestamp	{"date":"2020-08-22 00:39:27.000000","timezone_type":3,"timezone":"UTC"}
176	2020-08-22 00:39:28	raca	""
177	2020-08-22 00:39:50	raca	"Branca"
178	2020-08-22 00:42:17	name	"rafael"
179	2020-08-22 00:42:17	updateTimestamp	{"date":"2020-08-22 00:42:17.000000","timezone_type":3,"timezone":"UTC"}
180	2020-08-22 00:42:21	name	"hacla"
181	2020-08-22 00:42:21	updateTimestamp	{"date":"2020-08-22 00:42:21.000000","timezone_type":3,"timezone":"UTC"}
182	2020-08-22 00:42:22	name	"hacklab"
183	2020-08-22 00:42:22	updateTimestamp	{"date":"2020-08-22 00:42:22.000000","timezone_type":3,"timezone":"UTC"}
184	2020-08-22 00:42:28	name	"hacklab\\/ servi\\u00e7os de tecnologia"
185	2020-08-22 00:42:28	updateTimestamp	{"date":"2020-08-22 00:42:28.000000","timezone_type":3,"timezone":"UTC"}
186	2020-08-22 05:01:47	En_CEP	"0122001"
187	2020-08-22 05:01:47	name	""
188	2020-08-22 05:01:47	updateTimestamp	{"date":"2020-08-22 05:01:47.000000","timezone_type":3,"timezone":"UTC"}
189	2020-08-22 05:01:50	En_CEP	"01220-01"
190	2020-08-22 05:09:39	En_CEP	"01220-02"
191	2020-08-22 05:12:12	En_CEP	"01220-"
192	2020-08-22 05:12:34	En_CEP	"01220-2"
193	2020-08-22 05:12:47	En_CEP	"01220-01"
194	2020-08-22 05:15:28	En_CEP	"01220-10"
195	2020-08-22 05:15:41	En_CEP	"01220-01"
196	2020-08-22 05:16:14	En_CEP	"054530"
197	2020-08-22 05:16:21	En_CEP	"05453-06"
198	2020-08-22 05:17:50	En_CEP	"05453-060"
199	2020-08-22 05:18:34	En_CEP	"01220-010"
200	2020-08-22 05:19:04	En_CEP	"01220-01"
201	2020-08-22 05:19:05	En_CEP	"01220-010"
202	2020-08-22 05:19:16	En_CEP	"01220-011"
203	2020-08-22 05:19:21	En_CEP	"01220-010"
204	2020-08-22 05:19:49	En_CEP	"05453-060"
205	2020-08-22 05:20:10	En_CEP	"05453-06"
206	2020-08-22 05:20:19	En_CEP	"05453-062"
207	2020-08-22 05:20:23	En_CEP	"05453-060"
208	2020-08-22 05:20:56	En_CEP	"0"
209	2020-08-22 05:20:59	En_CEP	"050"
210	2020-08-22 05:21:08	En_CEP	"05453-060"
211	2020-08-22 05:24:41	En_CEP	"05453-06"
212	2020-08-22 05:24:48	En_CEP	"05453-060"
213	2020-08-22 05:25:05	En_CEP	"054"
214	2020-08-22 05:25:05	En_Nome_Logradouro	"asdasd"
215	2020-08-22 05:25:05	En_Num	"asd"
216	2020-08-22 05:25:05	En_Complemento	"asd"
217	2020-08-22 05:27:00	En_CEP	"05453-060"
218	2020-08-22 05:27:35	En_CEP	"0"
219	2020-08-22 05:27:44	En_CEP	"05453-060"
220	2020-08-22 05:27:54	En_CEP	"01220-010"
221	2020-08-22 05:29:20	En_CEP	"01220-060"
222	2020-08-22 05:29:28	En_CEP	"01220-001"
223	2020-08-22 05:29:42	En_CEP	"01220-010"
224	2020-08-22 05:31:58	En_CEP	"01220-011"
225	2020-08-22 06:26:08	En_CEP	"88035-001"
226	2020-08-22 06:26:53	En_CEP	""
227	2020-08-22 06:26:57	En_CEP	"88035-001"
228	2020-08-22 06:32:36	En_CEP	""
229	2020-08-22 06:32:38	En_CEP	"03500"
230	2020-08-22 06:32:42	En_CEP	"88035-001"
231	2020-08-22 06:36:16	En_CEP	"32112-332"
232	2020-08-22 06:36:43	En_CEP	"01220-010"
233	2020-08-22 06:47:20	En_CEP	"01220-01"
234	2020-08-22 06:47:24	En_CEP	"01220-010"
235	2020-08-22 06:47:46	En_CEP	"05453-060"
236	2020-08-22 06:48:43	En_CEP	"010"
237	2020-08-22 06:48:47	En_CEP	"01220-010"
238	2020-08-22 06:48:57	En_CEP	"88035-001"
239	2020-08-22 06:49:21	En_Num	""
240	2020-08-22 06:49:24	En_Complemento	""
241	2020-08-22 06:52:05	En_CEP	"01220-010"
242	2020-08-22 06:52:13	En_Nome_Logradouro	"Rua Rego Freitas"
243	2020-08-22 06:52:24	En_Nome_Logradouro	""
244	2020-08-22 06:52:58	En_Municipio	"S\\u00e3o Paul"
245	2020-08-22 06:53:00	En_Municipio	"S\\u00e3o Paulo"
246	2020-08-22 06:57:56	En_CEP	"01220-011"
247	2020-08-22 06:57:59	En_CEP	"01220-010"
248	2020-08-22 06:58:00	En_Nome_Logradouro	"Rua Rego Freitas"
249	2020-08-22 06:58:00	En_Bairro	"Rep\\u00fablica"
250	2020-08-22 06:58:23	En_CEP	"05453-060"
251	2020-08-22 06:58:24	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
252	2020-08-22 06:58:24	En_Bairro	"Vila Madalena"
253	2020-08-22 06:58:47	En_CEP	"88035-001"
254	2020-08-22 06:58:48	En_Municipio	"Florian\\u00f3polis"
255	2020-08-22 06:58:48	En_Nome_Logradouro	"Avenida Madre Benvenuta"
256	2020-08-22 06:58:48	En_Bairro	"Santa M\\u00f4nica"
257	2020-08-22 07:05:13	genero	"Mulher Transexual"
258	2020-08-22 07:05:21	name	"Rafael Chaves"
259	2020-08-22 07:05:21	updateTimestamp	{"date":"2020-08-22 07:05:21.000000","timezone_type":3,"timezone":"UTC"}
260	2020-08-22 07:05:26	raca	"Branca"
261	2020-08-22 07:05:42	name	"Rafael Chavesd"
262	2020-08-22 07:05:42	updateTimestamp	{"date":"2020-08-22 07:05:42.000000","timezone_type":3,"timezone":"UTC"}
263	2020-08-22 07:05:56	name	"Rafael Chaves"
264	2020-08-22 07:05:56	updateTimestamp	{"date":"2020-08-22 07:05:56.000000","timezone_type":3,"timezone":"UTC"}
265	2020-08-23 21:42:44	En_CEP	"88035-000"
266	2020-08-23 22:45:02	En_CEP	"88035-001"
267	2020-08-23 22:45:51	En_CEP	"88035-000"
268	2020-08-23 22:49:35	En_CEP	"88035-001"
269	2020-08-23 22:50:36	En_CEP	"88035-000"
270	2020-08-23 22:50:37	location	{"latitude":"-27.597","longitude":"-48.5411803341"}
271	2020-08-23 22:50:37	updateTimestamp	{"date":"2020-08-23 22:50:37.000000","timezone_type":3,"timezone":"UTC"}
272	2020-08-23 22:51:06	updateTimestamp	{"date":"2020-08-23 22:51:06.000000","timezone_type":3,"timezone":"UTC"}
273	2020-08-23 22:51:06	En_CEP	"88035-001"
274	2020-08-23 22:51:07	location	{"latitude":"-27.6039300012","longitude":"-48.5411803391"}
275	2020-08-23 22:51:07	updateTimestamp	{"date":"2020-08-23 22:51:07.000000","timezone_type":3,"timezone":"UTC"}
276	2020-08-24 00:16:18	En_Num	"1502"
277	2020-08-24 00:16:54	En_Num	"1500"
278	2020-08-24 00:18:49	En_Num	"1502"
279	2020-08-24 00:19:16	En_Num	"1500"
280	2020-08-24 00:21:30	En_Num	"1502"
281	2020-08-24 00:22:49	En_Num	"1500"
282	2020-08-24 00:23:24	En_Num	"1502"
283	2020-08-24 00:24:15	En_Num	"1500"
284	2020-08-24 00:24:40	En_Num	"1502"
285	2020-08-24 00:26:28	En_CEP	"88035-000"
286	2020-08-24 00:26:29	location	{"latitude":"-27.597","longitude":"-48.5411803341"}
287	2020-08-24 00:26:29	updateTimestamp	{"date":"2020-08-24 00:26:29.000000","timezone_type":3,"timezone":"UTC"}
288	2020-08-24 00:26:29	En_Estado	"SC"
289	2020-08-24 00:26:39	updateTimestamp	{"date":"2020-08-24 00:26:39.000000","timezone_type":3,"timezone":"UTC"}
290	2020-08-24 00:26:39	En_Num	"1500"
291	2020-08-24 00:27:23	En_Num	"1502"
292	2020-08-24 00:44:38	updateTimestamp	{"date":"2020-08-24 00:44:38.000000","timezone_type":3,"timezone":"UTC"}
293	2020-08-24 00:44:38	En_Num	"1500"
294	2020-08-24 00:45:50	updateTimestamp	{"date":"2020-08-24 00:45:50.000000","timezone_type":3,"timezone":"UTC"}
295	2020-08-24 00:45:50	En_Num	"1502"
296	2020-08-24 00:45:51	location	{"latitude":"-27.5973002","longitude":"-48.5496098"}
297	2020-08-24 00:45:51	updateTimestamp	{"date":"2020-08-24 00:45:51.000000","timezone_type":3,"timezone":"UTC"}
298	2020-08-24 00:46:50	updateTimestamp	{"date":"2020-08-24 00:46:50.000000","timezone_type":3,"timezone":"UTC"}
299	2020-08-24 00:46:50	En_CEP	"88035-001"
300	2020-08-24 00:46:51	location	{"latitude":"-27.6039300012","longitude":"-48.5411803391"}
301	2020-08-24 00:46:51	updateTimestamp	{"date":"2020-08-24 00:46:51.000000","timezone_type":3,"timezone":"UTC"}
1133	2020-08-24 18:16:49	En_CEP	"01220-010"
302	2020-08-24 00:49:38	updateTimestamp	{"date":"2020-08-24 00:49:38.000000","timezone_type":3,"timezone":"UTC"}
303	2020-08-24 00:49:38	En_CEP	"88035-000"
304	2020-08-24 00:49:40	location	{"latitude":"-27.597","longitude":"-48.5411803341"}
305	2020-08-24 00:49:40	updateTimestamp	{"date":"2020-08-24 00:49:40.000000","timezone_type":3,"timezone":"UTC"}
306	2020-08-24 00:49:40	En_Num	"1500"
307	2020-08-24 00:49:56	updateTimestamp	{"date":"2020-08-24 00:49:56.000000","timezone_type":3,"timezone":"UTC"}
308	2020-08-24 00:49:56	En_Num	"200"
309	2020-08-24 00:50:20	updateTimestamp	{"date":"2020-08-24 00:50:20.000000","timezone_type":3,"timezone":"UTC"}
310	2020-08-24 00:50:20	En_Num	"2000"
311	2020-08-24 00:51:08	updateTimestamp	{"date":"2020-08-24 00:51:08.000000","timezone_type":3,"timezone":"UTC"}
312	2020-08-24 00:51:08	En_Num	"1502"
313	2020-08-24 00:51:11	location	{"latitude":"-27.5973002","longitude":"-48.5496098"}
314	2020-08-24 00:51:11	updateTimestamp	{"date":"2020-08-24 00:51:11.000000","timezone_type":3,"timezone":"UTC"}
315	2020-08-24 00:51:55	updateTimestamp	{"date":"2020-08-24 00:51:54.000000","timezone_type":3,"timezone":"UTC"}
316	2020-08-24 00:51:55	En_CEP	"88035-001"
317	2020-08-24 00:51:56	location	{"latitude":"-27.6039300012","longitude":"-48.5411803391"}
318	2020-08-24 00:51:56	updateTimestamp	{"date":"2020-08-24 00:51:56.000000","timezone_type":3,"timezone":"UTC"}
319	2020-08-24 00:52:03	updateTimestamp	{"date":"2020-08-24 00:52:03.000000","timezone_type":3,"timezone":"UTC"}
320	2020-08-24 00:52:03	En_CEP	"01220-010"
321	2020-08-24 00:52:05	location	{"latitude":"-23.555110006","longitude":"-46.6282441293"}
322	2020-08-24 00:52:05	updateTimestamp	{"date":"2020-08-24 00:52:05.000000","timezone_type":3,"timezone":"UTC"}
323	2020-08-24 00:52:05	En_Municipio	"S\\u00e3o Paulo"
324	2020-08-24 00:52:05	En_Nome_Logradouro	"Rua Rego Freitas"
325	2020-08-24 00:52:05	En_Bairro	"Rep\\u00fablica"
326	2020-08-24 00:52:05	En_Estado	"SP"
327	2020-08-24 00:52:07	updateTimestamp	{"date":"2020-08-24 00:52:07.000000","timezone_type":3,"timezone":"UTC"}
328	2020-08-24 00:52:07	En_Num	"530"
329	2020-08-24 00:52:09	location	{"latitude":"-23.5506507","longitude":"-46.6333824"}
330	2020-08-24 00:52:09	updateTimestamp	{"date":"2020-08-24 00:52:09.000000","timezone_type":3,"timezone":"UTC"}
331	2020-08-24 00:58:46	updateTimestamp	{"date":"2020-08-24 00:58:46.000000","timezone_type":3,"timezone":"UTC"}
332	2020-08-24 00:58:46	En_Num	"531"
333	2020-08-24 00:59:23	updateTimestamp	{"date":"2020-08-24 00:59:23.000000","timezone_type":3,"timezone":"UTC"}
334	2020-08-24 00:59:23	En_Num	"530"
335	2020-08-24 01:13:37	updateTimestamp	{"date":"2020-08-24 01:13:37.000000","timezone_type":3,"timezone":"UTC"}
336	2020-08-24 01:13:37	En_Num	"500"
337	2020-08-24 01:13:40	location	{"latitude":"-23.5463107","longitude":"-46.6467397"}
338	2020-08-24 01:13:40	updateTimestamp	{"date":"2020-08-24 01:13:40.000000","timezone_type":3,"timezone":"UTC"}
339	2020-08-24 01:13:42	updateTimestamp	{"date":"2020-08-24 01:13:42.000000","timezone_type":3,"timezone":"UTC"}
340	2020-08-24 01:13:42	En_Num	"530"
341	2020-08-24 01:13:46	location	{"latitude":"-23.5465762","longitude":"-46.6467484"}
342	2020-08-24 01:13:46	updateTimestamp	{"date":"2020-08-24 01:13:46.000000","timezone_type":3,"timezone":"UTC"}
343	2020-08-24 01:23:56	updateTimestamp	{"date":"2020-08-24 01:23:56.000000","timezone_type":3,"timezone":"UTC"}
344	2020-08-24 01:23:56	En_CEP	"05453-060"
345	2020-08-24 01:23:58	updateTimestamp	{"date":"2020-08-24 01:23:58.000000","timezone_type":3,"timezone":"UTC"}
346	2020-08-24 01:23:58	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
347	2020-08-24 01:23:58	En_Bairro	"Vila Madalena"
348	2020-08-24 01:24:00	updateTimestamp	{"date":"2020-08-24 01:24:00.000000","timezone_type":3,"timezone":"UTC"}
349	2020-08-24 01:24:00	En_Num	"35"
350	2020-08-24 01:25:19	updateTimestamp	{"date":"2020-08-24 01:25:19.000000","timezone_type":3,"timezone":"UTC"}
351	2020-08-24 01:25:19	En_CEP	"88035-001"
352	2020-08-24 01:25:36	updateTimestamp	{"date":"2020-08-24 01:25:36.000000","timezone_type":3,"timezone":"UTC"}
353	2020-08-24 01:25:55	updateTimestamp	{"date":"2020-08-24 01:25:55.000000","timezone_type":3,"timezone":"UTC"}
354	2020-08-24 01:25:55	En_CEP	"88035-000"
355	2020-08-24 01:26:39	updateTimestamp	{"date":"2020-08-24 01:26:39.000000","timezone_type":3,"timezone":"UTC"}
356	2020-08-24 01:26:39	En_CEP	"88035-001"
357	2020-08-24 01:26:40	updateTimestamp	{"date":"2020-08-24 01:26:40.000000","timezone_type":3,"timezone":"UTC"}
358	2020-08-24 01:26:40	En_Municipio	"Florian\\u00f3polis"
359	2020-08-24 01:26:40	En_Estado	"SC"
360	2020-08-24 01:26:40	En_Nome_Logradouro	"Avenida Madre Benvenuta"
361	2020-08-24 01:26:40	En_Bairro	"Santa M\\u00f4nica"
362	2020-08-24 01:27:05	updateTimestamp	{"date":"2020-08-24 01:27:05.000000","timezone_type":3,"timezone":"UTC"}
363	2020-08-24 01:27:05	En_CEP	"88035-00"
364	2020-08-24 01:27:08	updateTimestamp	{"date":"2020-08-24 01:27:08.000000","timezone_type":3,"timezone":"UTC"}
365	2020-08-24 01:27:08	En_CEP	"88035-000"
366	2020-08-24 01:27:15	updateTimestamp	{"date":"2020-08-24 01:27:15.000000","timezone_type":3,"timezone":"UTC"}
367	2020-08-24 01:27:15	En_CEP	"88035-001"
368	2020-08-24 01:27:21	updateTimestamp	{"date":"2020-08-24 01:27:21.000000","timezone_type":3,"timezone":"UTC"}
369	2020-08-24 01:27:21	En_CEP	"01220-010"
370	2020-08-24 01:27:23	updateTimestamp	{"date":"2020-08-24 01:27:23.000000","timezone_type":3,"timezone":"UTC"}
371	2020-08-24 01:27:23	En_Municipio	"S\\u00e3o Paulo"
372	2020-08-24 01:27:23	En_Estado	"SP"
373	2020-08-24 01:27:23	En_Nome_Logradouro	"Rua Rego Freitas"
374	2020-08-24 01:27:23	En_Bairro	"Rep\\u00fablica"
375	2020-08-24 01:42:07	updateTimestamp	{"date":"2020-08-24 01:42:07.000000","timezone_type":3,"timezone":"UTC"}
376	2020-08-24 01:42:07	En_Estado	"SC"
377	2020-08-24 01:42:12	updateTimestamp	{"date":"2020-08-24 01:42:12.000000","timezone_type":3,"timezone":"UTC"}
378	2020-08-24 01:42:12	En_Estado	"SP"
379	2020-08-24 01:42:35	updateTimestamp	{"date":"2020-08-24 01:42:35.000000","timezone_type":3,"timezone":"UTC"}
380	2020-08-24 01:42:35	En_Estado	"RJ"
381	2020-08-24 01:43:09	updateTimestamp	{"date":"2020-08-24 01:43:09.000000","timezone_type":3,"timezone":"UTC"}
382	2020-08-24 01:43:09	En_Estado	"SP"
383	2020-08-24 01:43:35	updateTimestamp	{"date":"2020-08-24 01:43:35.000000","timezone_type":3,"timezone":"UTC"}
384	2020-08-24 01:43:35	En_Estado	"RR"
385	2020-08-24 01:44:09	updateTimestamp	{"date":"2020-08-24 01:44:09.000000","timezone_type":3,"timezone":"UTC"}
386	2020-08-24 01:44:09	En_Estado	"RO"
387	2020-08-24 01:45:17	updateTimestamp	{"date":"2020-08-24 01:45:17.000000","timezone_type":3,"timezone":"UTC"}
388	2020-08-24 01:45:17	En_Estado	"PE"
389	2020-08-24 01:46:21	updateTimestamp	{"date":"2020-08-24 01:46:21.000000","timezone_type":3,"timezone":"UTC"}
390	2020-08-24 01:46:21	En_Estado	"SP"
391	2020-08-24 02:00:03	updateTimestamp	{"date":"2020-08-24 02:00:03.000000","timezone_type":3,"timezone":"UTC"}
392	2020-08-24 02:00:03	En_Estado	"SC"
393	2020-08-24 02:00:05	updateTimestamp	{"date":"2020-08-24 02:00:05.000000","timezone_type":3,"timezone":"UTC"}
394	2020-08-24 02:00:05	En_Estado	"RN"
395	2020-08-24 02:00:10	updateTimestamp	{"date":"2020-08-24 02:00:10.000000","timezone_type":3,"timezone":"UTC"}
396	2020-08-24 02:00:10	En_Estado	"SP"
397	2020-08-24 02:00:27	updateTimestamp	{"date":"2020-08-24 02:00:27.000000","timezone_type":3,"timezone":"UTC"}
398	2020-08-24 02:00:27	En_Estado	"SC"
399	2020-08-24 03:19:39	updateTimestamp	{"date":"2020-08-24 03:19:39.000000","timezone_type":3,"timezone":"UTC"}
400	2020-08-24 03:19:39	En_Estado	""
401	2020-08-24 03:20:12	updateTimestamp	{"date":"2020-08-24 03:20:12.000000","timezone_type":3,"timezone":"UTC"}
402	2020-08-24 03:20:12	En_Estado	"Distrito Federal"
403	2020-08-24 03:21:22	updateTimestamp	{"date":"2020-08-24 03:21:22.000000","timezone_type":3,"timezone":"UTC"}
404	2020-08-24 03:21:22	En_Estado	""
405	2020-08-24 03:21:50	updateTimestamp	{"date":"2020-08-24 03:21:50.000000","timezone_type":3,"timezone":"UTC"}
406	2020-08-24 03:21:50	En_Estado	"SP"
407	2020-08-24 03:22:45	updateTimestamp	{"date":"2020-08-24 03:22:45.000000","timezone_type":3,"timezone":"UTC"}
408	2020-08-24 03:22:45	En_CEP	"88035-001"
409	2020-08-24 03:22:48	updateTimestamp	{"date":"2020-08-24 03:22:48.000000","timezone_type":3,"timezone":"UTC"}
410	2020-08-24 03:22:48	En_Municipio	""
411	2020-08-24 03:22:48	En_Nome_Logradouro	"Avenida Madre Benvenuta"
412	2020-08-24 03:22:48	En_Bairro	"Santa M\\u00f4nica"
413	2020-08-24 03:22:48	En_Estado	"SC"
414	2020-08-24 03:22:58	updateTimestamp	{"date":"2020-08-24 03:22:57.000000","timezone_type":3,"timezone":"UTC"}
415	2020-08-24 03:22:58	En_CEP	"88035-000"
416	2020-08-24 03:23:00	updateTimestamp	{"date":"2020-08-24 03:22:59.000000","timezone_type":3,"timezone":"UTC"}
417	2020-08-24 03:23:00	En_Municipio	"Florian\\u00f3polis"
418	2020-08-24 03:24:32	updateTimestamp	{"date":"2020-08-24 03:24:32.000000","timezone_type":3,"timezone":"UTC"}
419	2020-08-24 03:24:32	En_CEP	"01220-010"
420	2020-08-24 03:24:36	updateTimestamp	{"date":"2020-08-24 03:24:36.000000","timezone_type":3,"timezone":"UTC"}
421	2020-08-24 03:24:36	En_Nome_Logradouro	"Rua Rego Freitas"
422	2020-08-24 03:24:36	En_Bairro	"Rep\\u00fablica"
423	2020-08-24 03:24:36	En_Estado	"SP"
424	2020-08-24 03:24:36	En_Municipio	""
425	2020-08-24 03:24:43	updateTimestamp	{"date":"2020-08-24 03:24:43.000000","timezone_type":3,"timezone":"UTC"}
426	2020-08-24 03:24:43	En_CEP	"01220-000"
427	2020-08-24 03:24:43	En_Municipio	"S\\u00e3o Paulo"
428	2020-08-24 03:24:49	updateTimestamp	{"date":"2020-08-24 03:24:49.000000","timezone_type":3,"timezone":"UTC"}
429	2020-08-24 03:24:49	En_Nome_Logradouro	"Rua Bento Freitas"
430	2020-08-24 03:25:02	updateTimestamp	{"date":"2020-08-24 03:25:02.000000","timezone_type":3,"timezone":"UTC"}
431	2020-08-24 03:25:02	En_CEP	"88035-001"
432	2020-08-24 03:25:04	updateTimestamp	{"date":"2020-08-24 03:25:04.000000","timezone_type":3,"timezone":"UTC"}
433	2020-08-24 03:25:07	updateTimestamp	{"date":"2020-08-24 03:25:07.000000","timezone_type":3,"timezone":"UTC"}
434	2020-08-24 03:25:07	En_Municipio	""
435	2020-08-24 03:25:07	En_Nome_Logradouro	"Avenida Madre Benvenuta"
436	2020-08-24 03:25:07	En_Bairro	"Santa M\\u00f4nica"
437	2020-08-24 03:25:07	En_Estado	"SC"
438	2020-08-24 03:25:21	updateTimestamp	{"date":"2020-08-24 03:25:21.000000","timezone_type":3,"timezone":"UTC"}
439	2020-08-24 03:25:21	En_CEP	"880"
440	2020-08-24 03:25:25	updateTimestamp	{"date":"2020-08-24 03:25:25.000000","timezone_type":3,"timezone":"UTC"}
441	2020-08-24 03:25:25	En_CEP	"88035-001"
442	2020-08-24 03:25:26	updateTimestamp	{"date":"2020-08-24 03:25:26.000000","timezone_type":3,"timezone":"UTC"}
443	2020-08-24 03:25:26	En_Municipio	"Florian\\u00f3polis"
444	2020-08-24 03:25:42	updateTimestamp	{"date":"2020-08-24 03:25:42.000000","timezone_type":3,"timezone":"UTC"}
445	2020-08-24 03:25:42	En_CEP	"01220-010"
446	2020-08-24 03:25:44	updateTimestamp	{"date":"2020-08-24 03:25:44.000000","timezone_type":3,"timezone":"UTC"}
447	2020-08-24 03:25:44	En_Nome_Logradouro	"Rua Rego Freitas"
448	2020-08-24 03:25:44	En_Bairro	"Rep\\u00fablica"
449	2020-08-24 03:25:44	En_Estado	"SP"
450	2020-08-24 03:25:44	En_Municipio	""
451	2020-08-24 03:25:45	updateTimestamp	{"date":"2020-08-24 03:25:45.000000","timezone_type":3,"timezone":"UTC"}
452	2020-08-24 03:25:45	En_Municipio	"S\\u00e3o Paulo"
453	2020-08-24 03:26:07	updateTimestamp	{"date":"2020-08-24 03:26:07.000000","timezone_type":3,"timezone":"UTC"}
454	2020-08-24 03:26:07	En_CEP	"88035-001"
455	2020-08-24 03:26:19	updateTimestamp	{"date":"2020-08-24 03:26:19.000000","timezone_type":3,"timezone":"UTC"}
456	2020-08-24 03:26:19	En_CEP	"88035-000"
457	2020-08-24 03:26:22	updateTimestamp	{"date":"2020-08-24 03:26:22.000000","timezone_type":3,"timezone":"UTC"}
458	2020-08-24 03:26:22	En_CEP	"88035-001"
459	2020-08-24 03:26:35	updateTimestamp	{"date":"2020-08-24 03:26:35.000000","timezone_type":3,"timezone":"UTC"}
460	2020-08-24 03:26:35	En_CEP	"88035-00"
461	2020-08-24 03:26:44	updateTimestamp	{"date":"2020-08-24 03:26:44.000000","timezone_type":3,"timezone":"UTC"}
462	2020-08-24 03:26:44	En_CEP	"88035-010"
463	2020-08-24 03:26:56	updateTimestamp	{"date":"2020-08-24 03:26:56.000000","timezone_type":3,"timezone":"UTC"}
464	2020-08-24 03:26:56	En_CEP	"88035-020"
465	2020-08-24 03:27:04	updateTimestamp	{"date":"2020-08-24 03:27:04.000000","timezone_type":3,"timezone":"UTC"}
466	2020-08-24 03:27:10	updateTimestamp	{"date":"2020-08-24 03:27:10.000000","timezone_type":3,"timezone":"UTC"}
467	2020-08-24 03:27:10	En_CEP	"88035-"
468	2020-08-24 03:27:13	updateTimestamp	{"date":"2020-08-24 03:27:13.000000","timezone_type":3,"timezone":"UTC"}
469	2020-08-24 03:27:13	En_CEP	"88035-001"
470	2020-08-24 03:27:44	updateTimestamp	{"date":"2020-08-24 03:27:44.000000","timezone_type":3,"timezone":"UTC"}
471	2020-08-24 03:27:44	En_Municipio	"Flora Rica"
472	2020-08-24 03:27:48	updateTimestamp	{"date":"2020-08-24 03:27:48.000000","timezone_type":3,"timezone":"UTC"}
473	2020-08-24 03:27:48	En_Estado	"SE"
474	2020-08-24 03:27:54	updateTimestamp	{"date":"2020-08-24 03:27:54.000000","timezone_type":3,"timezone":"UTC"}
475	2020-08-24 03:27:54	En_Estado	"SC"
476	2020-08-24 03:29:21	updateTimestamp	{"date":"2020-08-24 03:29:21.000000","timezone_type":3,"timezone":"UTC"}
477	2020-08-24 03:29:21	En_Estado	"RN"
478	2020-08-24 03:29:31	updateTimestamp	{"date":"2020-08-24 03:29:31.000000","timezone_type":3,"timezone":"UTC"}
479	2020-08-24 03:29:31	En_CEP	"01220-010"
480	2020-08-24 03:29:37	updateTimestamp	{"date":"2020-08-24 03:29:37.000000","timezone_type":3,"timezone":"UTC"}
481	2020-08-24 03:29:37	En_CEP	"01220-000"
482	2020-08-24 03:30:17	updateTimestamp	{"date":"2020-08-24 03:30:17.000000","timezone_type":3,"timezone":"UTC"}
483	2020-08-24 03:30:17	En_Municipio	"S\\u00e3o Paulo do Potengi"
484	2020-08-24 03:30:21	updateTimestamp	{"date":"2020-08-24 03:30:21.000000","timezone_type":3,"timezone":"UTC"}
485	2020-08-24 03:30:21	En_Estado	"MS"
486	2020-08-24 03:30:24	updateTimestamp	{"date":"2020-08-24 03:30:24.000000","timezone_type":3,"timezone":"UTC"}
487	2020-08-24 03:30:24	En_Estado	"SC"
488	2020-08-24 03:31:54	updateTimestamp	{"date":"2020-08-24 03:31:54.000000","timezone_type":3,"timezone":"UTC"}
489	2020-08-24 03:31:54	En_Nome_Logradouro	"Rua Bento Freitas"
490	2020-08-24 03:31:54	En_CEP	"88035-001"
491	2020-08-24 03:31:54	En_Municipio	"S\\u00e3o Paulo"
492	2020-08-24 03:31:54	En_Estado	"SP"
493	2020-08-24 03:31:56	updateTimestamp	{"date":"2020-08-24 03:31:56.000000","timezone_type":3,"timezone":"UTC"}
494	2020-08-24 03:31:56	En_Bairro	"Santa M\\u00f4nica"
495	2020-08-24 03:31:56	En_Nome_Logradouro	"Avenida Madre Benvenuta"
496	2020-08-24 03:31:56	En_Municipio	"Florian\\u00f3polis"
497	2020-08-24 03:31:56	En_Estado	"SC"
498	2020-08-24 03:32:02	updateTimestamp	{"date":"2020-08-24 03:32:02.000000","timezone_type":3,"timezone":"UTC"}
499	2020-08-24 03:32:02	En_CEP	"01220-010"
500	2020-08-24 03:32:03	updateTimestamp	{"date":"2020-08-24 03:32:03.000000","timezone_type":3,"timezone":"UTC"}
501	2020-08-24 03:32:03	En_Bairro	"Rep\\u00fablica"
502	2020-08-24 03:32:03	En_Nome_Logradouro	"Rua Rego Freitas"
503	2020-08-24 03:32:03	En_Estado	"SP"
504	2020-08-24 03:32:04	updateTimestamp	{"date":"2020-08-24 03:32:04.000000","timezone_type":3,"timezone":"UTC"}
505	2020-08-24 03:32:04	En_Municipio	"S\\u00e3o Paulo"
506	2020-08-24 03:32:51	updateTimestamp	{"date":"2020-08-24 03:32:51.000000","timezone_type":3,"timezone":"UTC"}
507	2020-08-24 03:32:51	En_CEP	"88035-001"
508	2020-08-24 03:34:32	updateTimestamp	{"date":"2020-08-24 03:34:32.000000","timezone_type":3,"timezone":"UTC"}
509	2020-08-24 03:34:32	En_Estado	"SC"
510	2020-08-24 03:34:32	En_Municipio	"Florian\\u00f3polis"
511	2020-08-24 03:34:32	En_CEP	"88035-000"
512	2020-08-24 03:35:03	updateTimestamp	{"date":"2020-08-24 03:35:03.000000","timezone_type":3,"timezone":"UTC"}
513	2020-08-24 03:35:03	En_CEP	"01220-010"
514	2020-08-24 03:36:01	updateTimestamp	{"date":"2020-08-24 03:36:01.000000","timezone_type":3,"timezone":"UTC"}
515	2020-08-24 03:36:01	En_CEP	"88035-001"
516	2020-08-24 03:36:02	updateTimestamp	{"date":"2020-08-24 03:36:02.000000","timezone_type":3,"timezone":"UTC"}
517	2020-08-24 03:36:02	En_Bairro	"Santa M\\u00f4nica"
518	2020-08-24 03:36:02	En_Nome_Logradouro	"Avenida Madre Benvenuta"
519	2020-08-24 03:36:10	updateTimestamp	{"date":"2020-08-24 03:36:10.000000","timezone_type":3,"timezone":"UTC"}
520	2020-08-24 03:36:10	En_CEP	"01220-010"
521	2020-08-24 03:36:11	updateTimestamp	{"date":"2020-08-24 03:36:11.000000","timezone_type":3,"timezone":"UTC"}
522	2020-08-24 03:36:11	En_Estado	"SP"
523	2020-08-24 03:36:11	En_Municipio	"S\\u00e3o Paulo"
524	2020-08-24 03:36:11	En_Bairro	"Rep\\u00fablica"
525	2020-08-24 03:36:11	En_Nome_Logradouro	"Rua Rego Freitas"
526	2020-08-24 03:36:23	updateTimestamp	{"date":"2020-08-24 03:36:23.000000","timezone_type":3,"timezone":"UTC"}
527	2020-08-24 03:36:23	En_CEP	"88035-001"
528	2020-08-24 03:36:24	updateTimestamp	{"date":"2020-08-24 03:36:24.000000","timezone_type":3,"timezone":"UTC"}
529	2020-08-24 03:36:24	En_Estado	"SC"
530	2020-08-24 03:36:24	En_Municipio	"Florian\\u00f3polis"
531	2020-08-24 03:36:24	En_Bairro	"Santa M\\u00f4nica"
532	2020-08-24 03:36:24	En_Nome_Logradouro	"Avenida Madre Benvenuta"
533	2020-08-24 03:37:44	updateTimestamp	{"date":"2020-08-24 03:37:44.000000","timezone_type":3,"timezone":"UTC"}
534	2020-08-24 03:37:44	En_Estado	"RR"
535	2020-08-24 03:37:46	updateTimestamp	{"date":"2020-08-24 03:37:46.000000","timezone_type":3,"timezone":"UTC"}
536	2020-08-24 03:37:46	En_Estado	"SC"
537	2020-08-24 03:38:11	genero	"Homem"
538	2020-08-24 03:38:11	updateTimestamp	{"date":"2020-08-24 03:38:11.000000","timezone_type":3,"timezone":"UTC"}
539	2020-08-24 03:38:15	genero	"Homem Transexual"
540	2020-08-24 03:38:16	updateTimestamp	{"date":"2020-08-24 03:38:16.000000","timezone_type":3,"timezone":"UTC"}
541	2020-08-24 03:57:48	updateTimestamp	{"date":"2020-08-24 03:57:48.000000","timezone_type":3,"timezone":"UTC"}
542	2020-08-24 03:57:48	En_CEP	""
543	2020-08-24 03:57:53	updateTimestamp	{"date":"2020-08-24 03:57:53.000000","timezone_type":3,"timezone":"UTC"}
544	2020-08-24 03:57:53	En_Num	""
545	2020-08-24 03:57:53	En_Nome_Logradouro	""
546	2020-08-24 03:57:54	updateTimestamp	{"date":"2020-08-24 03:57:54.000000","timezone_type":3,"timezone":"UTC"}
547	2020-08-24 03:57:54	En_Bairro	""
548	2020-08-24 03:57:59	updateTimestamp	{"date":"2020-08-24 03:57:59.000000","timezone_type":3,"timezone":"UTC"}
549	2020-08-24 03:57:59	En_Estado	""
550	2020-08-24 03:58:16	updateTimestamp	{"date":"2020-08-24 03:58:16.000000","timezone_type":3,"timezone":"UTC"}
551	2020-08-24 03:58:16	En_Municipio	""
552	2020-08-24 03:59:13	updateTimestamp	{"date":"2020-08-24 03:59:13.000000","timezone_type":3,"timezone":"UTC"}
553	2020-08-24 03:59:13	En_CEP	"01220-010"
554	2020-08-24 03:59:14	updateTimestamp	{"date":"2020-08-24 03:59:14.000000","timezone_type":3,"timezone":"UTC"}
555	2020-08-24 03:59:14	En_Nome_Logradouro	"Rua Rego Freitas"
556	2020-08-24 03:59:14	En_Bairro	"Rep\\u00fablica"
557	2020-08-24 03:59:14	En_Estado	"SP"
558	2020-08-24 03:59:14	En_Municipio	"S\\u00e3o Paulo"
559	2020-08-24 03:59:26	updateTimestamp	{"date":"2020-08-24 03:59:26.000000","timezone_type":3,"timezone":"UTC"}
560	2020-08-24 03:59:26	En_Num	"530"
561	2020-08-24 03:59:58	updateTimestamp	{"date":"2020-08-24 03:59:58.000000","timezone_type":3,"timezone":"UTC"}
562	2020-08-24 03:59:58	En_CEP	"88035-010"
563	2020-08-24 03:59:59	updateTimestamp	{"date":"2020-08-24 03:59:59.000000","timezone_type":3,"timezone":"UTC"}
564	2020-08-24 03:59:59	En_Nome_Logradouro	"Rua Jonas Alves Messina"
565	2020-08-24 03:59:59	En_Bairro	"Santa M\\u00f4nica"
566	2020-08-24 03:59:59	En_Estado	"SC"
567	2020-08-24 03:59:59	En_Municipio	"Florian\\u00f3polis"
568	2020-08-24 04:03:12	updateTimestamp	{"date":"2020-08-24 04:03:12.000000","timezone_type":3,"timezone":"UTC"}
569	2020-08-24 04:03:12	En_CEP	"88035-001"
570	2020-08-24 04:03:43	updateTimestamp	{"date":"2020-08-24 04:03:43.000000","timezone_type":3,"timezone":"UTC"}
571	2020-08-24 04:03:43	En_CEP	"88035-000"
572	2020-08-24 04:04:19	updateTimestamp	{"date":"2020-08-24 04:04:19.000000","timezone_type":3,"timezone":"UTC"}
573	2020-08-24 04:04:19	En_CEP	"88035-001"
574	2020-08-24 04:04:20	updateTimestamp	{"date":"2020-08-24 04:04:20.000000","timezone_type":3,"timezone":"UTC"}
575	2020-08-24 04:04:20	En_Nome_Logradouro	"Avenida Madre Benvenuta"
576	2020-08-24 04:04:23	updateTimestamp	{"date":"2020-08-24 04:04:23.000000","timezone_type":3,"timezone":"UTC"}
577	2020-08-24 04:04:23	En_Num	"a"
578	2020-08-24 04:04:23	En_CEP	"88035-000"
579	2020-08-24 04:06:56	updateTimestamp	{"date":"2020-08-24 04:06:56.000000","timezone_type":3,"timezone":"UTC"}
580	2020-08-24 04:06:56	En_Bairro	""
581	2020-08-24 04:06:58	updateTimestamp	{"date":"2020-08-24 04:06:58.000000","timezone_type":3,"timezone":"UTC"}
582	2020-08-24 04:06:58	En_Nome_Logradouro	""
583	2020-08-24 04:06:58	En_Num	""
584	2020-08-24 04:07:00	updateTimestamp	{"date":"2020-08-24 04:07:00.000000","timezone_type":3,"timezone":"UTC"}
585	2020-08-24 04:07:00	En_Estado	"AP"
586	2020-08-24 04:07:03	updateTimestamp	{"date":"2020-08-24 04:07:03.000000","timezone_type":3,"timezone":"UTC"}
587	2020-08-24 04:07:03	En_Estado	""
588	2020-08-24 04:07:06	updateTimestamp	{"date":"2020-08-24 04:07:06.000000","timezone_type":3,"timezone":"UTC"}
589	2020-08-24 04:07:06	En_Municipio	""
590	2020-08-24 04:07:17	updateTimestamp	{"date":"2020-08-24 04:07:17.000000","timezone_type":3,"timezone":"UTC"}
591	2020-08-24 04:07:17	En_CEP	"88035-001"
592	2020-08-24 04:07:18	updateTimestamp	{"date":"2020-08-24 04:07:18.000000","timezone_type":3,"timezone":"UTC"}
593	2020-08-24 04:07:18	En_Bairro	"Santa M\\u00f4nica"
594	2020-08-24 04:07:18	En_Nome_Logradouro	"Avenida Madre Benvenuta"
595	2020-08-24 04:07:18	En_Estado	"SC"
596	2020-08-24 04:07:18	En_Municipio	"Florian\\u00f3polis"
597	2020-08-24 04:08:38	updateTimestamp	{"date":"2020-08-24 04:08:38.000000","timezone_type":3,"timezone":"UTC"}
598	2020-08-24 04:08:38	En_CEP	"88035-000"
599	2020-08-24 04:11:55	updateTimestamp	{"date":"2020-08-24 04:11:55.000000","timezone_type":3,"timezone":"UTC"}
600	2020-08-24 04:11:55	En_CEP	"88035-001"
601	2020-08-24 04:12:07	updateTimestamp	{"date":"2020-08-24 04:12:07.000000","timezone_type":3,"timezone":"UTC"}
602	2020-08-24 04:12:07	En_CEP	"88035-000"
603	2020-08-24 04:12:11	updateTimestamp	{"date":"2020-08-24 04:12:11.000000","timezone_type":3,"timezone":"UTC"}
604	2020-08-24 04:12:11	En_Num	"530"
605	2020-08-24 04:12:15	updateTimestamp	{"date":"2020-08-24 04:12:15.000000","timezone_type":3,"timezone":"UTC"}
606	2020-08-24 04:12:15	En_Num	"1502"
607	2020-08-24 04:12:33	updateTimestamp	{"date":"2020-08-24 04:12:33.000000","timezone_type":3,"timezone":"UTC"}
608	2020-08-24 04:12:33	En_CEP	"05453-060"
609	2020-08-24 04:12:36	updateTimestamp	{"date":"2020-08-24 04:12:36.000000","timezone_type":3,"timezone":"UTC"}
610	2020-08-24 04:12:36	En_Bairro	"Vila Madalena"
611	2020-08-24 04:12:36	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
612	2020-08-24 04:12:36	En_Estado	"SP"
613	2020-08-24 04:12:36	En_Municipio	"S\\u00e3o Paulo"
614	2020-08-24 04:14:08	updateTimestamp	{"date":"2020-08-24 04:14:08.000000","timezone_type":3,"timezone":"UTC"}
615	2020-08-24 04:17:34	updateTimestamp	{"date":"2020-08-24 04:17:34.000000","timezone_type":3,"timezone":"UTC"}
616	2020-08-24 04:17:34	En_CEP	"01220-101"
617	2020-08-24 04:17:39	updateTimestamp	{"date":"2020-08-24 04:17:39.000000","timezone_type":3,"timezone":"UTC"}
618	2020-08-24 04:17:39	En_CEP	"01220-010"
619	2020-08-24 04:17:45	updateTimestamp	{"date":"2020-08-24 04:17:45.000000","timezone_type":3,"timezone":"UTC"}
620	2020-08-24 04:17:45	En_Bairro	"Rep\\u00fablica"
621	2020-08-24 04:17:45	En_Nome_Logradouro	"Rua Rego Freitas"
622	2020-08-24 04:17:55	updateTimestamp	{"date":"2020-08-24 04:17:55.000000","timezone_type":3,"timezone":"UTC"}
623	2020-08-24 04:17:55	En_CEP	"01220-0"
624	2020-08-24 04:17:58	updateTimestamp	{"date":"2020-08-24 04:17:58.000000","timezone_type":3,"timezone":"UTC"}
625	2020-08-24 04:17:58	En_CEP	"01220-010"
626	2020-08-24 04:18:01	updateTimestamp	{"date":"2020-08-24 04:18:01.000000","timezone_type":3,"timezone":"UTC"}
627	2020-08-24 04:18:01	En_Num	"5030"
1134	2020-08-24 18:17:02	En_CEP	"05453-060"
628	2020-08-24 04:18:05	updateTimestamp	{"date":"2020-08-24 04:18:05.000000","timezone_type":3,"timezone":"UTC"}
629	2020-08-24 04:18:05	En_Num	"530"
630	2020-08-24 04:18:09	updateTimestamp	{"date":"2020-08-24 04:18:09.000000","timezone_type":3,"timezone":"UTC"}
631	2020-08-24 04:18:09	En_Complemento	"apto D4"
632	2020-08-24 04:18:17	updateTimestamp	{"date":"2020-08-24 04:18:17.000000","timezone_type":3,"timezone":"UTC"}
633	2020-08-24 04:24:34	updateTimestamp	{"date":"2020-08-24 04:24:34.000000","timezone_type":3,"timezone":"UTC"}
634	2020-08-24 04:30:15	updateTimestamp	{"date":"2020-08-24 04:30:15.000000","timezone_type":3,"timezone":"UTC"}
635	2020-08-24 04:30:15	En_CEP	"01220-000"
636	2020-08-24 04:30:19	updateTimestamp	{"date":"2020-08-24 04:30:19.000000","timezone_type":3,"timezone":"UTC"}
637	2020-08-24 04:30:19	En_Nome_Logradouro	"Rua Bento Freitas"
638	2020-08-24 05:02:51	updateTimestamp	{"date":"2020-08-24 05:02:51.000000","timezone_type":3,"timezone":"UTC"}
639	2020-08-24 05:02:51	En_CEP	"054"
640	2020-08-24 05:02:57	updateTimestamp	{"date":"2020-08-24 05:02:57.000000","timezone_type":3,"timezone":"UTC"}
641	2020-08-24 05:02:57	En_CEP	"05453-060"
642	2020-08-24 05:02:59	updateTimestamp	{"date":"2020-08-24 05:02:58.000000","timezone_type":3,"timezone":"UTC"}
643	2020-08-24 05:02:59	En_Bairro	"Vila Madalena"
644	2020-08-24 05:02:59	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
645	2020-08-24 06:05:04	_type	2
646	2020-08-24 06:05:04	name	"Meu Coletivo"
647	2020-08-24 06:05:04	publicLocation	false
648	2020-08-24 06:05:04	location	{"latitude":"0","longitude":"0"}
649	2020-08-24 06:05:04	shortDescription	"Coletivo muito maneiro"
650	2020-08-24 06:05:04	longDescription	null
651	2020-08-24 06:05:04	createTimestamp	{"date":"2020-08-24 06:05:04.000000","timezone_type":3,"timezone":"UTC"}
652	2020-08-24 06:05:04	status	1
653	2020-08-24 06:05:04	updateTimestamp	null
654	2020-08-24 06:05:04	_subsiteId	null
655	2020-08-24 06:05:04	_terms	{"":["Dan\\u00e7a"]}
656	2020-08-24 06:05:25	updateTimestamp	{"date":"2020-08-24 06:05:25.000000","timezone_type":3,"timezone":"UTC"}
657	2020-08-24 06:05:25	En_CEP	"88035-010"
658	2020-08-24 06:05:25	En_Bairro	""
659	2020-08-24 06:05:25	En_Nome_Logradouro	""
660	2020-08-24 06:05:25	En_Estado	""
661	2020-08-24 06:05:25	En_Municipio	""
662	2020-08-24 06:05:25	En_Num	""
663	2020-08-24 06:05:25	En_Complemento	""
664	2020-08-24 06:05:29	updateTimestamp	{"date":"2020-08-24 06:05:29.000000","timezone_type":3,"timezone":"UTC"}
665	2020-08-24 06:05:29	En_CEP	"05453-060"
666	2020-08-24 06:05:29	En_Bairro	"Vila Madalena"
667	2020-08-24 06:05:29	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
668	2020-08-24 06:05:29	En_Estado	"SP"
669	2020-08-24 06:05:29	En_Municipio	"S\\u00e3o Paulo"
670	2020-08-24 06:05:29	En_Num	"530"
671	2020-08-24 06:05:29	En_Complemento	"apto D4"
672	2020-08-24 06:05:30	En_CEP	"88035-010"
673	2020-08-24 06:05:30	En_Bairro	"Santa M\\u00f4nica"
674	2020-08-24 06:05:30	En_Nome_Logradouro	"Rua Jonas Alves Messina"
675	2020-08-24 06:05:30	En_Estado	"SC"
676	2020-08-24 06:05:30	En_Municipio	"Florian\\u00f3polis"
677	2020-08-24 06:05:30	En_Num	""
678	2020-08-24 06:05:30	En_Complemento	""
679	2020-08-24 06:05:39	updateTimestamp	{"date":"2020-08-24 06:05:39.000000","timezone_type":3,"timezone":"UTC"}
680	2020-08-24 06:05:39	En_CEP	"05453-060"
681	2020-08-24 06:05:39	En_Bairro	"Vila Madalena"
682	2020-08-24 06:05:39	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
683	2020-08-24 06:05:39	En_Estado	"SP"
684	2020-08-24 06:05:39	En_Municipio	"S\\u00e3o Paulo"
685	2020-08-24 06:05:39	En_Num	"530"
686	2020-08-24 06:05:39	En_Complemento	"apto D4"
687	2020-08-24 06:05:39	En_CEP	"88035-001"
688	2020-08-24 06:05:39	En_Bairro	"Santa M\\u00f4nica"
689	2020-08-24 06:05:39	En_Nome_Logradouro	"Rua Jonas Alves Messina"
690	2020-08-24 06:05:39	En_Estado	"SC"
691	2020-08-24 06:05:39	En_Municipio	"Florian\\u00f3polis"
692	2020-08-24 06:05:39	En_Num	""
693	2020-08-24 06:05:39	En_Complemento	""
694	2020-08-24 06:05:40	updateTimestamp	{"date":"2020-08-24 06:05:40.000000","timezone_type":3,"timezone":"UTC"}
695	2020-08-24 06:05:40	En_CEP	"05453-060"
696	2020-08-24 06:05:40	En_Bairro	"Vila Madalena"
697	2020-08-24 06:05:40	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
698	2020-08-24 06:05:40	En_Estado	"SP"
699	2020-08-24 06:05:40	En_Municipio	"S\\u00e3o Paulo"
700	2020-08-24 06:05:40	En_Num	"530"
701	2020-08-24 06:05:40	En_Complemento	"apto D4"
702	2020-08-24 06:05:40	En_CEP	"88035-001"
703	2020-08-24 06:05:40	En_Bairro	"Santa M\\u00f4nica"
704	2020-08-24 06:05:40	En_Nome_Logradouro	"Avenida Madre Benvenuta"
705	2020-08-24 06:05:40	En_Estado	"SC"
706	2020-08-24 06:05:40	En_Municipio	"Florian\\u00f3polis"
707	2020-08-24 06:05:40	En_Num	""
708	2020-08-24 06:05:40	En_Complemento	""
709	2020-08-24 06:05:44	updateTimestamp	{"date":"2020-08-24 06:05:44.000000","timezone_type":3,"timezone":"UTC"}
710	2020-08-24 06:05:44	En_CEP	"05453-060"
711	2020-08-24 06:05:44	En_Bairro	"Vila Madalena"
712	2020-08-24 06:05:44	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
713	2020-08-24 06:05:44	En_Estado	"SP"
714	2020-08-24 06:05:44	En_Municipio	"S\\u00e3o Paulo"
715	2020-08-24 06:05:44	En_Num	"530"
716	2020-08-24 06:05:44	En_Complemento	"apto D4"
717	2020-08-24 06:05:44	En_CEP	"88035-001"
718	2020-08-24 06:05:44	En_Bairro	"Santa M\\u00f4nica"
719	2020-08-24 06:05:44	En_Nome_Logradouro	"Avenida Madre Benvenuta"
720	2020-08-24 06:05:44	En_Estado	"SC"
721	2020-08-24 06:05:44	En_Municipio	"Florian\\u00f3polis"
722	2020-08-24 06:05:44	En_Num	"1502"
723	2020-08-24 06:05:44	En_Complemento	""
724	2020-08-24 06:07:20	updateTimestamp	{"date":"2020-08-24 06:07:20.000000","timezone_type":3,"timezone":"UTC"}
725	2020-08-24 06:07:20	En_CEP	"05453-060"
726	2020-08-24 06:07:20	En_Bairro	"Vila Madalena"
727	2020-08-24 06:07:20	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
728	2020-08-24 06:07:20	En_Estado	"SP"
729	2020-08-24 06:07:20	En_Municipio	"S\\u00e3o Paulo"
730	2020-08-24 06:07:20	En_Num	"530"
731	2020-08-24 06:07:20	En_Complemento	"apto D4"
732	2020-08-24 06:07:21	En_CEP	"88035-000"
733	2020-08-24 06:07:21	En_Bairro	"Santa M\\u00f4nica"
734	2020-08-24 06:07:21	En_Nome_Logradouro	"Avenida Madre Benvenuta"
735	2020-08-24 06:07:21	En_Estado	"SC"
736	2020-08-24 06:07:21	En_Municipio	"Florian\\u00f3polis"
737	2020-08-24 06:07:21	En_Num	"1502"
738	2020-08-24 06:07:21	En_Complemento	""
744	2020-08-24 06:08:14	updateTimestamp	{"date":"2020-08-24 06:08:14.000000","timezone_type":3,"timezone":"UTC"}
745	2020-08-24 06:08:14	En_CEP	"05453-060"
746	2020-08-24 06:08:14	En_Bairro	"Vila Madalena"
747	2020-08-24 06:08:14	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
748	2020-08-24 06:08:14	En_Estado	"SP"
749	2020-08-24 06:08:14	En_Municipio	"S\\u00e3o Paulo"
750	2020-08-24 06:08:14	En_Num	"530"
751	2020-08-24 06:08:14	En_Complemento	"apto D4"
752	2020-08-24 06:08:14	En_CEP	"88035-001"
753	2020-08-24 06:08:14	En_Nome_Logradouro	"Avenida Madre Benvenuta"
754	2020-08-24 06:08:14	En_Num	"1502"
755	2020-08-24 06:08:14	En_Bairro	"Santa M\\u00f4nica"
756	2020-08-24 06:08:14	En_Municipio	"Florian\\u00f3polis"
757	2020-08-24 06:08:14	En_Estado	"SC"
758	2020-08-24 06:43:47	updateTimestamp	{"date":"2020-08-24 06:43:47.000000","timezone_type":3,"timezone":"UTC"}
759	2020-08-24 06:43:48	name	""
760	2020-08-24 06:43:48	updateTimestamp	{"date":"2020-08-24 06:43:48.000000","timezone_type":3,"timezone":"UTC"}
761	2020-08-24 06:43:48	En_CEP	""
762	2020-08-24 06:43:48	En_Nome_Logradouro	""
763	2020-08-24 06:43:48	En_Num	""
764	2020-08-24 06:43:48	En_Bairro	""
765	2020-08-24 06:43:48	En_Municipio	""
766	2020-08-24 06:43:48	En_Estado	""
767	2020-08-24 06:43:52	updateTimestamp	{"date":"2020-08-24 06:43:52.000000","timezone_type":3,"timezone":"UTC"}
768	2020-08-24 06:43:57	updateTimestamp	{"date":"2020-08-24 06:43:57.000000","timezone_type":3,"timezone":"UTC"}
769	2020-08-24 06:44:56	location	{"latitude":"0","longitude":"0"}
770	2020-08-24 06:44:56	name	"Museu Sei La"
771	2020-08-24 06:44:56	public	false
772	2020-08-24 06:44:56	shortDescription	"o museu sei l\\u00e1 o qu\\u00ea"
773	2020-08-24 06:44:56	longDescription	null
774	2020-08-24 06:44:56	createTimestamp	{"date":"2020-08-24 06:44:56.000000","timezone_type":3,"timezone":"UTC"}
775	2020-08-24 06:44:56	status	1
776	2020-08-24 06:44:56	_type	61
777	2020-08-24 06:44:56	_ownerId	4
778	2020-08-24 06:44:56	updateTimestamp	null
779	2020-08-24 06:44:56	_subsiteId	null
780	2020-08-24 06:44:56	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":392}
781	2020-08-24 06:44:56	_terms	{"":["Cultura Popular"]}
782	2020-08-24 06:45:13	updateTimestamp	{"date":"2020-08-24 06:45:13.000000","timezone_type":3,"timezone":"UTC"}
783	2020-08-24 06:45:13	_spaces	[{"id":1,"name":"Museu Sei La","revision":393}]
784	2020-08-24 06:45:14	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":394}
785	2020-08-24 06:45:14	En_Bairro	"Rep\\u00fablica"
786	2020-08-24 06:45:14	En_CEP	"01220-010"
787	2020-08-24 06:45:14	En_Estado	"SP"
788	2020-08-24 06:45:14	En_Municipio	"S\\u00e3o Paulo"
789	2020-08-24 06:45:14	En_Nome_Logradouro	"Rua Rego Freitas"
790	2020-08-24 06:45:14	En_Num	"530"
791	2020-08-24 06:52:41	updateTimestamp	{"date":"2020-08-24 06:52:41.000000","timezone_type":3,"timezone":"UTC"}
792	2020-08-24 06:52:41	En_CEP	"01220-010"
793	2020-08-24 06:52:41	_spaces	[{"id":1,"name":"Museu Sei La","revision":395}]
794	2020-08-24 06:52:41	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":396}
795	2020-08-24 06:52:41	En_Bairro	""
796	2020-08-24 06:52:41	En_CEP	""
797	2020-08-24 06:52:41	En_Estado	""
798	2020-08-24 06:52:41	En_Municipio	""
799	2020-08-24 06:52:41	En_Nome_Logradouro	""
800	2020-08-24 06:52:41	En_Num	""
801	2020-08-24 06:52:49	updateTimestamp	{"date":"2020-08-24 06:52:49.000000","timezone_type":3,"timezone":"UTC"}
802	2020-08-24 06:52:49	En_CEP	"88035-001"
803	2020-08-24 06:52:49	_spaces	[{"id":1,"name":"Museu Sei La","revision":397}]
804	2020-08-24 06:52:49	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":398}
805	2020-08-24 06:52:50	updateTimestamp	{"date":"2020-08-24 06:52:50.000000","timezone_type":3,"timezone":"UTC"}
806	2020-08-24 06:52:50	En_Bairro	"Santa M\\u00f4nica"
807	2020-08-24 06:52:50	En_Nome_Logradouro	"Avenida Madre Benvenuta"
808	2020-08-24 06:52:50	En_Estado	"SC"
809	2020-08-24 06:52:50	En_Municipio	"Florian\\u00f3polis"
810	2020-08-24 06:52:50	_spaces	[{"id":1,"name":"Museu Sei La","revision":399}]
811	2020-08-24 06:52:51	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":400}
812	2020-08-24 06:52:52	updateTimestamp	{"date":"2020-08-24 06:52:52.000000","timezone_type":3,"timezone":"UTC"}
813	2020-08-24 06:52:52	En_Num	"1502"
814	2020-08-24 06:52:52	_spaces	[{"id":1,"name":"Museu Sei La","revision":401}]
815	2020-08-24 06:52:53	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":402}
816	2020-08-24 06:53:49	updateTimestamp	{"date":"2020-08-24 06:53:49.000000","timezone_type":3,"timezone":"UTC"}
817	2020-08-24 06:53:49	_spaces	[{"id":1,"name":"Museu Sei La","revision":403}]
818	2020-08-24 06:53:50	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":404}
819	2020-08-24 06:54:47	updateTimestamp	{"date":"2020-08-24 06:54:47.000000","timezone_type":3,"timezone":"UTC"}
820	2020-08-24 06:54:47	En_CEP	"88035-000"
821	2020-08-24 06:54:47	_spaces	[{"id":1,"name":"Museu Sei La","revision":405}]
822	2020-08-24 06:54:48	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":406}
823	2020-08-24 06:55:23	updateTimestamp	{"date":"2020-08-24 06:55:23.000000","timezone_type":3,"timezone":"UTC"}
824	2020-08-24 06:55:23	En_CEP	"88035-001"
1135	2020-08-24 18:17:22	name	"Cooletivo"
825	2020-08-24 06:55:23	_spaces	[{"id":1,"name":"Museu Sei La","revision":407}]
826	2020-08-24 06:55:24	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":408}
827	2020-08-24 06:56:18	updateTimestamp	{"date":"2020-08-24 06:56:18.000000","timezone_type":3,"timezone":"UTC"}
828	2020-08-24 06:56:18	En_CEP	"88035-000"
829	2020-08-24 06:56:18	_spaces	[{"id":1,"name":"Museu Sei La","revision":409}]
830	2020-08-24 06:56:18	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":410}
831	2020-08-24 06:56:47	updateTimestamp	{"date":"2020-08-24 06:56:47.000000","timezone_type":3,"timezone":"UTC"}
832	2020-08-24 06:56:47	En_Complemento	"apto D5"
833	2020-08-24 06:56:47	_spaces	[{"id":1,"name":"Museu Sei La","revision":411}]
834	2020-08-24 06:56:47	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":412}
835	2020-08-24 06:57:56	updateTimestamp	{"date":"2020-08-24 06:57:56.000000","timezone_type":3,"timezone":"UTC"}
836	2020-08-24 06:57:56	En_CEP	"88035-001"
837	2020-08-24 06:57:56	_spaces	[{"id":1,"name":"Museu Sei La","revision":413}]
838	2020-08-24 06:57:56	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":414}
839	2020-08-24 06:58:30	updateTimestamp	{"date":"2020-08-24 06:58:30.000000","timezone_type":3,"timezone":"UTC"}
840	2020-08-24 06:58:30	En_Nome_Logradouro	"Avenida Madre Benvenutas"
841	2020-08-24 06:58:30	_spaces	[{"id":1,"name":"Museu Sei La","revision":415}]
842	2020-08-24 06:58:30	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":416}
843	2020-08-24 06:59:20	updateTimestamp	{"date":"2020-08-24 06:59:20.000000","timezone_type":3,"timezone":"UTC"}
844	2020-08-24 06:59:20	En_Nome_Logradouro	"Avenida Madre Benvenuta"
845	2020-08-24 06:59:20	_spaces	[{"id":1,"name":"Museu Sei La","revision":417}]
846	2020-08-24 06:59:20	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":418}
847	2020-08-24 06:59:33	updateTimestamp	{"date":"2020-08-24 06:59:33.000000","timezone_type":3,"timezone":"UTC"}
848	2020-08-24 06:59:33	En_Nome_Logradouro	"Avenida Madre Benvenutas"
849	2020-08-24 06:59:33	_spaces	[{"id":1,"name":"Museu Sei La","revision":419}]
850	2020-08-24 06:59:33	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":420}
851	2020-08-24 06:59:44	updateTimestamp	{"date":"2020-08-24 06:59:44.000000","timezone_type":3,"timezone":"UTC"}
852	2020-08-24 06:59:44	En_Num	"150"
853	2020-08-24 06:59:44	_spaces	[{"id":1,"name":"Museu Sei La","revision":421}]
854	2020-08-24 06:59:45	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":422}
855	2020-08-24 07:00:07	updateTimestamp	{"date":"2020-08-24 07:00:07.000000","timezone_type":3,"timezone":"UTC"}
856	2020-08-24 07:00:07	En_Num	"1500"
857	2020-08-24 07:00:07	_spaces	[{"id":1,"name":"Museu Sei La","revision":423}]
858	2020-08-24 07:00:07	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":424}
859	2020-08-24 07:00:25	updateTimestamp	{"date":"2020-08-24 07:00:25.000000","timezone_type":3,"timezone":"UTC"}
860	2020-08-24 07:00:25	En_Num	"150"
861	2020-08-24 07:00:25	_spaces	[{"id":1,"name":"Museu Sei La","revision":425}]
862	2020-08-24 07:00:26	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":426}
863	2020-08-24 07:00:32	updateTimestamp	{"date":"2020-08-24 07:00:32.000000","timezone_type":3,"timezone":"UTC"}
864	2020-08-24 07:00:32	En_Num	"1500"
865	2020-08-24 07:00:32	_spaces	[{"id":1,"name":"Museu Sei La","revision":427}]
866	2020-08-24 07:00:33	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":428}
867	2020-08-24 07:00:41	updateTimestamp	{"date":"2020-08-24 07:00:41.000000","timezone_type":3,"timezone":"UTC"}
868	2020-08-24 07:00:41	En_Nome_Logradouro	"Avenida Madre Benvenuta"
869	2020-08-24 07:00:41	_spaces	[{"id":1,"name":"Museu Sei La","revision":429}]
870	2020-08-24 07:00:42	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":430}
871	2020-08-24 07:00:44	updateTimestamp	{"date":"2020-08-24 07:00:43.000000","timezone_type":3,"timezone":"UTC"}
872	2020-08-24 07:00:44	En_Num	"1502"
873	2020-08-24 07:00:44	_spaces	[{"id":1,"name":"Museu Sei La","revision":431}]
874	2020-08-24 07:00:44	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":432}
875	2020-08-24 07:01:08	updateTimestamp	{"date":"2020-08-24 07:01:08.000000","timezone_type":3,"timezone":"UTC"}
876	2020-08-24 07:01:08	En_Num	"1512"
877	2020-08-24 07:01:08	_spaces	[{"id":1,"name":"Museu Sei La","revision":433}]
878	2020-08-24 07:01:09	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":434}
879	2020-08-24 07:02:33	updateTimestamp	{"date":"2020-08-24 07:02:33.000000","timezone_type":3,"timezone":"UTC"}
880	2020-08-24 07:02:33	En_Num	"1502"
881	2020-08-24 07:02:33	_spaces	[{"id":1,"name":"Museu Sei La","revision":435}]
882	2020-08-24 07:02:33	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":436}
883	2020-08-24 07:02:36	updateTimestamp	{"date":"2020-08-24 07:02:36.000000","timezone_type":3,"timezone":"UTC"}
884	2020-08-24 07:02:36	En_Complemento	""
885	2020-08-24 07:02:36	_spaces	[{"id":1,"name":"Museu Sei La","revision":437}]
886	2020-08-24 07:02:37	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":438}
887	2020-08-24 07:02:48	updateTimestamp	{"date":"2020-08-24 07:02:48.000000","timezone_type":3,"timezone":"UTC"}
888	2020-08-24 07:02:48	En_CEP	"88035-000"
889	2020-08-24 07:02:48	_spaces	[{"id":1,"name":"Museu Sei La","revision":439}]
890	2020-08-24 07:02:49	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":440}
891	2020-08-24 07:04:56	updateTimestamp	{"date":"2020-08-24 07:04:56.000000","timezone_type":3,"timezone":"UTC"}
892	2020-08-24 07:04:56	En_Nome_Logradouro	"Avenida Madre Benvenutas"
893	2020-08-24 07:04:56	endereco	"Avenida Madre Benvenutas 1502, Santa M\\u00f4nica, Florian\\u00f3polis, SC, BR"
894	2020-08-24 07:04:56	_spaces	[{"id":1,"name":"Museu Sei La","revision":441}]
895	2020-08-24 07:04:57	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":442}
896	2020-08-24 07:05:03	updateTimestamp	{"date":"2020-08-24 07:05:03.000000","timezone_type":3,"timezone":"UTC"}
897	2020-08-24 07:05:03	En_Nome_Logradouro	"Avenida Madre Benvenuta"
898	2020-08-24 07:05:03	_spaces	[{"id":1,"name":"Museu Sei La","revision":443}]
899	2020-08-24 07:05:04	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":444}
900	2020-08-24 07:05:23	updateTimestamp	{"date":"2020-08-24 07:05:23.000000","timezone_type":3,"timezone":"UTC"}
901	2020-08-24 07:05:23	En_Num	"1500"
902	2020-08-24 07:05:23	endereco	"Avenida Madre Benvenuta 1500, Santa M\\u00f4nica, Florian\\u00f3polis, SC, BR"
903	2020-08-24 07:05:23	_spaces	[{"id":1,"name":"Museu Sei La","revision":445}]
904	2020-08-24 07:05:23	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":446}
905	2020-08-24 07:06:48	updateTimestamp	{"date":"2020-08-24 07:06:48.000000","timezone_type":3,"timezone":"UTC"}
906	2020-08-24 07:06:48	En_Num	"1502"
907	2020-08-24 07:06:48	endereco	"Avenida Madre Benvenuta 1502, Santa M\\u00f4nica, Florian\\u00f3polis, SC, BR"
908	2020-08-24 07:06:48	_spaces	[{"id":1,"name":"Museu Sei La","revision":447}]
909	2020-08-24 07:06:49	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":448}
910	2020-08-24 07:07:04	updateTimestamp	{"date":"2020-08-24 07:07:03.000000","timezone_type":3,"timezone":"UTC"}
911	2020-08-24 07:07:04	En_Bairro	"Santa M\\u00f4nicaa"
912	2020-08-24 07:07:04	endereco	"Avenida Madre Benvenuta 1502, Santa M\\u00f4nicaa, Florian\\u00f3polis, SC, BR"
913	2020-08-24 07:07:04	_spaces	[{"id":1,"name":"Museu Sei La","revision":449}]
914	2020-08-24 07:07:04	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":450}
915	2020-08-24 07:07:05	updateTimestamp	{"date":"2020-08-24 07:07:05.000000","timezone_type":3,"timezone":"UTC"}
916	2020-08-24 07:07:05	En_Bairro	"Santa M\\u00f4nica"
917	2020-08-24 07:07:05	_spaces	[{"id":1,"name":"Museu Sei La","revision":451}]
918	2020-08-24 07:07:05	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":452}
919	2020-08-24 07:07:36	updateTimestamp	{"date":"2020-08-24 07:07:36.000000","timezone_type":3,"timezone":"UTC"}
920	2020-08-24 07:07:36	En_CEP	"01220-010"
921	2020-08-24 07:07:36	endereco	"Avenida Madre Benvenuta 1502, Santa M\\u00f4nica, Florian\\u00f3polis, SC, BR"
922	2020-08-24 07:07:36	_spaces	[{"id":1,"name":"Museu Sei La","revision":453}]
923	2020-08-24 07:07:36	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":454}
924	2020-08-24 07:07:38	updateTimestamp	{"date":"2020-08-24 07:07:38.000000","timezone_type":3,"timezone":"UTC"}
925	2020-08-24 07:07:38	En_Estado	"SP"
926	2020-08-24 07:07:38	En_Municipio	"S\\u00e3o Paulo"
927	2020-08-24 07:07:38	En_Nome_Logradouro	"Rua Rego Freitas"
928	2020-08-24 07:07:38	En_Bairro	"Rep\\u00fablica"
929	2020-08-24 07:07:38	_spaces	[{"id":1,"name":"Museu Sei La","revision":455}]
930	2020-08-24 07:07:39	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":456}
931	2020-08-24 07:08:01	updateTimestamp	{"date":"2020-08-24 07:08:01.000000","timezone_type":3,"timezone":"UTC"}
932	2020-08-24 07:08:01	endereco	"Rua Rego Freitas 1502, Rep\\u00fablica, S\\u00e3o Paulo, SP, BR"
933	2020-08-24 07:08:01	_spaces	[{"id":1,"name":"Museu Sei La","revision":457}]
934	2020-08-24 07:08:02	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":458}
935	2020-08-24 07:09:34	updateTimestamp	{"date":"2020-08-24 07:09:34.000000","timezone_type":3,"timezone":"UTC"}
936	2020-08-24 07:09:34	En_CEP	"88035-001"
937	2020-08-24 07:09:34	_spaces	[{"id":1,"name":"Museu Sei La","revision":459}]
938	2020-08-24 07:09:35	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":460}
939	2020-08-24 07:09:36	location	{"latitude":"-23.5458711","longitude":"-46.6466427"}
940	2020-08-24 07:09:36	updateTimestamp	{"date":"2020-08-24 07:09:36.000000","timezone_type":3,"timezone":"UTC"}
941	2020-08-24 07:09:36	_spaces	[{"id":1,"name":"Museu Sei La","revision":461}]
942	2020-08-24 07:09:36	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":462}
943	2020-08-24 07:09:41	location	{"latitude":"-27.6039300012","longitude":"-48.5411803391"}
944	2020-08-24 07:09:41	updateTimestamp	{"date":"2020-08-24 07:09:41.000000","timezone_type":3,"timezone":"UTC"}
945	2020-08-24 07:09:41	En_Estado	"SC"
946	2020-08-24 07:09:41	En_Municipio	"Florian\\u00f3polis"
947	2020-08-24 07:09:41	En_Nome_Logradouro	"Avenida Madre Benvenuta"
948	2020-08-24 07:09:41	En_Bairro	"Santa M\\u00f4nica"
949	2020-08-24 07:09:41	_spaces	[{"id":1,"name":"Museu Sei La","revision":463}]
950	2020-08-24 07:09:42	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":464}
951	2020-08-24 07:12:26	updateTimestamp	{"date":"2020-08-24 07:12:26.000000","timezone_type":3,"timezone":"UTC"}
952	2020-08-24 07:12:26	_spaces	[{"id":1,"name":"Museu Sei La","revision":465}]
953	2020-08-24 07:12:27	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":466}
954	2020-08-24 07:12:27	En_CEP	"01220-010"
955	2020-08-24 07:12:28	updateTimestamp	{"date":"2020-08-24 07:12:28.000000","timezone_type":3,"timezone":"UTC"}
956	2020-08-24 07:12:28	_spaces	[{"id":1,"name":"Museu Sei La","revision":467}]
957	2020-08-24 07:12:29	location	{"latitude":"-23.555110006","longitude":"-46.6282441293"}
958	2020-08-24 07:12:29	updateTimestamp	{"date":"2020-08-24 07:12:29.000000","timezone_type":3,"timezone":"UTC"}
959	2020-08-24 07:12:29	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":468}
960	2020-08-24 07:12:29	En_Bairro	"Rep\\u00fablica"
961	2020-08-24 07:12:29	En_Estado	"SP"
962	2020-08-24 07:12:29	En_Municipio	"S\\u00e3o Paulo"
963	2020-08-24 07:12:29	En_Nome_Logradouro	"Rua Rego Freitas"
964	2020-08-24 07:12:35	updateTimestamp	{"date":"2020-08-24 07:12:35.000000","timezone_type":3,"timezone":"UTC"}
965	2020-08-24 07:12:35	_spaces	[{"id":1,"name":"Museu Sei La","revision":469}]
966	2020-08-24 07:12:35	location	{"latitude":"-23.5465762","longitude":"-46.6467484"}
967	2020-08-24 07:12:35	updateTimestamp	{"date":"2020-08-24 07:12:35.000000","timezone_type":3,"timezone":"UTC"}
968	2020-08-24 07:12:35	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":470}
969	2020-08-24 07:12:35	En_Complemento	"apto"
970	2020-08-24 07:12:35	endereco	"Rua Rego Freitas 530, Rep\\u00fablica, S\\u00e3o Paulo, SP, BR"
971	2020-08-24 07:12:35	En_Num	"530"
972	2020-08-24 07:12:37	updateTimestamp	{"date":"2020-08-24 07:12:36.000000","timezone_type":3,"timezone":"UTC"}
973	2020-08-24 07:12:37	_spaces	[{"id":1,"name":"Museu Sei La","revision":471}]
1285	2020-08-25 21:36:26	dataDeNascimento	""
974	2020-08-24 07:12:37	updateTimestamp	{"date":"2020-08-24 07:12:37.000000","timezone_type":3,"timezone":"UTC"}
975	2020-08-24 07:12:37	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":472}
976	2020-08-24 07:12:37	En_Complemento	"apto d4"
977	2020-08-24 07:12:48	updateTimestamp	{"date":"2020-08-24 07:12:48.000000","timezone_type":3,"timezone":"UTC"}
978	2020-08-24 07:12:48	_spaces	[{"id":1,"name":"Museu Sei La","revision":473}]
979	2020-08-24 07:12:49	updateTimestamp	{"date":"2020-08-24 07:12:49.000000","timezone_type":3,"timezone":"UTC"}
980	2020-08-24 07:12:49	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":474}
981	2020-08-24 07:12:49	En_CEP	"0"
982	2020-08-24 07:12:54	updateTimestamp	{"date":"2020-08-24 07:12:54.000000","timezone_type":3,"timezone":"UTC"}
983	2020-08-24 07:12:54	_spaces	[{"id":1,"name":"Museu Sei La","revision":475}]
984	2020-08-24 07:12:54	updateTimestamp	{"date":"2020-08-24 07:12:54.000000","timezone_type":3,"timezone":"UTC"}
985	2020-08-24 07:12:54	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":476}
986	2020-08-24 07:12:54	En_CEP	"88035-001"
987	2020-08-24 07:12:55	updateTimestamp	{"date":"2020-08-24 07:12:55.000000","timezone_type":3,"timezone":"UTC"}
988	2020-08-24 07:12:55	_spaces	[{"id":1,"name":"Museu Sei La","revision":477}]
989	2020-08-24 07:12:56	location	{"latitude":"-27.6039300012","longitude":"-48.5411803391"}
990	2020-08-24 07:12:56	updateTimestamp	{"date":"2020-08-24 07:12:56.000000","timezone_type":3,"timezone":"UTC"}
991	2020-08-24 07:12:56	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":478}
992	2020-08-24 07:12:56	En_Bairro	"Santa M\\u00f4nica"
993	2020-08-24 07:12:56	En_Estado	"SC"
994	2020-08-24 07:12:56	En_Municipio	"Florian\\u00f3polis"
995	2020-08-24 07:12:56	En_Nome_Logradouro	"Avenida Madre Benvenuta"
996	2020-08-24 07:12:59	updateTimestamp	{"date":"2020-08-24 07:12:59.000000","timezone_type":3,"timezone":"UTC"}
997	2020-08-24 07:12:59	_spaces	[{"id":1,"name":"Museu Sei La","revision":479}]
998	2020-08-24 07:13:00	location	{"latitude":"-27.58886765","longitude":"-48.5069237149848"}
999	2020-08-24 07:13:00	updateTimestamp	{"date":"2020-08-24 07:13:00.000000","timezone_type":3,"timezone":"UTC"}
1000	2020-08-24 07:13:00	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":480}
1001	2020-08-24 07:13:00	endereco	"Avenida Madre Benvenuta 1502, Santa M\\u00f4nica, Florian\\u00f3polis, SC, BR"
1002	2020-08-24 07:13:00	En_Num	"1502"
1003	2020-08-24 07:16:56	updateTimestamp	{"date":"2020-08-24 07:16:56.000000","timezone_type":3,"timezone":"UTC"}
1004	2020-08-24 07:16:56	En_CEP	"01220-010"
1005	2020-08-24 07:16:56	_spaces	[{"id":1,"name":"Museu Sei La","revision":481}]
1006	2020-08-24 07:16:57	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":482}
1007	2020-08-24 07:16:57	En_Bairro	""
1008	2020-08-24 07:16:57	En_CEP	""
1009	2020-08-24 07:16:57	En_Complemento	""
1010	2020-08-24 07:16:57	endereco	""
1011	2020-08-24 07:16:57	En_Estado	""
1012	2020-08-24 07:16:57	En_Municipio	""
1013	2020-08-24 07:16:57	En_Nome_Logradouro	""
1014	2020-08-24 07:16:57	En_Num	""
1015	2020-08-24 07:16:59	location	{"latitude":"-27.58886765","longitude":"-48.5069237149848"}
1016	2020-08-24 07:16:59	updateTimestamp	{"date":"2020-08-24 07:16:58.000000","timezone_type":3,"timezone":"UTC"}
1017	2020-08-24 07:16:59	endereco	"Avenida Madre Benvenuta 1502, Santa M\\u00f4nica, Florian\\u00f3polis, SC, BR"
1018	2020-08-24 07:16:59	_spaces	[{"id":1,"name":"Museu Sei La","revision":483}]
1019	2020-08-24 07:16:59	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":484}
1020	2020-08-24 07:17:06	location	{"latitude":"-23.555110006","longitude":"-46.6282441293"}
1021	2020-08-24 07:17:06	updateTimestamp	{"date":"2020-08-24 07:17:06.000000","timezone_type":3,"timezone":"UTC"}
1022	2020-08-24 07:17:06	En_Estado	"SP"
1023	2020-08-24 07:17:06	En_Municipio	"S\\u00e3o Paulo"
1024	2020-08-24 07:17:06	En_Nome_Logradouro	"Rua Rego Freitas"
1025	2020-08-24 07:17:06	En_Bairro	"Rep\\u00fablica"
1026	2020-08-24 07:17:06	endereco	"Rua Rego Freitas 1502, Rep\\u00fablica, S\\u00e3o Paulo, SP, BR"
1027	2020-08-24 07:17:06	_spaces	[{"id":1,"name":"Museu Sei La","revision":485}]
1028	2020-08-24 07:17:07	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":486}
1029	2020-08-24 07:17:13	updateTimestamp	{"date":"2020-08-24 07:17:13.000000","timezone_type":3,"timezone":"UTC"}
1030	2020-08-24 07:17:13	En_Num	"530"
1031	2020-08-24 07:17:13	_spaces	[{"id":1,"name":"Museu Sei La","revision":487}]
1032	2020-08-24 07:17:13	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":488}
1033	2020-08-24 07:17:14	location	{"latitude":"-23.5465762","longitude":"-46.6467484"}
1034	2020-08-24 07:17:14	updateTimestamp	{"date":"2020-08-24 07:17:14.000000","timezone_type":3,"timezone":"UTC"}
1035	2020-08-24 07:17:14	endereco	"Rua Rego Freitas 530, Rep\\u00fablica, S\\u00e3o Paulo, SP, BR"
1036	2020-08-24 07:17:14	_spaces	[{"id":1,"name":"Museu Sei La","revision":489}]
1037	2020-08-24 07:17:15	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":490}
1038	2020-08-24 07:18:09	updateTimestamp	{"date":"2020-08-24 07:18:09.000000","timezone_type":3,"timezone":"UTC"}
1039	2020-08-24 07:18:09	_spaces	[{"id":1,"name":"Museu Sei La","revision":491}]
1040	2020-08-24 07:18:09	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":492}
1041	2020-08-24 07:18:16	updateTimestamp	{"date":"2020-08-24 07:18:15.000000","timezone_type":3,"timezone":"UTC"}
1042	2020-08-24 07:18:16	En_CEP	"88035-001"
1043	2020-08-24 07:18:16	_spaces	[{"id":1,"name":"Museu Sei La","revision":493}]
1044	2020-08-24 07:18:16	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":494}
1045	2020-08-24 07:18:22	location	{"latitude":"-27.6039300012","longitude":"-48.5411803391"}
1046	2020-08-24 07:18:22	updateTimestamp	{"date":"2020-08-24 07:18:22.000000","timezone_type":3,"timezone":"UTC"}
1047	2020-08-24 07:18:22	En_Estado	"SC"
1048	2020-08-24 07:18:22	En_Municipio	"Florian\\u00f3polis"
1049	2020-08-24 07:18:22	En_Nome_Logradouro	"Avenida Madre Benvenuta"
1050	2020-08-24 07:18:22	En_Bairro	"Santa M\\u00f4nica"
1051	2020-08-24 07:18:22	endereco	"Avenida Madre Benvenuta 530, Santa M\\u00f4nica, Florian\\u00f3polis, SC, BR"
1052	2020-08-24 07:18:22	_spaces	[{"id":1,"name":"Museu Sei La","revision":495}]
1053	2020-08-24 07:18:22	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":496}
1054	2020-08-24 07:18:48	updateTimestamp	{"date":"2020-08-24 07:18:48.000000","timezone_type":3,"timezone":"UTC"}
1055	2020-08-24 07:18:48	En_CEP	"01220-010"
1056	2020-08-24 07:18:48	_spaces	[{"id":1,"name":"Museu Sei La","revision":497}]
1057	2020-08-24 07:18:48	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":498}
1058	2020-08-24 07:18:55	updateTimestamp	{"date":"2020-08-24 07:18:55.000000","timezone_type":3,"timezone":"UTC"}
1059	2020-08-24 07:18:55	En_Estado	"SP"
1060	2020-08-24 07:18:55	En_Municipio	"S\\u00e3o Paulo"
1061	2020-08-24 07:18:55	En_Nome_Logradouro	"Rua Rego Freitas"
1062	2020-08-24 07:18:55	En_Bairro	"Rep\\u00fablica"
1063	2020-08-24 07:18:55	_spaces	[{"id":1,"name":"Museu Sei La","revision":499}]
1064	2020-08-24 07:18:55	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":500}
1065	2020-08-24 07:23:17	updateTimestamp	{"date":"2020-08-24 07:23:17.000000","timezone_type":3,"timezone":"UTC"}
1066	2020-08-24 07:23:17	En_CEP	"88035-001"
1067	2020-08-24 07:23:17	_spaces	[{"id":1,"name":"Museu Sei La","revision":501}]
1068	2020-08-24 07:23:17	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":502}
1069	2020-08-24 07:23:42	updateTimestamp	{"date":"2020-08-24 07:23:42.000000","timezone_type":3,"timezone":"UTC"}
1070	2020-08-24 07:23:42	En_CEP	"01220-010"
1071	2020-08-24 07:23:42	_spaces	[{"id":1,"name":"Museu Sei La","revision":503}]
1072	2020-08-24 07:23:43	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":504}
1073	2020-08-24 07:24:15	updateTimestamp	{"date":"2020-08-24 07:24:15.000000","timezone_type":3,"timezone":"UTC"}
1074	2020-08-24 07:24:15	En_CEP	"88035-001"
1075	2020-08-24 07:24:15	_spaces	[{"id":1,"name":"Museu Sei La","revision":505}]
1076	2020-08-24 07:24:16	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":506}
1077	2020-08-24 07:24:19	updateTimestamp	{"date":"2020-08-24 07:24:19.000000","timezone_type":3,"timezone":"UTC"}
1078	2020-08-24 07:24:19	En_Estado	"SC"
1079	2020-08-24 07:24:19	En_Municipio	"Florian\\u00f3polis"
1080	2020-08-24 07:24:19	En_Nome_Logradouro	"Avenida Madre Benvenuta"
1081	2020-08-24 07:24:19	En_Bairro	"Santa M\\u00f4nica"
1082	2020-08-24 07:24:19	_spaces	[{"id":1,"name":"Museu Sei La","revision":507}]
1083	2020-08-24 07:24:20	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":508}
1084	2020-08-24 07:24:29	updateTimestamp	{"date":"2020-08-24 07:24:29.000000","timezone_type":3,"timezone":"UTC"}
1085	2020-08-24 07:24:29	En_CEP	"01220-010"
1086	2020-08-24 07:24:29	_spaces	[{"id":1,"name":"Museu Sei La","revision":509}]
1087	2020-08-24 07:24:30	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":510}
1088	2020-08-24 07:24:43	updateTimestamp	{"date":"2020-08-24 07:24:43.000000","timezone_type":3,"timezone":"UTC"}
1089	2020-08-24 07:24:43	En_Estado	"SP"
1090	2020-08-24 07:24:43	En_Municipio	"S\\u00e3o Paulo"
1091	2020-08-24 07:24:43	En_Nome_Logradouro	"Rua Rego Freitas"
1092	2020-08-24 07:24:43	En_Bairro	"Rep\\u00fablica"
1093	2020-08-24 07:24:43	_spaces	[{"id":1,"name":"Museu Sei La","revision":511}]
1094	2020-08-24 07:24:44	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":512}
1095	2020-08-24 07:25:01	updateTimestamp	{"date":"2020-08-24 07:25:01.000000","timezone_type":3,"timezone":"UTC"}
1096	2020-08-24 07:25:01	En_CEP	"05453-060"
1097	2020-08-24 07:25:01	_spaces	[{"id":1,"name":"Museu Sei La","revision":513}]
1098	2020-08-24 07:25:01	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":514}
1099	2020-08-24 07:25:05	updateTimestamp	{"date":"2020-08-24 07:25:05.000000","timezone_type":3,"timezone":"UTC"}
1100	2020-08-24 07:25:05	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
1101	2020-08-24 07:25:05	En_Bairro	"Vila Madalena"
1102	2020-08-24 07:25:05	_spaces	[{"id":1,"name":"Museu Sei La","revision":515}]
1103	2020-08-24 07:25:05	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":516}
1104	2020-08-24 07:25:44	updateTimestamp	{"date":"2020-08-24 07:25:44.000000","timezone_type":3,"timezone":"UTC"}
1105	2020-08-24 07:25:44	En_CEP	"05453-061"
1106	2020-08-24 07:25:44	_spaces	[{"id":1,"name":"Museu Sei La","revision":517}]
1107	2020-08-24 07:25:45	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":518}
1108	2020-08-24 07:28:01	updateTimestamp	{"date":"2020-08-24 07:28:01.000000","timezone_type":3,"timezone":"UTC"}
1109	2020-08-24 07:28:01	En_CEP	"05453-060"
1110	2020-08-24 07:28:01	_spaces	[{"id":1,"name":"Museu Sei La","revision":519}]
1111	2020-08-24 07:28:01	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":520}
1112	2020-08-24 07:29:31	updateTimestamp	{"date":"2020-08-24 07:29:31.000000","timezone_type":3,"timezone":"UTC"}
1113	2020-08-24 07:29:31	_spaces	[{"id":1,"name":"Museu Sei La","revision":521}]
1114	2020-08-24 07:29:31	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":522}
1115	2020-08-24 07:29:39	updateTimestamp	{"date":"2020-08-24 07:29:39.000000","timezone_type":3,"timezone":"UTC"}
1116	2020-08-24 07:29:39	En_Complemento	"apto 91A"
1117	2020-08-24 07:29:39	_spaces	[{"id":1,"name":"Museu Sei La","revision":523}]
1118	2020-08-24 07:29:39	owner	{"id":4,"name":"Rafael Chaves","shortDescription":"RAFA","revision":524}
1119	2020-08-24 18:05:03	_type	2
1120	2020-08-24 18:05:03	name	"Cooletivo"
1121	2020-08-24 18:05:03	publicLocation	false
1122	2020-08-24 18:05:03	location	{"latitude":"0","longitude":"0"}
1123	2020-08-24 18:05:03	shortDescription	"Cooletivo \\u00e9 uma cooperativa massa"
1124	2020-08-24 18:05:03	longDescription	null
1125	2020-08-24 18:05:03	createTimestamp	{"date":"2020-08-24 18:05:02.000000","timezone_type":3,"timezone":"UTC"}
1126	2020-08-24 18:05:03	status	1
1127	2020-08-24 18:05:03	updateTimestamp	null
1128	2020-08-24 18:05:03	_subsiteId	null
1129	2020-08-24 18:05:03	_terms	{"":["Comunica\\u00e7\\u00e3o"]}
1130	2020-08-24 18:15:56	name	""
1131	2020-08-24 18:15:56	updateTimestamp	{"date":"2020-08-24 18:15:56.000000","timezone_type":3,"timezone":"UTC"}
1132	2020-08-24 18:15:56	En_Bairro	"b"
1136	2020-08-24 18:17:22	updateTimestamp	{"date":"2020-08-24 18:17:22.000000","timezone_type":3,"timezone":"UTC"}
1137	2020-08-24 18:17:22	En_Bairro	""
1138	2020-08-24 18:17:22	En_CEP	""
1139	2020-08-24 18:21:36	updateTimestamp	{"date":"2020-08-24 18:21:36.000000","timezone_type":3,"timezone":"UTC"}
1140	2020-08-24 18:21:36	updateTimestamp	{"date":"2020-08-24 18:21:36.000000","timezone_type":3,"timezone":"UTC"}
1141	2020-08-24 18:21:36	En_CEP	"01220-010"
1142	2020-08-24 18:21:45	updateTimestamp	{"date":"2020-08-24 18:21:45.000000","timezone_type":3,"timezone":"UTC"}
1143	2020-08-24 18:21:46	updateTimestamp	{"date":"2020-08-24 18:21:46.000000","timezone_type":3,"timezone":"UTC"}
1144	2020-08-24 18:21:46	En_Bairro	"Rep\\u00fablica"
1145	2020-08-24 18:21:46	En_Nome_Logradouro	"Rua Rego Freitas"
1146	2020-08-24 18:21:46	En_Municipio	"S\\u00e3o Paulo"
1147	2020-08-24 18:21:46	En_Estado	"SP"
1148	2020-08-24 18:21:52	updateTimestamp	{"date":"2020-08-24 18:21:52.000000","timezone_type":3,"timezone":"UTC"}
1149	2020-08-24 18:21:52	updateTimestamp	{"date":"2020-08-24 18:21:52.000000","timezone_type":3,"timezone":"UTC"}
1150	2020-08-24 18:21:52	En_Num	"530"
1151	2020-08-24 18:21:55	updateTimestamp	{"date":"2020-08-24 18:21:55.000000","timezone_type":3,"timezone":"UTC"}
1152	2020-08-24 18:21:55	updateTimestamp	{"date":"2020-08-24 18:21:55.000000","timezone_type":3,"timezone":"UTC"}
1153	2020-08-24 18:21:55	En_Complemento	"apto D4"
1154	2020-08-24 18:25:48	updateTimestamp	{"date":"2020-08-24 18:25:48.000000","timezone_type":3,"timezone":"UTC"}
1155	2020-08-24 18:25:48	updateTimestamp	{"date":"2020-08-24 18:25:48.000000","timezone_type":3,"timezone":"UTC"}
1156	2020-08-24 18:28:35	publicLocation	true
1157	2020-08-24 18:28:35	updateTimestamp	{"date":"2020-08-24 18:28:35.000000","timezone_type":3,"timezone":"UTC"}
1158	2020-08-24 18:28:35	publicLocation	true
1159	2020-08-24 18:28:35	updateTimestamp	{"date":"2020-08-24 18:28:35.000000","timezone_type":3,"timezone":"UTC"}
1160	2020-08-24 18:29:08	updateTimestamp	{"date":"2020-08-24 18:29:08.000000","timezone_type":3,"timezone":"UTC"}
1161	2020-08-24 18:29:08	updateTimestamp	{"date":"2020-08-24 18:29:08.000000","timezone_type":3,"timezone":"UTC"}
1162	2020-08-24 18:30:49	updateTimestamp	{"date":"2020-08-24 18:30:49.000000","timezone_type":3,"timezone":"UTC"}
1163	2020-08-24 18:30:50	updateTimestamp	{"date":"2020-08-24 18:30:50.000000","timezone_type":3,"timezone":"UTC"}
1164	2020-08-24 18:30:58	updateTimestamp	{"date":"2020-08-24 18:30:58.000000","timezone_type":3,"timezone":"UTC"}
1165	2020-08-24 18:30:59	publicLocation	false
1166	2020-08-24 18:30:59	updateTimestamp	{"date":"2020-08-24 18:30:58.000000","timezone_type":3,"timezone":"UTC"}
1167	2020-08-24 18:31:31	updateTimestamp	{"date":"2020-08-24 18:31:31.000000","timezone_type":3,"timezone":"UTC"}
1168	2020-08-24 18:31:31	publicLocation	true
1169	2020-08-24 18:31:31	updateTimestamp	{"date":"2020-08-24 18:31:31.000000","timezone_type":3,"timezone":"UTC"}
1170	2020-08-24 19:20:35	updateTimestamp	{"date":"2020-08-24 19:20:35.000000","timezone_type":3,"timezone":"UTC"}
1171	2020-08-24 19:20:35	En_CEP	"88035-001"
1172	2020-08-24 19:20:35	updateTimestamp	{"date":"2020-08-24 19:20:35.000000","timezone_type":3,"timezone":"UTC"}
1173	2020-08-24 19:20:37	updateTimestamp	{"date":"2020-08-24 19:20:37.000000","timezone_type":3,"timezone":"UTC"}
1174	2020-08-24 19:20:37	En_Municipio	"Florian\\u00f3polis"
1175	2020-08-24 19:20:37	En_Estado	"SC"
1176	2020-08-24 19:20:37	En_Nome_Logradouro	"Avenida Madre Benvenuta"
1177	2020-08-24 19:20:37	En_Bairro	"Santa M\\u00f4nica"
1178	2020-08-24 19:20:37	updateTimestamp	{"date":"2020-08-24 19:20:37.000000","timezone_type":3,"timezone":"UTC"}
1179	2020-08-24 19:20:40	updateTimestamp	{"date":"2020-08-24 19:20:40.000000","timezone_type":3,"timezone":"UTC"}
1180	2020-08-24 19:20:40	En_Num	"1502"
1181	2020-08-24 19:20:40	updateTimestamp	{"date":"2020-08-24 19:20:40.000000","timezone_type":3,"timezone":"UTC"}
1182	2020-08-24 19:20:48	updateTimestamp	{"date":"2020-08-24 19:20:48.000000","timezone_type":3,"timezone":"UTC"}
1183	2020-08-24 19:20:48	updateTimestamp	{"date":"2020-08-24 19:20:48.000000","timezone_type":3,"timezone":"UTC"}
1184	2020-08-24 19:20:56	updateTimestamp	{"date":"2020-08-24 19:20:56.000000","timezone_type":3,"timezone":"UTC"}
1185	2020-08-24 19:20:57	updateTimestamp	{"date":"2020-08-24 19:20:57.000000","timezone_type":3,"timezone":"UTC"}
1186	2020-08-24 19:21:00	updateTimestamp	{"date":"2020-08-24 19:21:00.000000","timezone_type":3,"timezone":"UTC"}
1187	2020-08-24 19:21:00	updateTimestamp	{"date":"2020-08-24 19:21:00.000000","timezone_type":3,"timezone":"UTC"}
1188	2020-08-24 19:21:09	updateTimestamp	{"date":"2020-08-24 19:21:09.000000","timezone_type":3,"timezone":"UTC"}
1189	2020-08-24 19:21:09	updateTimestamp	{"date":"2020-08-24 19:21:09.000000","timezone_type":3,"timezone":"UTC"}
1190	2020-08-24 19:21:13	updateTimestamp	{"date":"2020-08-24 19:21:13.000000","timezone_type":3,"timezone":"UTC"}
1191	2020-08-24 19:21:13	updateTimestamp	{"date":"2020-08-24 19:21:13.000000","timezone_type":3,"timezone":"UTC"}
1192	2020-08-24 19:21:17	updateTimestamp	{"date":"2020-08-24 19:21:17.000000","timezone_type":3,"timezone":"UTC"}
1193	2020-08-24 19:21:17	updateTimestamp	{"date":"2020-08-24 19:21:17.000000","timezone_type":3,"timezone":"UTC"}
1194	2020-08-24 19:21:20	updateTimestamp	{"date":"2020-08-24 19:21:20.000000","timezone_type":3,"timezone":"UTC"}
1195	2020-08-24 19:21:20	updateTimestamp	{"date":"2020-08-24 19:21:20.000000","timezone_type":3,"timezone":"UTC"}
1196	2020-08-24 19:36:23	updateTimestamp	{"date":"2020-08-24 19:36:23.000000","timezone_type":3,"timezone":"UTC"}
1197	2020-08-24 19:36:23	En_Municipio	""
1198	2020-08-24 19:36:23	En_Estado	""
1199	2020-08-24 19:36:23	En_Num	""
1200	2020-08-24 19:36:23	En_CEP	""
1201	2020-08-24 19:36:23	En_Nome_Logradouro	""
1202	2020-08-24 19:36:23	En_Bairro	""
1203	2020-08-24 19:36:23	updateTimestamp	{"date":"2020-08-24 19:36:23.000000","timezone_type":3,"timezone":"UTC"}
1204	2020-08-24 19:36:23	En_CEP	""
1205	2020-08-24 19:36:29	updateTimestamp	{"date":"2020-08-24 19:36:29.000000","timezone_type":3,"timezone":"UTC"}
1206	2020-08-24 19:36:29	updateTimestamp	{"date":"2020-08-24 19:36:29.000000","timezone_type":3,"timezone":"UTC"}
1207	2020-08-24 19:36:29	En_CEP	"60"
1208	2020-08-24 19:36:34	updateTimestamp	{"date":"2020-08-24 19:36:34.000000","timezone_type":3,"timezone":"UTC"}
1209	2020-08-24 19:36:34	updateTimestamp	{"date":"2020-08-24 19:36:34.000000","timezone_type":3,"timezone":"UTC"}
1210	2020-08-24 19:36:34	En_CEP	"60730"
1211	2020-08-24 19:36:37	updateTimestamp	{"date":"2020-08-24 19:36:37.000000","timezone_type":3,"timezone":"UTC"}
1212	2020-08-24 19:36:37	updateTimestamp	{"date":"2020-08-24 19:36:37.000000","timezone_type":3,"timezone":"UTC"}
1213	2020-08-24 19:36:37	En_CEP	"60730-714"
1214	2020-08-24 19:37:13	updateTimestamp	{"date":"2020-08-24 19:37:13.000000","timezone_type":3,"timezone":"UTC"}
1215	2020-08-24 19:37:13	updateTimestamp	{"date":"2020-08-24 19:37:13.000000","timezone_type":3,"timezone":"UTC"}
1216	2020-08-24 19:37:26	updateTimestamp	{"date":"2020-08-24 19:37:26.000000","timezone_type":3,"timezone":"UTC"}
1217	2020-08-24 19:37:27	updateTimestamp	{"date":"2020-08-24 19:37:26.000000","timezone_type":3,"timezone":"UTC"}
1218	2020-08-24 19:37:27	En_CEP	"60"
1219	2020-08-24 19:37:29	updateTimestamp	{"date":"2020-08-24 19:37:29.000000","timezone_type":3,"timezone":"UTC"}
1220	2020-08-24 19:37:29	updateTimestamp	{"date":"2020-08-24 19:37:29.000000","timezone_type":3,"timezone":"UTC"}
1221	2020-08-24 19:37:29	En_CEP	"60015"
1222	2020-08-24 19:37:31	updateTimestamp	{"date":"2020-08-24 19:37:31.000000","timezone_type":3,"timezone":"UTC"}
1223	2020-08-24 19:37:31	updateTimestamp	{"date":"2020-08-24 19:37:31.000000","timezone_type":3,"timezone":"UTC"}
1224	2020-08-24 19:37:31	En_CEP	"60015-051"
1225	2020-08-24 19:37:36	updateTimestamp	{"date":"2020-08-24 19:37:36.000000","timezone_type":3,"timezone":"UTC"}
1226	2020-08-24 19:37:36	updateTimestamp	{"date":"2020-08-24 19:37:36.000000","timezone_type":3,"timezone":"UTC"}
1227	2020-08-24 19:37:36	En_Bairro	"Centro"
1228	2020-08-24 19:37:36	En_Nome_Logradouro	"Avenida Imperador"
1229	2020-08-24 19:37:36	En_Municipio	"Fortaleza"
1230	2020-08-24 19:37:36	En_Estado	"CE"
1231	2020-08-24 19:38:04	updateTimestamp	{"date":"2020-08-24 19:38:04.000000","timezone_type":3,"timezone":"UTC"}
1232	2020-08-24 19:38:04	updateTimestamp	{"date":"2020-08-24 19:38:04.000000","timezone_type":3,"timezone":"UTC"}
1233	2020-08-24 19:38:42	updateTimestamp	{"date":"2020-08-24 19:38:42.000000","timezone_type":3,"timezone":"UTC"}
1234	2020-08-24 19:38:43	updateTimestamp	{"date":"2020-08-24 19:38:43.000000","timezone_type":3,"timezone":"UTC"}
1235	2020-08-24 19:38:43	En_CEP	"60015"
1236	2020-08-24 19:38:44	updateTimestamp	{"date":"2020-08-24 19:38:44.000000","timezone_type":3,"timezone":"UTC"}
1237	2020-08-24 19:38:44	updateTimestamp	{"date":"2020-08-24 19:38:44.000000","timezone_type":3,"timezone":"UTC"}
1238	2020-08-24 19:38:44	En_CEP	""
1239	2020-08-24 19:38:46	updateTimestamp	{"date":"2020-08-24 19:38:46.000000","timezone_type":3,"timezone":"UTC"}
1240	2020-08-24 19:38:46	updateTimestamp	{"date":"2020-08-24 19:38:46.000000","timezone_type":3,"timezone":"UTC"}
1241	2020-08-24 19:38:46	En_CEP	"60"
1242	2020-08-24 19:38:48	updateTimestamp	{"date":"2020-08-24 19:38:48.000000","timezone_type":3,"timezone":"UTC"}
1243	2020-08-24 19:38:49	updateTimestamp	{"date":"2020-08-24 19:38:48.000000","timezone_type":3,"timezone":"UTC"}
1244	2020-08-24 19:38:49	En_CEP	"60730"
1245	2020-08-24 19:38:51	updateTimestamp	{"date":"2020-08-24 19:38:51.000000","timezone_type":3,"timezone":"UTC"}
1246	2020-08-24 19:38:51	updateTimestamp	{"date":"2020-08-24 19:38:51.000000","timezone_type":3,"timezone":"UTC"}
1247	2020-08-24 19:38:51	En_CEP	"60730-714"
1248	2020-08-24 19:39:07	updateTimestamp	{"date":"2020-08-24 19:39:07.000000","timezone_type":3,"timezone":"UTC"}
1249	2020-08-24 19:39:07	updateTimestamp	{"date":"2020-08-24 19:39:07.000000","timezone_type":3,"timezone":"UTC"}
1250	2020-08-24 19:39:07	En_CEP	"60714"
1251	2020-08-24 19:39:09	updateTimestamp	{"date":"2020-08-24 19:39:09.000000","timezone_type":3,"timezone":"UTC"}
1252	2020-08-24 19:39:10	updateTimestamp	{"date":"2020-08-24 19:39:10.000000","timezone_type":3,"timezone":"UTC"}
1253	2020-08-24 19:39:10	En_CEP	"60714-730"
1254	2020-08-24 19:39:11	updateTimestamp	{"date":"2020-08-24 19:39:11.000000","timezone_type":3,"timezone":"UTC"}
1255	2020-08-24 19:39:11	updateTimestamp	{"date":"2020-08-24 19:39:11.000000","timezone_type":3,"timezone":"UTC"}
1256	2020-08-24 19:39:11	En_Bairro	"Dend\\u00ea"
1257	2020-08-24 19:39:11	En_Nome_Logradouro	"Rua Campo Maior"
1258	2020-08-24 19:39:53	updateTimestamp	{"date":"2020-08-24 19:39:53.000000","timezone_type":3,"timezone":"UTC"}
1259	2020-08-24 19:39:53	updateTimestamp	{"date":"2020-08-24 19:39:53.000000","timezone_type":3,"timezone":"UTC"}
1260	2020-08-24 19:39:56	updateTimestamp	{"date":"2020-08-24 19:39:55.000000","timezone_type":3,"timezone":"UTC"}
1261	2020-08-24 19:39:56	updateTimestamp	{"date":"2020-08-24 19:39:56.000000","timezone_type":3,"timezone":"UTC"}
1262	2020-08-24 21:56:07	updateTimestamp	{"date":"2020-08-24 21:56:07.000000","timezone_type":3,"timezone":"UTC"}
1263	2020-08-24 21:56:07	En_CEP	"01220-010"
1264	2020-08-24 21:56:07	updateTimestamp	{"date":"2020-08-24 21:56:07.000000","timezone_type":3,"timezone":"UTC"}
1265	2020-08-24 21:56:16	updateTimestamp	{"date":"2020-08-24 21:56:16.000000","timezone_type":3,"timezone":"UTC"}
1266	2020-08-24 21:56:16	En_Municipio	"S\\u00e3o Paulo"
1267	2020-08-24 21:56:16	En_Estado	"SP"
1268	2020-08-24 21:56:16	En_Nome_Logradouro	"Rua Rego Freitas"
1269	2020-08-24 21:56:16	En_Bairro	"Rep\\u00fablica"
1270	2020-08-24 21:56:16	updateTimestamp	{"date":"2020-08-24 21:56:16.000000","timezone_type":3,"timezone":"UTC"}
1271	2020-08-25 21:36:25	_spaces	[{"id":1,"name":"Museu Sei La","revision":525}]
1272	2020-08-25 21:36:25	nomeCompleto	"Rafael Chaves Fretias"
1273	2020-08-25 21:36:25	En_Num	""
1274	2020-08-25 21:36:25	endereco	""
1275	2020-08-25 21:36:25	En_Estado	""
1276	2020-08-25 21:36:25	En_Municipio	""
1277	2020-08-25 21:36:25	En_Nome_Logradouro	""
1278	2020-08-25 21:36:25	En_Bairro	""
1279	2020-08-25 21:36:25	En_CEP	""
1280	2020-08-25 21:36:25	En_Complemento	""
1281	2020-08-25 21:36:25	documento	""
1282	2020-08-25 21:36:25	name	""
1283	2020-08-25 21:36:25	updateTimestamp	{"date":"2020-08-25 21:36:25.000000","timezone_type":3,"timezone":"UTC"}
1284	2020-08-25 21:36:26	raca	""
1286	2020-08-25 21:36:26	genero	""
1287	2020-08-25 21:36:50	telefone1	"\\"\\""
1288	2020-08-25 21:36:50	nomeCompleto	"\\"Rafael Chaves Fretias\\""
1289	2020-08-25 21:36:51	name	"\\"\\""
1290	2020-08-25 21:36:51	updateTimestamp	{"date":"2020-08-25 21:36:51.000000","timezone_type":3,"timezone":"UTC"}
1291	2020-08-25 21:36:51	raca	"\\"\\""
1292	2020-08-25 21:36:51	dataDeNascimento	"\\"\\""
1293	2020-08-25 21:36:51	telefone2	"\\"\\""
1294	2020-08-25 21:36:51	emailPrivado	"\\"\\""
1295	2020-08-25 21:36:51	genero	"\\"\\""
1296	2020-08-25 21:36:55	name	""
1297	2020-08-25 21:36:55	updateTimestamp	{"date":"2020-08-25 21:36:55.000000","timezone_type":3,"timezone":"UTC"}
1298	2020-08-25 21:38:08	name	"Rafa Chaves"
1299	2020-08-25 21:38:08	updateTimestamp	{"date":"2020-08-25 21:38:08.000000","timezone_type":3,"timezone":"UTC"}
1300	2020-08-25 21:38:08	telefone1	""
1301	2020-08-25 21:38:08	raca	"Branca"
1302	2020-08-25 21:38:08	dataDeNascimento	"2020-08-19"
1303	2020-08-25 21:38:08	telefone2	""
1304	2020-08-25 21:38:08	emailPrivado	""
1305	2020-08-25 21:41:33	updateTimestamp	{"date":"2020-08-25 21:41:33.000000","timezone_type":3,"timezone":"UTC"}
1306	2020-08-25 21:41:33	documento	"050.913.009-70"
1307	2020-08-25 21:41:47	nomeCompleto	"Rafael Chaves Fretias"
1308	2020-08-25 21:41:47	publicLocation	true
1309	2020-08-25 21:41:47	updateTimestamp	{"date":"2020-08-25 21:41:47.000000","timezone_type":3,"timezone":"UTC"}
1310	2020-08-25 21:41:55	nomeCompleto	"Rafael Chaves Freitas"
1311	2020-08-25 21:41:55	updateTimestamp	{"date":"2020-08-25 21:41:55.000000","timezone_type":3,"timezone":"UTC"}
1312	2020-08-25 21:42:19	updateTimestamp	{"date":"2020-08-25 21:42:19.000000","timezone_type":3,"timezone":"UTC"}
1313	2020-08-25 21:42:52	_type	1
1314	2020-08-25 21:42:52	name	"Sardinha"
1315	2020-08-25 21:42:52	publicLocation	false
1316	2020-08-25 21:42:52	location	{"latitude":0,"longitude":0}
1317	2020-08-25 21:42:52	shortDescription	null
1318	2020-08-25 21:42:52	longDescription	null
1319	2020-08-25 21:42:52	createTimestamp	{"date":"2020-08-25 21:42:52.703598","timezone_type":3,"timezone":"UTC"}
1320	2020-08-25 21:42:52	status	1
1321	2020-08-25 21:42:52	updateTimestamp	null
1322	2020-08-25 21:42:52	_subsiteId	null
1323	2020-08-25 21:42:52	location	{"latitude":"0","longitude":"0"}
1324	2020-08-25 21:42:52	createTimestamp	{"date":"2020-08-25 21:42:52.000000","timezone_type":3,"timezone":"UTC"}
1325	2020-08-25 21:45:07	location	{"latitude":"-23.5465762","longitude":"-46.6467484"}
1326	2020-08-25 21:45:08	shortDescription	"Uma monstra demon\\u00edaca"
1327	2020-08-25 21:45:08	longDescription	""
1328	2020-08-25 21:45:08	updateTimestamp	{"date":"2020-08-25 21:45:07.000000","timezone_type":3,"timezone":"UTC"}
1329	2020-08-25 21:45:08	nomeCompleto	"Sarda Medeiros"
1330	2020-08-25 21:45:08	documento	"666.666.666-66"
1331	2020-08-25 21:45:08	dataDeNascimento	"2020-01-27"
1332	2020-08-25 21:45:08	genero	"Mulher"
1333	2020-08-25 21:45:08	orientacaoSexual	"Outras"
1334	2020-08-25 21:45:08	raca	"Preta"
1335	2020-08-25 21:45:08	emailPrivado	"sarda@email.com"
1336	2020-08-25 21:45:08	telefone1	"(11) 99223-2123"
1337	2020-08-25 21:45:08	endereco	"Rua Rego Freitas, 530, apto D4, Rep\\u00fablica, 01220-010, S\\u00e3o Paulo, SP"
1338	2020-08-25 21:45:08	En_CEP	"01220-010"
1339	2020-08-25 21:45:08	En_Nome_Logradouro	"Rua Rego Freitas"
1340	2020-08-25 21:45:08	En_Num	"530"
1341	2020-08-25 21:45:08	En_Complemento	"apto D4"
1342	2020-08-25 21:45:08	En_Bairro	"Rep\\u00fablica"
1343	2020-08-25 21:45:08	En_Municipio	"S\\u00e3o Paulo"
1344	2020-08-25 21:45:08	En_Estado	"SP"
1345	2020-08-25 21:45:08	_terms	{"":["Arquitetura-Urbanismo"]}
1346	2020-08-25 21:45:23	aldirblanc_inciso1_registration	"1970483263"
1347	2020-08-25 21:53:27	publicLocation	true
1348	2020-08-25 21:53:27	updateTimestamp	{"date":"2020-08-25 21:53:27.000000","timezone_type":3,"timezone":"UTC"}
1349	2020-08-25 21:53:28	dataDeNascimento	""
1350	2020-08-25 21:58:12	updateTimestamp	{"date":"2020-08-25 21:58:12.000000","timezone_type":3,"timezone":"UTC"}
1351	2020-08-25 21:58:12	dataDeNascimento	"2020-01-27"
1352	2020-08-25 23:50:08	updateTimestamp	{"date":"2020-08-25 23:50:08.000000","timezone_type":3,"timezone":"UTC"}
1353	2020-08-26 01:14:40	name	""
1354	2020-08-26 01:14:40	updateTimestamp	{"date":"2020-08-26 00:49:57.000000","timezone_type":3,"timezone":"UTC"}
1355	2020-08-26 01:14:40	genero	"ASDASDASD"
1356	2020-08-26 01:14:52	name	"asd"
1357	2020-08-26 01:14:52	updateTimestamp	{"date":"2020-08-26 01:14:52.000000","timezone_type":3,"timezone":"UTC"}
1358	2020-08-26 01:33:41	name	""
1359	2020-08-26 01:33:41	updateTimestamp	{"date":"2020-08-26 01:33:41.000000","timezone_type":3,"timezone":"UTC"}
1360	2020-08-26 01:35:52	name	"Rafael"
1361	2020-08-26 01:35:52	updateTimestamp	{"date":"2020-08-26 01:35:52.000000","timezone_type":3,"timezone":"UTC"}
1362	2020-08-26 01:42:44	updateTimestamp	{"date":"2020-08-26 01:42:44.000000","timezone_type":3,"timezone":"UTC"}
1363	2020-08-26 01:43:00	updateTimestamp	{"date":"2020-08-26 01:43:00.000000","timezone_type":3,"timezone":"UTC"}
1364	2020-08-26 01:43:00	name	"Ser\\u00e1?"
1365	2020-08-26 01:43:09	updateTimestamp	{"date":"2020-08-26 01:43:09.000000","timezone_type":3,"timezone":"UTC"}
1366	2020-08-26 02:03:01	name	"asd"
1367	2020-08-26 02:03:01	updateTimestamp	{"date":"2020-08-26 02:03:01.000000","timezone_type":3,"timezone":"UTC"}
1368	2020-08-26 02:05:17	documento	"asd"
1369	2020-08-26 02:13:03	documento	" "
1370	2020-08-26 02:13:15	documento	"asd"
1371	2020-08-26 02:13:42	updateTimestamp	{"date":"2020-08-26 02:13:41.000000","timezone_type":3,"timezone":"UTC"}
1372	2020-08-26 02:13:42	documento	"666.666.666-66"
1373	2020-08-26 02:15:26	telefone1	"asdasdasd"
1374	2020-08-26 02:15:27	updateTimestamp	{"date":"2020-08-26 02:15:27.000000","timezone_type":3,"timezone":"UTC"}
1375	2020-08-26 02:15:34	updateTimestamp	{"date":"2020-08-26 02:15:34.000000","timezone_type":3,"timezone":"UTC"}
1376	2020-08-26 02:17:57	documento	"asd"
1473	2020-08-26 07:06:58	_subsiteId	null
1377	2020-08-26 02:18:26	updateTimestamp	{"date":"2020-08-26 02:18:26.000000","timezone_type":3,"timezone":"UTC"}
1378	2020-08-26 02:18:30	updateTimestamp	{"date":"2020-08-26 02:18:30.000000","timezone_type":3,"timezone":"UTC"}
1379	2020-08-26 02:18:30	documento	"050.913.009-70"
1380	2020-08-26 03:54:33	telefone1	"1199999999"
1381	2020-08-26 03:54:34	updateTimestamp	{"date":"2020-08-26 03:54:33.000000","timezone_type":3,"timezone":"UTC"}
1382	2020-08-26 03:54:48	updateTimestamp	{"date":"2020-08-26 03:54:48.000000","timezone_type":3,"timezone":"UTC"}
1383	2020-08-26 03:54:48	telefone2	"00000000000000000"
1384	2020-08-26 03:55:23	updateTimestamp	{"date":"2020-08-26 03:55:23.000000","timezone_type":3,"timezone":"UTC"}
1385	2020-08-26 03:55:45	telefone1	"11999999999"
1386	2020-08-26 03:55:46	updateTimestamp	{"date":"2020-08-26 03:55:46.000000","timezone_type":3,"timezone":"UTC"}
1387	2020-08-26 03:57:32	updateTimestamp	{"date":"2020-08-26 03:57:32.000000","timezone_type":3,"timezone":"UTC"}
1388	2020-08-26 03:57:35	updateTimestamp	{"date":"2020-08-26 03:57:35.000000","timezone_type":3,"timezone":"UTC"}
1389	2020-08-26 03:57:49	updateTimestamp	{"date":"2020-08-26 03:57:49.000000","timezone_type":3,"timezone":"UTC"}
1390	2020-08-26 03:57:59	updateTimestamp	{"date":"2020-08-26 03:57:59.000000","timezone_type":3,"timezone":"UTC"}
1391	2020-08-26 03:58:00	telefone2	"44"
1392	2020-08-26 03:58:07	updateTimestamp	{"date":"2020-08-26 03:58:07.000000","timezone_type":3,"timezone":"UTC"}
1393	2020-08-26 03:58:13	updateTimestamp	{"date":"2020-08-26 03:58:13.000000","timezone_type":3,"timezone":"UTC"}
1394	2020-08-26 03:58:13	telefone2	"1"
1395	2020-08-26 03:59:08	updateTimestamp	{"date":"2020-08-26 03:59:08.000000","timezone_type":3,"timezone":"UTC"}
1396	2020-08-26 04:00:51	updateTimestamp	{"date":"2020-08-26 04:00:51.000000","timezone_type":3,"timezone":"UTC"}
1397	2020-08-26 04:01:53	updateTimestamp	{"date":"2020-08-26 04:01:53.000000","timezone_type":3,"timezone":"UTC"}
1398	2020-08-26 04:18:56	nomeCompleto	"Sarda Medeiros Freitas"
1399	2020-08-26 04:18:56	updateTimestamp	{"date":"2020-08-26 04:18:56.000000","timezone_type":3,"timezone":"UTC"}
1400	2020-08-26 04:19:05	nomeCompleto	"Sarda Medeiros"
1401	2020-08-26 04:19:05	updateTimestamp	{"date":"2020-08-26 04:19:05.000000","timezone_type":3,"timezone":"UTC"}
1402	2020-08-26 04:27:51	nomeCompleto	"Sarda Medeiro"
1403	2020-08-26 04:27:52	updateTimestamp	{"date":"2020-08-26 04:27:52.000000","timezone_type":3,"timezone":"UTC"}
1404	2020-08-26 04:29:35	nomeCompleto	"Sarda Medeiros"
1405	2020-08-26 04:30:31	nomeCompleto	"Sarda Medeiro"
1406	2020-08-26 04:31:46	nomeCompleto	"Sarda Medeiros"
1407	2020-08-26 04:32:42	nomeCompleto	"Sarda Medeiro"
1408	2020-08-26 04:33:15	name	"Rafael"
1409	2020-08-26 04:33:15	updateTimestamp	{"date":"2020-08-26 04:33:15.000000","timezone_type":3,"timezone":"UTC"}
1410	2020-08-26 04:34:43	nomeCompleto	"Sarda MedeiroASD"
1411	2020-08-26 04:35:00	nomeCompleto	"Sarda Medeiro"
1412	2020-08-26 04:43:22	documento	"asd"
1413	2020-08-26 04:45:01	emailPrivado	"sarda@asd.com"
1414	2020-08-26 05:21:12	documento	"050.913.00970"
1415	2020-08-26 05:21:15	documento	"050.913.009-70"
1416	2020-08-26 05:21:18	documento	"050.913.009-71"
1417	2020-08-26 05:21:25	documento	"050.913.009-70"
1418	2020-08-26 05:56:46	documento	"11"
1419	2020-08-26 05:56:56	documento	"050.913.009-70"
1420	2020-08-26 05:57:53	documento	""
1421	2020-08-26 05:58:56	documento	"050.913.009-70"
1422	2020-08-26 05:59:09	documento	""
1423	2020-08-26 06:00:36	documento	"050.913.009-70"
1424	2020-08-26 06:05:28	documento	"050.913.009-71"
1425	2020-08-26 06:08:19	documento	"050.913.009-70"
1426	2020-08-26 06:08:41	documento	"050.913.009-7"
1427	2020-08-26 06:09:02	documento	""
1428	2020-08-26 06:10:21	documento	"1"
1429	2020-08-26 06:10:30	documento	""
1430	2020-08-26 06:10:45	documento	"050.913.009-70"
1431	2020-08-26 06:14:06	documento	"050.913.009-7"
1432	2020-08-26 06:14:51	documento	"050.913.009-70"
1433	2020-08-26 06:25:00	documento	""
1434	2020-08-26 06:25:12	documento	"1"
1435	2020-08-26 06:25:28	documento	""
1436	2020-08-26 06:25:47	documento	"123.321.123-33"
1437	2020-08-26 06:25:57	documento	""
1438	2020-08-26 06:26:36	documento	"123.123.123-12"
1439	2020-08-26 06:26:43	documento	""
1440	2020-08-26 06:27:28	documento	"1"
1441	2020-08-26 06:27:44	documento	""
1442	2020-08-26 06:28:05	documento	"123"
1443	2020-08-26 06:29:05	documento	""
1444	2020-08-26 06:32:14	documento	"12"
1445	2020-08-26 06:32:18	documento	"112"
1446	2020-08-26 06:32:34	documento	""
1447	2020-08-26 06:35:37	documento	"1"
1448	2020-08-26 06:37:07	documento	""
1449	2020-08-26 06:37:23	documento	"1"
1450	2020-08-26 06:38:54	documento	"112.3"
1451	2020-08-26 06:39:19	documento	"050.913.009-70"
1452	2020-08-26 06:39:53	documento	"123"
1453	2020-08-26 06:40:17	documento	"050.913.009-70"
1454	2020-08-26 06:40:29	nomeCompleto	"Sarda Freitas"
1455	2020-08-26 06:43:21	name	"Rafael Chaves"
1456	2020-08-26 06:43:21	updateTimestamp	{"date":"2020-08-26 06:43:21.000000","timezone_type":3,"timezone":"UTC"}
1457	2020-08-26 06:44:20	name	"Rafael"
1458	2020-08-26 06:44:20	updateTimestamp	{"date":"2020-08-26 06:44:20.000000","timezone_type":3,"timezone":"UTC"}
1459	2020-08-26 06:48:30	documento	"1"
1460	2020-08-26 06:50:13	documento	"11"
1461	2020-08-26 06:51:31	documento	"050.913.009-70"
1462	2020-08-26 06:52:48	documento	"050.913.009-71"
1463	2020-08-26 06:52:56	documento	"050.913.009-70"
1464	2020-08-26 07:06:58	_type	1
1465	2020-08-26 07:06:58	name	"Rud\\u00e1 Freitas Medeiros"
1466	2020-08-26 07:06:58	publicLocation	false
1467	2020-08-26 07:06:58	location	{"latitude":0,"longitude":0}
1468	2020-08-26 07:06:58	shortDescription	null
1469	2020-08-26 07:06:58	longDescription	null
1470	2020-08-26 07:06:58	createTimestamp	{"date":"2020-08-26 07:06:58.337706","timezone_type":3,"timezone":"UTC"}
1471	2020-08-26 07:06:58	status	1
1472	2020-08-26 07:06:58	updateTimestamp	null
1474	2020-08-26 07:06:58	location	{"latitude":"0","longitude":"0"}
1475	2020-08-26 07:06:58	createTimestamp	{"date":"2020-08-26 07:06:58.000000","timezone_type":3,"timezone":"UTC"}
1476	2020-08-26 07:07:04	aldirblanc_inciso1_registration	"902053773"
1477	2020-08-26 07:07:59	nomeCompleto	"Rud\\u00e1 Freitas Medeiros"
1478	2020-08-26 07:09:30	name	"Rud\\u00e1"
1479	2020-08-26 07:09:30	publicLocation	true
1480	2020-08-26 07:09:30	updateTimestamp	{"date":"2020-08-26 07:09:30.000000","timezone_type":3,"timezone":"UTC"}
1481	2020-08-26 07:09:30	En_CEP	"05453-060"
1482	2020-08-26 07:09:30	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
1483	2020-08-26 07:09:30	En_Bairro	"Vila Madalena"
1484	2020-08-26 07:09:30	En_Municipio	"S\\u00e3o Paulo"
1485	2020-08-26 07:09:30	En_Estado	"SP"
1486	2020-08-26 07:09:37	updateTimestamp	{"date":"2020-08-26 07:09:37.000000","timezone_type":3,"timezone":"UTC"}
1487	2020-08-26 07:09:37	En_Num	"35"
1488	2020-08-26 07:09:37	En_Complemento	"apto 91A"
1489	2020-08-26 07:14:32	documento	"050.913.009-7"
1490	2020-08-26 07:14:36	documento	"050.913.009-70"
1491	2020-08-26 07:15:10	_type	1
1492	2020-08-26 07:15:10	name	"Sardinha"
1493	2020-08-26 07:15:10	publicLocation	false
1494	2020-08-26 07:15:10	location	{"latitude":0,"longitude":0}
1495	2020-08-26 07:15:10	shortDescription	null
1496	2020-08-26 07:15:10	longDescription	null
1497	2020-08-26 07:15:10	createTimestamp	{"date":"2020-08-26 07:15:10.461105","timezone_type":3,"timezone":"UTC"}
1498	2020-08-26 07:15:10	status	1
1499	2020-08-26 07:15:10	updateTimestamp	null
1500	2020-08-26 07:15:10	_subsiteId	null
1501	2020-08-26 07:15:10	location	{"latitude":"0","longitude":"0"}
1502	2020-08-26 07:15:10	createTimestamp	{"date":"2020-08-26 07:15:10.000000","timezone_type":3,"timezone":"UTC"}
1503	2020-08-26 07:15:24	aldirblanc_inciso1_registration	"1715162904"
1504	2020-08-26 07:16:41	publicLocation	true
1505	2020-08-26 07:16:41	updateTimestamp	{"date":"2020-08-26 07:16:41.000000","timezone_type":3,"timezone":"UTC"}
1506	2020-08-26 07:16:41	En_CEP	"05453-060"
1507	2020-08-26 07:16:41	En_Nome_Logradouro	"Pra\\u00e7a Japuba"
1508	2020-08-26 07:16:41	En_Num	"35"
1509	2020-08-26 07:16:41	En_Complemento	"apto 91a"
1510	2020-08-26 07:16:41	En_Bairro	"Vila Madalena"
1511	2020-08-26 07:16:41	En_Municipio	"S\\u00e3o Paulo"
1512	2020-08-26 07:16:41	En_Estado	"SP"
1513	2020-08-26 07:19:09	documento	"050.913.009-70"
1514	2020-08-26 07:19:37	nomeCompleto	"Rafael Freitas"
1515	2020-08-26 07:19:46	dataDeNascimento	"2020-08-12"
1516	2020-08-26 07:19:48	telefone1	"123123123"
1517	2020-08-26 07:19:49	telefone2	"123123123"
1518	2020-08-26 07:19:57	emailPrivado	"rafafafa@asdasda.cm"
1519	2020-08-26 07:20:13	raca	"Amarela"
1520	2020-08-26 07:23:01	_type	1
1521	2020-08-26 07:23:01	name	"Praga"
1522	2020-08-26 07:23:01	publicLocation	false
1523	2020-08-26 07:23:01	location	{"latitude":0,"longitude":0}
1524	2020-08-26 07:23:01	shortDescription	null
1525	2020-08-26 07:23:01	longDescription	null
1526	2020-08-26 07:23:01	createTimestamp	{"date":"2020-08-26 07:23:01.021825","timezone_type":3,"timezone":"UTC"}
1527	2020-08-26 07:23:01	status	1
1528	2020-08-26 07:23:01	updateTimestamp	null
1529	2020-08-26 07:23:01	_subsiteId	null
1530	2020-08-26 07:23:01	location	{"latitude":"0","longitude":"0"}
1531	2020-08-26 07:23:01	createTimestamp	{"date":"2020-08-26 07:23:01.000000","timezone_type":3,"timezone":"UTC"}
1532	2020-08-26 07:23:05	aldirblanc_inciso1_registration	"905535019"
1533	2020-08-26 07:27:24	documento	"050.913.009-7"
1534	2020-08-26 07:27:28	documento	"050.913.009-70"
1535	2020-08-26 07:36:38	documento	"050.913.00970"
1536	2020-08-26 07:36:42	documento	"050.913.009-70"
1537	2020-08-26 07:41:25	documento	"1"
1538	2020-08-26 07:42:23	documento	"2"
1539	2020-08-26 07:42:30	documento	"1"
1540	2020-08-26 07:42:58	_type	1
1541	2020-08-26 07:42:58	name	"adasdas"
1542	2020-08-26 07:42:58	publicLocation	false
1543	2020-08-26 07:42:58	location	{"latitude":0,"longitude":0}
1544	2020-08-26 07:42:58	shortDescription	null
1545	2020-08-26 07:42:58	longDescription	null
1546	2020-08-26 07:42:58	createTimestamp	{"date":"2020-08-26 07:42:57.976799","timezone_type":3,"timezone":"UTC"}
1547	2020-08-26 07:42:58	status	1
1548	2020-08-26 07:42:58	updateTimestamp	null
1549	2020-08-26 07:42:58	_subsiteId	null
1550	2020-08-26 07:42:58	location	{"latitude":"0","longitude":"0"}
1551	2020-08-26 07:42:58	createTimestamp	{"date":"2020-08-26 07:42:57.000000","timezone_type":3,"timezone":"UTC"}
1552	2020-08-26 07:43:01	aldirblanc_inciso1_registration	"1750691250"
1553	2020-08-26 07:43:32	documento	"1111"
1554	2020-08-26 07:43:53	documento	"111.1"
1555	2020-08-26 07:44:46	_type	1
1556	2020-08-26 07:44:46	name	"teste123"
1557	2020-08-26 07:44:46	publicLocation	false
1558	2020-08-26 07:44:46	location	{"latitude":0,"longitude":0}
1559	2020-08-26 07:44:46	shortDescription	null
1560	2020-08-26 07:44:46	longDescription	null
1561	2020-08-26 07:44:46	createTimestamp	{"date":"2020-08-26 07:44:46.089816","timezone_type":3,"timezone":"UTC"}
1562	2020-08-26 07:44:46	status	1
1563	2020-08-26 07:44:46	updateTimestamp	null
1564	2020-08-26 07:44:46	_subsiteId	null
1565	2020-08-26 07:44:46	location	{"latitude":"0","longitude":"0"}
1566	2020-08-26 07:44:46	createTimestamp	{"date":"2020-08-26 07:44:46.000000","timezone_type":3,"timezone":"UTC"}
1567	2020-08-26 07:44:55	aldirblanc_inciso1_registration	"413170950"
1568	2020-08-26 07:47:09	nomeCompleto	"123"
1569	2020-08-26 07:47:19	nomeCompleto	"1233"
1570	2020-08-26 07:47:45	_type	1
1571	2020-08-26 07:47:45	name	"asdasd asd asd asd "
1572	2020-08-26 07:47:45	publicLocation	false
1573	2020-08-26 07:47:45	location	{"latitude":0,"longitude":0}
1574	2020-08-26 07:47:45	shortDescription	null
1575	2020-08-26 07:47:45	longDescription	null
1576	2020-08-26 07:47:45	createTimestamp	{"date":"2020-08-26 07:47:45.713750","timezone_type":3,"timezone":"UTC"}
1577	2020-08-26 07:47:45	status	1
1578	2020-08-26 07:47:45	updateTimestamp	null
1579	2020-08-26 07:47:45	_subsiteId	null
1580	2020-08-26 07:47:45	location	{"latitude":"0","longitude":"0"}
1581	2020-08-26 07:47:45	createTimestamp	{"date":"2020-08-26 07:47:45.000000","timezone_type":3,"timezone":"UTC"}
1582	2020-08-26 07:47:49	aldirblanc_inciso1_registration	"1066273876"
1583	2020-08-26 07:48:14	documento	"050.913.009-70"
1584	2020-08-26 07:48:26	nomeCompleto	"rafael freitas"
1585	2020-08-26 07:48:33	name	"rafael chves"
1586	2020-08-26 07:48:33	updateTimestamp	{"date":"2020-08-26 07:48:33.000000","timezone_type":3,"timezone":"UTC"}
1587	2020-08-26 07:48:34	name	"rafael chaves"
1588	2020-08-26 07:48:34	updateTimestamp	{"date":"2020-08-26 07:48:34.000000","timezone_type":3,"timezone":"UTC"}
1589	2020-08-26 07:48:48	telefone1	"11232323123"
1590	2020-08-26 07:48:50	telefone2	"32312312323123"
1591	2020-08-26 07:48:56	emailPrivado	"raaasfas@asdasd.com"
1592	2020-08-26 07:49:04	publicLocation	true
1593	2020-08-26 07:49:04	updateTimestamp	{"date":"2020-08-26 07:49:04.000000","timezone_type":3,"timezone":"UTC"}
1594	2020-08-26 07:49:04	En_CEP	"01220-010"
1595	2020-08-26 07:49:04	En_Nome_Logradouro	"Rua Rego Freitas"
1596	2020-08-26 07:49:04	En_Num	"530"
1597	2020-08-26 07:49:04	En_Bairro	"Rep\\u00fablica"
1598	2020-08-26 07:49:04	En_Municipio	"S\\u00e3o Paulo"
1599	2020-08-26 07:49:04	En_Estado	"SP"
1600	2020-08-26 07:49:07	updateTimestamp	{"date":"2020-08-26 07:49:07.000000","timezone_type":3,"timezone":"UTC"}
1601	2020-08-26 07:49:07	En_Complemento	"d4"
1602	2020-08-26 07:49:08	genero	"Homem"
1603	2020-08-26 07:49:12	raca	"Parda"
1604	2020-08-26 07:50:19	dataDeNascimento	"2020-08-13"
1605	2020-08-26 07:58:44	documento	"050.913.009-71"
1606	2020-08-26 07:58:54	documento	"050.913.009-70"
1607	2020-08-26 20:13:48	nomeCompleto	"Rafael"
1608	2020-08-26 22:44:47	documento	"123123"
1609	2020-08-26 22:44:48	documento	"123.123"
1610	2020-08-26 22:44:59	documento	"050.913.009-70"
1611	2020-08-27 13:25:50	_type	1
1612	2020-08-27 13:25:50	name	"teste"
1613	2020-08-27 13:25:50	publicLocation	false
1614	2020-08-27 13:25:50	location	{"latitude":0,"longitude":0}
1615	2020-08-27 13:25:50	shortDescription	null
1616	2020-08-27 13:25:50	longDescription	null
1617	2020-08-27 13:25:50	createTimestamp	{"date":"2020-08-27 13:25:49.808191","timezone_type":3,"timezone":"UTC"}
1618	2020-08-27 13:25:50	status	1
1619	2020-08-27 13:25:50	updateTimestamp	null
1620	2020-08-27 13:25:50	_subsiteId	null
1621	2020-08-27 13:25:50	location	{"latitude":"0","longitude":"0"}
1622	2020-08-27 13:25:50	createTimestamp	{"date":"2020-08-27 13:25:49.000000","timezone_type":3,"timezone":"UTC"}
1623	2020-08-27 13:25:54	aldirblanc_inciso1_registration	"1076435879"
\.


--
-- Data for Name: entity_revision_revision_data; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.entity_revision_revision_data (revision_id, revision_data_id) FROM stdin;
1	1
1	2
1	3
1	4
1	5
1	6
1	7
1	8
1	9
1	10
2	1
2	2
2	11
2	12
2	13
2	14
2	7
2	8
2	15
2	10
2	16
2	17
2	18
3	19
3	20
3	21
3	22
3	23
3	24
3	25
3	26
3	27
3	28
4	19
4	20
4	21
4	29
4	23
4	24
4	30
4	26
4	27
4	28
5	19
5	20
5	21
5	29
5	23
5	24
5	30
5	26
5	27
5	28
5	31
6	19
6	20
6	21
6	29
6	23
6	24
6	30
6	26
6	27
6	28
6	32
7	19
7	20
7	21
7	29
7	23
7	24
7	30
7	26
7	27
7	28
7	33
8	19
8	20
8	21
8	29
8	23
8	24
8	30
8	26
8	27
8	28
8	33
8	34
9	19
9	20
9	21
9	29
9	23
9	24
9	30
9	26
9	27
9	28
9	33
9	35
10	19
10	20
10	21
10	29
10	23
10	24
10	30
10	26
10	27
10	28
10	33
10	36
11	19
11	20
11	21
11	29
11	23
11	24
11	30
11	26
11	27
11	28
11	33
11	36
11	37
12	19
12	20
12	21
12	29
12	23
12	24
12	30
12	26
12	27
12	28
12	33
12	38
12	36
12	37
13	19
13	20
13	21
13	29
13	23
13	24
13	30
13	26
13	27
13	28
13	33
13	39
13	36
13	37
14	19
14	20
14	21
14	29
14	23
14	24
14	30
14	26
14	27
14	28
14	33
14	39
14	36
14	37
14	40
15	19
15	20
15	21
15	29
15	23
15	24
15	30
15	26
15	27
15	28
15	33
15	39
15	36
15	37
15	40
15	41
16	19
16	20
16	21
16	29
16	23
16	24
16	30
16	26
16	27
16	28
16	33
16	39
16	42
16	37
16	40
16	41
17	19
17	43
17	21
17	29
17	23
17	24
17	30
17	26
17	44
17	28
17	33
17	39
17	42
17	37
17	40
17	41
18	19
18	43
18	21
18	29
18	23
18	24
18	30
18	26
18	44
18	28
18	33
18	39
18	42
18	37
18	45
18	41
19	19
19	43
19	21
19	29
19	23
19	24
19	30
19	26
19	44
19	28
19	33
19	39
19	42
19	46
19	45
19	41
20	19
20	43
20	21
20	29
20	23
20	24
20	30
20	26
20	44
20	28
20	33
20	39
20	42
20	46
20	45
20	47
21	19
21	43
21	21
21	29
21	23
21	24
21	30
21	26
21	44
21	28
21	33
21	39
21	42
21	46
21	45
21	48
22	19
22	43
22	21
22	29
22	23
22	24
22	30
22	26
22	44
22	28
22	33
22	39
22	42
22	46
22	45
22	49
23	19
23	43
23	21
23	29
23	23
23	24
23	30
23	26
23	44
23	28
23	33
23	39
23	42
23	46
23	50
23	49
24	19
24	43
24	21
24	29
24	23
24	24
24	30
24	26
24	44
24	28
24	33
24	51
24	42
24	46
24	50
24	49
25	19
25	43
25	21
25	29
25	23
25	24
25	30
25	26
25	44
25	28
25	33
25	51
25	42
25	52
25	50
25	49
26	19
26	53
26	21
26	29
26	54
26	55
26	30
26	26
26	56
26	28
26	33
26	51
26	42
26	52
26	50
26	49
26	57
27	19
27	58
27	21
27	29
27	54
27	55
27	30
27	26
27	59
27	28
27	33
27	51
27	42
27	52
27	50
27	49
27	57
28	19
28	58
28	21
28	29
28	54
28	55
28	30
28	26
28	59
28	28
28	33
28	51
28	42
28	60
28	52
28	50
28	49
28	57
29	1
29	2
29	11
29	12
29	13
29	14
29	7
29	8
29	15
29	10
29	61
29	16
29	17
29	18
30	1
30	2
30	11
30	12
30	13
30	14
30	7
30	8
30	15
30	10
30	61
30	16
30	62
30	17
30	18
31	1
31	63
31	11
31	12
31	13
31	14
31	7
31	8
31	64
31	10
31	61
31	16
31	62
31	17
31	18
32	1
32	63
32	11
32	12
32	13
32	14
32	7
32	8
32	64
32	10
32	61
32	16
32	62
32	65
32	17
32	18
33	1
33	63
33	11
33	12
33	13
33	14
33	7
33	8
33	64
33	10
33	61
33	66
33	62
33	65
33	17
33	18
34	1
34	63
34	11
34	12
34	13
34	14
34	7
34	8
34	64
34	10
34	61
34	66
34	62
34	65
34	67
34	17
34	18
35	1
35	63
35	11
35	12
35	13
35	14
35	7
35	8
35	64
35	10
35	61
35	66
35	62
35	65
35	68
35	17
35	18
36	1
36	63
36	11
36	12
36	13
36	14
36	7
36	8
36	64
36	10
36	61
36	66
36	62
36	65
36	69
36	17
36	18
37	1
37	63
37	11
37	12
37	13
37	14
37	7
37	8
37	64
37	10
37	61
37	66
37	62
37	70
37	65
37	69
37	17
37	18
38	1
38	63
38	11
38	12
38	13
38	14
38	7
38	8
38	64
38	10
38	61
38	66
38	62
38	70
38	71
38	65
38	69
38	17
38	18
39	1
39	63
39	11
39	12
39	13
39	14
39	7
39	8
39	64
39	10
39	61
39	66
39	62
39	70
39	71
39	65
39	72
39	69
39	17
39	18
40	1
40	73
40	11
40	12
40	74
40	14
40	7
40	8
40	75
40	10
40	61
40	66
40	62
40	70
40	71
40	65
40	72
40	76
40	17
40	18
41	1
41	73
41	11
41	12
41	74
41	14
41	7
41	8
41	75
41	10
41	61
41	66
41	62
41	70
41	71
41	77
41	72
41	76
41	17
41	18
42	1
42	73
42	11
42	12
42	74
42	14
42	7
42	8
42	75
42	10
42	61
42	66
42	62
42	70
42	71
42	77
42	72
42	76
42	78
42	17
42	18
43	1
43	73
43	11
43	12
43	74
43	14
43	7
43	8
43	75
43	10
43	61
43	66
43	79
43	70
43	71
43	77
43	72
43	76
43	78
43	17
43	18
44	1
44	80
44	11
44	12
44	74
44	14
44	7
44	8
44	81
44	10
44	61
44	66
44	79
44	70
44	71
44	77
44	72
44	76
44	78
44	17
44	18
45	1
45	80
45	11
45	12
45	74
45	14
45	7
45	8
45	81
45	10
45	61
45	66
45	82
45	70
45	71
45	77
45	72
45	76
45	78
45	17
45	18
46	1
46	83
46	11
46	12
46	74
46	14
46	7
46	8
46	84
46	10
46	61
46	66
46	82
46	70
46	71
46	77
46	72
46	76
46	78
46	17
46	18
47	1
47	83
47	11
47	12
47	74
47	14
47	7
47	8
47	84
47	10
47	61
47	66
47	82
47	70
47	71
47	85
47	72
47	76
47	78
47	17
47	18
48	1
48	83
48	11
48	12
48	74
48	14
48	7
48	8
48	84
48	10
48	61
48	66
48	86
48	70
48	71
48	85
48	72
48	76
48	78
48	17
48	18
49	1
49	87
49	11
49	12
49	74
49	14
49	7
49	8
49	88
49	10
49	61
49	66
49	86
49	70
49	71
49	85
49	72
49	76
49	78
49	17
49	18
50	1
50	87
50	11
50	12
50	74
50	14
50	7
50	8
50	88
50	10
50	61
50	66
50	89
50	70
50	71
50	85
50	72
50	76
50	78
50	17
50	18
51	1
51	90
51	11
51	12
51	74
51	14
51	7
51	8
51	91
51	10
51	61
51	66
51	89
51	70
51	71
51	85
51	72
51	76
51	78
51	17
51	18
52	1
52	90
52	11
52	12
52	74
52	14
52	7
52	8
52	91
52	10
52	61
52	92
52	89
52	70
52	71
52	85
52	72
52	76
52	78
52	17
52	18
53	1
53	90
53	11
53	12
53	74
53	14
53	7
53	8
53	91
53	10
53	61
53	93
53	89
53	70
53	71
53	85
53	72
53	76
53	78
53	17
53	18
54	1
54	90
54	11
54	12
54	74
54	14
54	7
54	8
54	91
54	10
54	61
54	93
54	94
54	70
54	71
54	85
54	72
54	76
54	78
54	17
54	18
55	1
55	95
55	11
55	12
55	74
55	14
55	7
55	8
55	96
55	10
55	61
55	93
55	94
55	70
55	71
55	85
55	72
55	76
55	78
55	17
55	18
56	1
56	95
56	11
56	12
56	74
56	14
56	7
56	8
56	96
56	10
56	61
56	93
56	94
56	70
56	71
56	97
56	72
56	76
56	78
56	17
56	18
57	1
57	95
57	11
57	12
57	74
57	14
57	7
57	8
57	96
57	10
57	61
57	93
57	94
57	70
57	71
57	98
57	72
57	76
57	78
57	17
57	18
58	1
58	95
58	11
58	12
58	74
58	14
58	7
58	8
58	96
58	10
58	61
58	93
58	94
58	70
58	71
58	99
58	72
58	76
58	78
58	17
58	18
59	100
59	101
59	102
59	103
59	104
59	105
59	106
59	107
59	108
59	109
60	100
60	101
60	102
60	110
60	104
60	105
60	111
60	107
60	108
60	109
61	100
61	101
61	102
61	110
61	104
61	105
61	111
61	107
61	108
61	109
61	112
62	100
62	101
62	102
62	110
62	104
62	105
62	111
62	107
62	108
62	109
62	112
62	113
63	100
63	101
63	102
63	110
63	114
63	105
63	111
63	107
63	115
63	109
63	112
63	113
64	100
64	101
64	102
64	110
64	114
64	105
64	111
64	107
64	115
64	109
64	112
64	113
64	116
65	100
65	101
65	102
65	110
65	114
65	105
65	111
65	107
65	115
65	109
65	112
65	117
65	113
65	116
66	100
66	101
66	102
66	110
66	114
66	105
66	111
66	107
66	115
66	109
66	112
66	117
66	113
66	116
66	118
67	100
67	101
67	102
67	110
67	114
67	105
67	111
67	107
67	115
67	109
67	112
67	117
67	119
67	116
67	118
68	1
68	95
68	11
68	12
68	74
68	14
68	7
68	8
68	96
68	10
68	61
68	70
68	71
68	72
68	76
68	78
68	93
68	99
68	120
68	17
68	18
69	1
69	95
69	11
69	12
69	74
69	14
69	7
69	8
69	96
69	10
69	61
69	70
69	71
69	76
69	78
69	93
69	99
69	120
69	121
69	17
69	18
70	1
70	95
70	11
70	12
70	74
70	14
70	7
70	8
70	96
70	10
70	61
70	70
70	71
70	76
70	78
70	93
70	99
70	121
70	122
70	17
70	18
71	19
71	58
71	21
71	29
71	54
71	55
71	30
71	26
71	59
71	28
71	33
71	42
71	49
71	51
71	52
71	60
71	123
71	57
72	19
72	58
72	21
72	29
72	124
72	55
72	30
72	26
72	125
72	28
72	33
72	42
72	49
72	51
72	52
72	60
72	123
72	57
73	19
73	58
73	21
73	29
73	124
73	55
73	30
73	26
73	125
73	28
73	33
73	49
73	51
73	52
73	60
73	123
73	126
73	57
74	19
74	58
74	21
74	29
74	124
74	55
74	30
74	26
74	125
74	28
74	33
74	49
74	52
74	60
74	123
74	126
74	127
74	57
75	1
75	95
75	11
75	12
75	74
75	14
75	7
75	8
75	96
75	10
75	61
75	70
75	71
75	76
75	78
75	93
75	99
75	121
75	122
75	128
75	17
75	18
76	1
76	95
76	11
76	12
76	74
76	14
76	7
76	8
76	96
76	10
76	61
76	70
76	71
76	76
76	78
76	93
76	99
76	121
76	122
76	128
76	129
76	130
76	17
76	18
77	1
77	95
77	11
77	12
77	74
77	14
77	7
77	8
77	96
77	10
77	61
77	70
77	71
77	76
77	78
77	93
77	99
77	121
77	122
77	128
77	129
77	130
77	131
77	17
77	18
78	1
78	95
78	11
78	12
78	74
78	14
78	7
78	8
78	96
78	10
78	61
78	70
78	71
78	76
78	78
78	93
78	99
78	121
78	122
78	128
78	129
78	130
78	131
78	132
78	133
78	17
78	18
79	19
79	58
79	21
79	29
79	124
79	55
79	30
79	26
79	125
79	28
79	33
79	49
79	60
79	123
79	126
79	127
79	134
79	57
80	19
80	58
80	21
80	29
80	124
80	55
80	30
80	26
80	125
80	28
80	33
80	49
80	60
80	123
80	126
80	134
80	135
80	57
81	19
81	58
81	21
81	29
81	124
81	55
81	30
81	26
81	125
81	28
81	33
81	49
81	60
81	123
81	126
81	134
81	136
81	57
82	1
82	95
82	11
82	12
82	74
82	14
82	7
82	8
82	96
82	10
82	61
82	70
82	71
82	76
82	78
82	93
82	99
82	121
82	122
82	128
82	130
82	131
82	132
82	133
82	137
82	17
82	18
83	1
83	95
83	11
83	12
83	74
83	14
83	7
83	8
83	96
83	10
83	61
83	70
83	71
83	76
83	78
83	93
83	99
83	121
83	122
83	128
83	130
83	131
83	132
83	133
83	138
83	17
83	18
84	1
84	95
84	11
84	12
84	74
84	14
84	7
84	8
84	96
84	10
84	61
84	70
84	71
84	76
84	78
84	93
84	99
84	121
84	122
84	128
84	130
84	131
84	132
84	133
84	139
84	17
84	18
85	19
85	58
85	21
85	29
85	124
85	55
85	30
85	26
85	125
85	28
85	33
85	49
85	60
85	123
85	126
85	134
85	136
85	140
85	57
86	19
86	58
86	21
86	29
86	124
86	55
86	30
86	26
86	125
86	28
86	33
86	49
86	60
86	123
86	126
86	134
86	140
86	141
86	57
87	19
87	58
87	21
87	29
87	124
87	55
87	30
87	26
87	125
87	28
87	33
87	49
87	60
87	123
87	126
87	140
87	141
87	142
87	57
88	100
88	101
88	102
88	110
88	114
88	105
88	111
88	107
88	115
88	109
88	112
88	116
88	117
88	118
88	119
88	143
89	144
89	145
89	146
89	147
89	148
89	149
89	150
89	151
89	152
89	153
90	144
90	145
90	146
90	154
90	148
90	149
90	155
90	151
90	152
90	153
91	144
91	145
91	146
91	154
91	148
91	149
91	155
91	151
91	152
91	153
91	156
92	144
92	145
92	146
92	154
92	148
92	149
92	155
92	151
92	152
92	153
92	156
92	157
93	144
93	145
93	146
93	154
93	158
93	149
93	155
93	151
93	159
93	153
93	156
93	157
94	144
94	145
94	146
94	154
94	158
94	149
94	155
94	151
94	159
94	153
94	156
94	157
94	160
95	144
95	145
95	146
95	154
95	158
95	149
95	155
95	151
95	159
95	153
95	156
95	157
95	161
96	144
96	145
96	146
96	154
96	162
96	149
96	155
96	151
96	163
96	153
96	156
96	157
96	161
97	144
97	145
97	146
97	154
97	162
97	149
97	155
97	151
97	163
97	153
97	156
97	161
97	164
98	144
98	145
98	146
98	154
98	162
98	149
98	155
98	151
98	163
98	153
98	156
98	161
98	165
99	144
99	145
99	146
99	154
99	162
99	149
99	155
99	151
99	163
99	153
99	156
99	161
99	166
100	144
100	145
100	146
100	154
100	162
100	149
100	155
100	151
100	163
100	153
100	156
100	161
100	167
101	144
101	145
101	146
101	154
101	162
101	149
101	155
101	151
101	163
101	153
101	156
101	161
101	168
102	144
102	145
102	146
102	154
102	162
102	149
102	155
102	151
102	163
102	153
102	156
102	161
102	168
102	169
103	144
103	145
103	146
103	154
103	162
103	170
103	155
103	151
103	171
103	153
103	156
103	161
103	168
103	169
103	172
104	19
104	58
104	21
104	29
104	124
104	55
104	30
104	26
104	125
104	28
104	33
104	49
104	60
104	123
104	126
104	140
104	141
104	173
104	57
105	19
105	174
105	21
105	29
105	124
105	55
105	30
105	26
105	175
105	28
105	33
105	49
105	60
105	123
105	126
105	140
105	141
105	173
105	57
106	19
106	174
106	21
106	29
106	124
106	55
106	30
106	26
106	175
106	28
106	33
106	60
106	123
106	126
106	140
106	141
106	173
106	176
106	57
107	19
107	174
107	21
107	29
107	124
107	55
107	30
107	26
107	175
107	28
107	33
107	60
107	123
107	126
107	140
107	141
107	173
107	177
107	57
108	19
108	178
108	21
108	29
108	124
108	55
108	30
108	26
108	179
108	28
108	33
108	60
108	123
108	126
108	140
108	141
108	173
108	177
108	57
109	19
109	180
109	21
109	29
109	124
109	55
109	30
109	26
109	181
109	28
109	33
109	60
109	123
109	126
109	140
109	141
109	173
109	177
109	57
110	19
110	182
110	21
110	29
110	124
110	55
110	30
110	26
110	183
110	28
110	33
110	60
110	123
110	126
110	140
110	141
110	173
110	177
110	57
111	19
111	184
111	21
111	29
111	124
111	55
111	30
111	26
111	185
111	28
111	33
111	60
111	123
111	126
111	140
111	141
111	173
111	177
111	57
112	144
112	145
112	146
112	154
112	162
112	170
112	155
112	151
112	171
112	153
112	156
112	161
112	168
112	169
112	186
112	172
113	144
113	187
113	146
113	154
113	162
113	170
113	155
113	151
113	188
113	153
113	156
113	161
113	168
113	169
113	186
113	172
114	144
114	187
114	146
114	154
114	162
114	170
114	155
114	151
114	188
114	153
114	156
114	161
114	168
114	169
114	189
114	172
115	144
115	187
115	146
115	154
115	162
115	170
115	155
115	151
115	188
115	153
115	156
115	161
115	168
115	169
115	190
115	172
116	144
116	187
116	146
116	154
116	162
116	170
116	155
116	151
116	188
116	153
116	156
116	161
116	168
116	169
116	191
116	172
117	144
117	187
117	146
117	154
117	162
117	170
117	155
117	151
117	188
117	153
117	156
117	161
117	168
117	169
117	192
117	172
118	144
118	187
118	146
118	154
118	162
118	170
118	155
118	151
118	188
118	153
118	156
118	161
118	168
118	169
118	193
118	172
119	144
119	187
119	146
119	154
119	162
119	170
119	155
119	151
119	188
119	153
119	156
119	161
119	168
119	169
119	194
119	172
120	144
120	187
120	146
120	154
120	162
120	170
120	155
120	151
120	188
120	153
120	156
120	161
120	168
120	169
120	195
120	172
121	144
121	187
121	146
121	154
121	162
121	170
121	155
121	151
121	188
121	153
121	156
121	161
121	168
121	169
121	196
121	172
122	144
122	187
122	146
122	154
122	162
122	170
122	155
122	151
122	188
122	153
122	156
122	161
122	168
122	169
122	197
122	172
123	144
123	187
123	146
123	154
123	162
123	170
123	155
123	151
123	188
123	153
123	156
123	161
123	168
123	169
123	198
123	172
124	144
124	187
124	146
124	154
124	162
124	170
124	155
124	151
124	188
124	153
124	156
124	161
124	168
124	169
124	199
124	172
125	144
125	187
125	146
125	154
125	162
125	170
125	155
125	151
125	188
125	153
125	156
125	161
125	168
125	169
125	200
125	172
126	144
126	187
126	146
126	154
126	162
126	170
126	155
126	151
126	188
126	153
126	156
126	161
126	168
126	169
126	201
126	172
127	144
127	187
127	146
127	154
127	162
127	170
127	155
127	151
127	188
127	153
127	156
127	161
127	168
127	169
127	202
127	172
128	144
128	187
128	146
128	154
128	162
128	170
128	155
128	151
128	188
128	153
128	156
128	161
128	168
128	169
128	203
128	172
129	144
129	187
129	146
129	154
129	162
129	170
129	155
129	151
129	188
129	153
129	156
129	161
129	168
129	169
129	204
129	172
130	144
130	187
130	146
130	154
130	162
130	170
130	155
130	151
130	188
130	153
130	156
130	161
130	168
130	169
130	205
130	172
131	144
131	187
131	146
131	154
131	162
131	170
131	155
131	151
131	188
131	153
131	156
131	161
131	168
131	169
131	206
131	172
132	144
132	187
132	146
132	154
132	162
132	170
132	155
132	151
132	188
132	153
132	156
132	161
132	168
132	169
132	207
132	172
133	144
133	187
133	146
133	154
133	162
133	170
133	155
133	151
133	188
133	153
133	156
133	161
133	168
133	169
133	208
133	172
134	144
134	187
134	146
134	154
134	162
134	170
134	155
134	151
134	188
134	153
134	156
134	161
134	168
134	169
134	209
134	172
135	144
135	187
135	146
135	154
135	162
135	170
135	155
135	151
135	188
135	153
135	156
135	161
135	168
135	169
135	210
135	172
136	144
136	187
136	146
136	154
136	162
136	170
136	155
136	151
136	188
136	153
136	156
136	161
136	168
136	169
136	211
136	172
137	144
137	187
137	146
137	154
137	162
137	170
137	155
137	151
137	188
137	153
137	156
137	161
137	168
137	169
137	212
137	172
138	144
138	187
138	146
138	154
138	162
138	170
138	155
138	151
138	188
138	153
138	156
138	161
138	168
138	169
138	213
138	214
138	215
138	216
138	172
139	144
139	187
139	146
139	154
139	162
139	170
139	155
139	151
139	188
139	153
139	156
139	161
139	168
139	169
139	214
139	215
139	216
139	217
139	172
140	144
140	187
140	146
140	154
140	162
140	170
140	155
140	151
140	188
140	153
140	218
140	156
140	161
140	168
140	169
140	214
140	215
140	216
140	172
141	144
141	187
141	146
141	154
141	162
141	170
141	155
141	151
141	188
141	153
141	219
141	156
141	161
141	168
141	169
141	214
141	215
141	216
141	172
142	144
142	187
142	146
142	154
142	162
142	170
142	155
142	151
142	188
142	153
142	220
142	156
142	161
142	168
142	169
142	214
142	215
142	216
142	172
143	144
143	187
143	146
143	154
143	162
143	170
143	155
143	151
143	188
143	153
143	221
143	156
143	161
143	168
143	169
143	214
143	215
143	216
143	172
144	144
144	187
144	146
144	154
144	162
144	170
144	155
144	151
144	188
144	153
144	222
144	156
144	161
144	168
144	169
144	214
144	215
144	216
144	172
145	144
145	187
145	146
145	154
145	162
145	170
145	155
145	151
145	188
145	153
145	223
145	156
145	161
145	168
145	169
145	214
145	215
145	216
145	172
146	144
146	187
146	146
146	154
146	162
146	170
146	155
146	151
146	188
146	153
146	224
146	156
146	161
146	168
146	169
146	214
146	215
146	216
146	172
147	144
147	187
147	146
147	154
147	162
147	170
147	155
147	151
147	188
147	153
147	225
147	156
147	161
147	168
147	169
147	214
147	215
147	216
147	172
148	144
148	187
148	146
148	154
148	162
148	170
148	155
148	151
148	188
148	153
148	226
148	156
148	161
148	168
148	169
148	214
148	215
148	216
148	172
149	144
149	187
149	146
149	154
149	162
149	170
149	155
149	151
149	188
149	153
149	227
149	156
149	161
149	168
149	169
149	214
149	215
149	216
149	172
150	144
150	187
150	146
150	154
150	162
150	170
150	155
150	151
150	188
150	153
150	228
150	156
150	161
150	168
150	169
150	214
150	215
150	216
150	172
151	144
151	187
151	146
151	154
151	162
151	170
151	155
151	151
151	188
151	153
151	229
151	156
151	161
151	168
151	169
151	214
151	215
151	216
151	172
152	144
152	187
152	146
152	154
152	162
152	170
152	155
152	151
152	188
152	153
152	230
152	156
152	161
152	168
152	169
152	214
152	215
152	216
152	172
153	144
153	187
153	146
153	154
153	162
153	170
153	155
153	151
153	188
153	153
153	231
153	156
153	161
153	168
153	169
153	214
153	215
153	216
153	172
154	144
154	187
154	146
154	154
154	162
154	170
154	155
154	151
154	188
154	153
154	232
154	156
154	161
154	168
154	169
154	214
154	215
154	216
154	172
155	144
155	187
155	146
155	154
155	162
155	170
155	155
155	151
155	188
155	153
155	233
155	156
155	161
155	168
155	169
155	214
155	215
155	216
155	172
156	144
156	187
156	146
156	154
156	162
156	170
156	155
156	151
156	188
156	153
156	234
156	156
156	161
156	168
156	169
156	214
156	215
156	216
156	172
157	144
157	187
157	146
157	154
157	162
157	170
157	155
157	151
157	188
157	153
157	235
157	156
157	161
157	168
157	169
157	214
157	215
157	216
157	172
158	144
158	187
158	146
158	154
158	162
158	170
158	155
158	151
158	188
158	153
158	236
158	156
158	161
158	168
158	169
158	214
158	215
158	216
158	172
159	144
159	187
159	146
159	154
159	162
159	170
159	155
159	151
159	188
159	153
159	237
159	156
159	161
159	168
159	169
159	214
159	215
159	216
159	172
160	144
160	187
160	146
160	154
160	162
160	170
160	155
160	151
160	188
160	153
160	238
160	156
160	161
160	168
160	169
160	214
160	215
160	216
160	172
161	144
161	187
161	146
161	154
161	162
161	170
161	155
161	151
161	188
161	153
161	238
161	239
161	156
161	161
161	168
161	169
161	214
161	216
161	172
162	144
162	187
162	146
162	154
162	162
162	170
162	155
162	151
162	188
162	153
162	238
162	239
162	240
162	156
162	161
162	168
162	169
162	214
162	172
163	144
163	187
163	146
163	154
163	162
163	170
163	155
163	151
163	188
163	153
163	239
163	240
163	241
163	156
163	161
163	168
163	169
163	214
163	172
164	144
164	187
164	146
164	154
164	162
164	170
164	155
164	151
164	188
164	153
164	239
164	240
164	241
164	242
164	156
164	161
164	168
164	169
164	172
165	144
165	187
165	146
165	154
165	162
165	170
165	155
165	151
165	188
165	153
165	239
165	240
165	241
165	243
165	156
165	161
165	168
165	169
165	172
166	144
166	187
166	146
166	154
166	162
166	170
166	155
166	151
166	188
166	153
166	239
166	240
166	241
166	243
166	244
166	156
166	161
166	168
166	169
166	172
167	144
167	187
167	146
167	154
167	162
167	170
167	155
167	151
167	188
167	153
167	239
167	240
167	241
167	243
167	245
167	156
167	161
167	168
167	169
167	172
168	144
168	187
168	146
168	154
168	162
168	170
168	155
168	151
168	188
168	153
168	239
168	240
168	243
168	245
168	246
168	156
168	161
168	168
168	169
168	172
169	144
169	187
169	146
169	154
169	162
169	170
169	155
169	151
169	188
169	153
169	239
169	240
169	243
169	245
169	247
169	156
169	161
169	168
169	169
169	172
170	144
170	187
170	146
170	154
170	162
170	170
170	155
170	151
170	188
170	153
170	239
170	240
170	245
170	247
170	248
170	249
170	156
170	161
170	168
170	169
170	172
171	144
171	187
171	146
171	154
171	162
171	170
171	155
171	151
171	188
171	153
171	239
171	240
171	245
171	248
171	249
171	250
171	156
171	161
171	168
171	169
171	172
172	144
172	187
172	146
172	154
172	162
172	170
172	155
172	151
172	188
172	153
172	239
172	240
172	245
172	250
172	251
172	156
172	161
172	252
172	168
172	169
172	172
173	144
173	187
173	146
173	154
173	162
173	170
173	155
173	151
173	188
173	153
173	239
173	240
173	245
173	251
173	156
173	161
173	252
173	253
173	168
173	169
173	172
174	144
174	187
174	146
174	154
174	162
174	170
174	155
174	151
174	188
174	153
174	239
174	240
174	156
174	161
174	253
174	254
174	255
174	168
174	169
174	256
174	172
175	144
175	187
175	146
175	154
175	162
175	170
175	155
175	151
175	188
175	153
175	239
175	240
175	156
175	161
175	253
175	254
175	255
175	168
175	169
175	256
175	257
175	172
176	144
176	258
176	146
176	154
176	162
176	170
176	155
176	151
176	259
176	153
176	239
176	240
176	156
176	161
176	253
176	254
176	255
176	168
176	169
176	256
176	257
176	172
177	144
177	258
177	146
177	154
177	162
177	170
177	155
177	151
177	259
177	153
177	239
177	240
177	156
177	161
177	253
177	254
177	255
177	168
177	169
177	256
177	257
177	260
177	172
178	144
178	261
178	146
178	154
178	162
178	170
178	155
178	151
178	262
178	153
178	239
178	240
178	156
178	161
178	253
178	254
178	255
178	168
178	169
178	256
178	257
178	260
178	172
179	144
179	263
179	146
179	154
179	162
179	170
179	155
179	151
179	264
179	153
179	239
179	240
179	156
179	161
179	253
179	254
179	255
179	168
179	169
179	256
179	257
179	260
179	172
180	144
180	263
180	146
180	154
180	162
180	170
180	155
180	151
180	264
180	153
180	239
180	240
180	156
180	161
180	254
180	255
180	168
180	169
180	256
180	257
180	260
180	265
180	172
181	144
181	263
181	146
181	154
181	162
181	170
181	155
181	151
181	264
181	153
181	239
181	240
181	156
181	161
181	254
181	255
181	168
181	169
181	256
181	257
181	260
181	266
181	172
182	144
182	263
182	146
182	154
182	162
182	170
182	155
182	151
182	264
182	153
182	239
182	240
182	156
182	161
182	254
182	255
182	168
182	169
182	256
182	257
182	260
182	267
182	172
183	144
183	263
183	146
183	154
183	162
183	170
183	155
183	151
183	264
183	153
183	239
183	240
183	156
183	161
183	254
183	255
183	168
183	169
183	256
183	257
183	260
183	268
183	172
184	144
184	263
184	146
184	154
184	162
184	170
184	155
184	151
184	264
184	153
184	239
184	240
184	156
184	161
184	254
184	255
184	168
184	169
184	256
184	257
184	260
184	269
184	172
185	144
185	263
185	146
185	270
185	162
185	170
185	155
185	151
185	271
185	153
185	239
185	240
185	156
185	161
185	254
185	255
185	168
185	169
185	256
185	257
185	260
185	269
185	172
186	144
186	263
186	146
186	270
186	162
186	170
186	155
186	151
186	272
186	153
186	239
186	240
186	156
186	161
186	254
186	255
186	168
186	169
186	256
186	257
186	260
186	273
186	172
187	144
187	263
187	146
187	274
187	162
187	170
187	155
187	151
187	275
187	153
187	239
187	240
187	156
187	161
187	254
187	255
187	168
187	169
187	256
187	257
187	260
187	273
187	172
188	144
188	263
188	146
188	274
188	162
188	170
188	155
188	151
188	275
188	153
188	240
188	156
188	161
188	254
188	255
188	168
188	169
188	256
188	257
188	260
188	273
188	276
188	172
189	144
189	263
189	146
189	274
189	162
189	170
189	155
189	151
189	275
189	153
189	240
189	156
189	161
189	254
189	255
189	168
189	169
189	256
189	257
189	260
189	273
189	277
189	172
190	144
190	263
190	146
190	274
190	162
190	170
190	155
190	151
190	275
190	153
190	240
190	156
190	161
190	254
190	255
190	168
190	169
190	256
190	257
190	260
190	273
190	278
190	172
191	144
191	263
191	146
191	274
191	162
191	170
191	155
191	151
191	275
191	153
191	240
191	156
191	161
191	254
191	255
191	168
191	169
191	256
191	257
191	260
191	273
191	279
191	172
192	144
192	263
192	146
192	274
192	162
192	170
192	155
192	151
192	275
192	153
192	240
192	156
192	161
192	254
192	255
192	168
192	169
192	256
192	257
192	260
192	273
192	280
192	172
193	144
193	263
193	146
193	274
193	162
193	170
193	155
193	151
193	275
193	153
193	240
193	156
193	161
193	254
193	255
193	168
193	169
193	256
193	257
193	260
193	273
193	281
193	172
194	144
194	263
194	146
194	274
194	162
194	170
194	155
194	151
194	275
194	153
194	240
194	156
194	161
194	254
194	255
194	168
194	169
194	256
194	257
194	260
194	273
194	282
194	172
195	144
195	263
195	146
195	274
195	162
195	170
195	155
195	151
195	275
195	153
195	240
195	156
195	161
195	254
195	255
195	168
195	169
195	256
195	257
195	260
195	273
195	283
195	172
196	144
196	263
196	146
196	274
196	162
196	170
196	155
196	151
196	275
196	153
196	240
196	156
196	161
196	254
196	255
196	168
196	169
196	256
196	257
196	260
196	273
196	284
196	172
197	144
197	263
197	146
197	274
197	162
197	170
197	155
197	151
197	275
197	153
197	240
197	156
197	161
197	254
197	255
197	168
197	169
197	256
197	257
197	260
197	284
197	285
197	172
198	144
198	263
198	146
198	286
198	162
198	170
198	155
198	151
198	287
198	153
198	240
198	156
198	161
198	254
198	255
198	168
198	169
198	256
198	257
198	260
198	284
198	285
198	288
198	172
199	144
199	263
199	146
199	286
199	162
199	170
199	155
199	151
199	289
199	153
199	240
199	156
199	161
199	254
199	255
199	168
199	169
199	256
199	257
199	260
199	285
199	288
199	290
199	172
200	144
200	263
200	146
200	286
200	162
200	170
200	155
200	151
200	289
200	153
200	240
200	156
200	161
200	254
200	255
200	168
200	169
200	256
200	257
200	260
200	285
200	288
200	291
200	172
201	144
201	263
201	146
201	286
201	162
201	170
201	155
201	151
201	292
201	153
201	240
201	156
201	161
201	254
201	255
201	168
201	169
201	256
201	257
201	260
201	285
201	288
201	293
201	172
202	144
202	263
202	146
202	286
202	162
202	170
202	155
202	151
202	294
202	153
202	240
202	156
202	161
202	254
202	255
202	168
202	169
202	256
202	257
202	260
202	285
202	288
202	295
202	172
203	144
203	263
203	146
203	296
203	162
203	170
203	155
203	151
203	297
203	153
203	240
203	156
203	161
203	254
203	255
203	168
203	169
203	256
203	257
203	260
203	285
203	288
203	295
203	172
204	144
204	263
204	146
204	296
204	162
204	170
204	155
204	151
204	298
204	153
204	240
204	156
204	161
204	254
204	255
204	168
204	169
204	256
204	257
204	260
204	288
204	295
204	299
204	172
205	144
205	263
205	146
205	300
205	162
205	170
205	155
205	151
205	301
205	153
205	240
205	156
205	161
205	254
205	255
205	168
205	169
205	256
205	257
205	260
205	288
205	295
205	299
205	172
206	144
206	263
206	146
206	300
206	162
206	170
206	155
206	151
206	302
206	153
206	303
206	240
206	156
206	161
206	254
206	255
206	168
206	169
206	256
206	257
206	260
206	288
206	295
206	172
207	144
207	263
207	146
207	304
207	162
207	170
207	155
207	151
207	305
207	153
207	303
207	306
207	240
207	156
207	161
207	254
207	255
207	168
207	169
207	256
207	257
207	260
207	288
207	172
208	144
208	263
208	146
208	304
208	162
208	170
208	155
208	151
208	307
208	153
208	303
208	308
208	240
208	156
208	161
208	254
208	255
208	168
208	169
208	256
208	257
208	260
208	288
208	172
209	144
209	263
209	146
209	304
209	162
209	170
209	155
209	151
209	309
209	153
209	303
209	310
209	240
209	156
209	161
209	254
209	255
209	168
209	169
209	256
209	257
209	260
209	288
209	172
210	144
210	263
210	146
210	304
210	162
210	170
210	155
210	151
210	311
210	153
210	303
210	312
210	240
210	156
210	161
210	254
210	255
210	168
210	169
210	256
210	257
210	260
210	288
210	172
211	144
211	263
211	146
211	313
211	162
211	170
211	155
211	151
211	314
211	153
211	303
211	312
211	240
211	156
211	161
211	254
211	255
211	168
211	169
211	256
211	257
211	260
211	288
211	172
212	144
212	263
212	146
212	313
212	162
212	170
212	155
212	151
212	315
212	153
212	312
212	316
212	240
212	156
212	161
212	254
212	255
212	168
212	169
212	256
212	257
212	260
212	288
212	172
213	144
213	263
213	146
213	317
213	162
213	170
213	155
213	151
213	318
213	153
213	312
213	316
213	240
213	156
213	161
213	254
213	255
213	168
213	169
213	256
213	257
213	260
213	288
213	172
214	144
214	263
214	146
214	317
214	162
214	170
214	155
214	151
214	319
214	153
214	312
214	320
214	240
214	156
214	161
214	254
214	255
214	168
214	169
214	256
214	257
214	260
214	288
214	172
215	144
215	263
215	146
215	321
215	162
215	170
215	155
215	151
215	322
215	153
215	312
215	320
215	323
215	324
215	325
215	326
215	240
215	156
215	161
215	168
215	169
215	257
215	260
215	172
216	144
216	263
216	146
216	321
216	162
216	170
216	155
216	151
216	327
216	153
216	320
216	323
216	324
216	325
216	326
216	328
216	240
216	156
216	161
216	168
216	169
216	257
216	260
216	172
217	144
217	263
217	146
217	329
217	162
217	170
217	155
217	151
217	330
217	153
217	320
217	323
217	324
217	325
217	326
217	328
217	240
217	156
217	161
217	168
217	169
217	257
217	260
217	172
218	144
218	263
218	146
218	329
218	162
218	170
218	155
218	151
218	331
218	153
218	320
218	323
218	324
218	325
218	326
218	332
218	240
218	156
218	161
218	168
218	169
218	257
218	260
218	172
219	144
219	263
219	146
219	329
219	162
219	170
219	155
219	151
219	333
219	153
219	320
219	323
219	324
219	325
219	326
219	334
219	240
219	156
219	161
219	168
219	169
219	257
219	260
219	172
220	144
220	263
220	146
220	329
220	162
220	170
220	155
220	151
220	335
220	153
220	320
220	323
220	324
220	325
220	326
220	336
220	240
220	156
220	161
220	168
220	169
220	257
220	260
220	172
221	144
221	263
221	146
221	337
221	162
221	170
221	155
221	151
221	338
221	153
221	320
221	323
221	324
221	325
221	326
221	336
221	240
221	156
221	161
221	168
221	169
221	257
221	260
221	172
222	144
222	263
222	146
222	337
222	162
222	170
222	155
222	151
222	339
222	153
222	320
222	323
222	324
222	325
222	326
222	340
222	240
222	156
222	161
222	168
222	169
222	257
222	260
222	172
223	144
223	263
223	146
223	341
223	162
223	170
223	155
223	151
223	342
223	153
223	320
223	323
223	324
223	325
223	326
223	340
223	240
223	156
223	161
223	168
223	169
223	257
223	260
223	172
224	144
224	263
224	146
224	341
224	162
224	170
224	155
224	151
224	343
224	153
224	323
224	324
224	325
224	326
224	340
224	344
224	240
224	156
224	161
224	168
224	169
224	257
224	260
224	172
225	144
225	263
225	146
225	341
225	162
225	170
225	155
225	151
225	345
225	153
225	323
225	326
225	340
225	344
225	346
225	347
225	240
225	156
225	161
225	168
225	169
225	257
225	260
225	172
226	144
226	263
226	146
226	341
226	162
226	170
226	155
226	151
226	348
226	153
226	323
226	326
226	344
226	346
226	347
226	349
226	240
226	156
226	161
226	168
226	169
226	257
226	260
226	172
227	144
227	263
227	146
227	341
227	162
227	170
227	155
227	151
227	350
227	153
227	323
227	326
227	346
227	347
227	349
227	351
227	240
227	156
227	161
227	168
227	169
227	257
227	260
227	172
228	144
228	263
228	146
228	341
228	162
228	170
228	155
228	151
228	352
228	153
228	323
228	326
228	346
228	347
228	349
228	351
228	240
228	156
228	161
228	168
228	169
228	257
228	260
228	172
229	144
229	263
229	146
229	341
229	162
229	170
229	155
229	151
229	353
229	153
229	323
229	326
229	346
229	347
229	349
229	354
229	240
229	156
229	161
229	168
229	169
229	257
229	260
229	172
230	144
230	263
230	146
230	341
230	162
230	170
230	155
230	151
230	355
230	153
230	323
230	326
230	346
230	347
230	349
230	240
230	356
230	156
230	161
230	168
230	169
230	257
230	260
230	172
231	144
231	263
231	146
231	341
231	162
231	170
231	155
231	151
231	357
231	153
231	349
231	240
231	356
231	358
231	359
231	360
231	361
231	156
231	161
231	168
231	169
231	257
231	260
231	172
232	144
232	263
232	146
232	341
232	162
232	170
232	155
232	151
232	362
232	153
232	349
232	240
232	358
232	359
232	360
232	361
232	363
232	156
232	161
232	168
232	169
232	257
232	260
232	172
233	144
233	263
233	146
233	341
233	162
233	170
233	155
233	151
233	364
233	153
233	349
233	240
233	358
233	359
233	360
233	361
233	365
233	156
233	161
233	168
233	169
233	257
233	260
233	172
234	144
234	263
234	146
234	341
234	162
234	170
234	155
234	151
234	366
234	153
234	349
234	240
234	358
234	359
234	360
234	361
234	367
234	156
234	161
234	168
234	169
234	257
234	260
234	172
235	144
235	263
235	146
235	341
235	162
235	170
235	155
235	151
235	368
235	153
235	349
235	240
235	358
235	359
235	360
235	361
235	369
235	156
235	161
235	168
235	169
235	257
235	260
235	172
236	144
236	263
236	146
236	341
236	162
236	170
236	155
236	151
236	370
236	153
236	349
236	240
236	369
236	156
236	161
236	371
236	372
236	168
236	169
236	257
236	260
236	373
236	374
236	172
237	144
237	263
237	146
237	341
237	162
237	170
237	155
237	151
237	375
237	153
237	349
237	240
237	369
237	156
237	161
237	371
237	168
237	169
237	257
237	260
237	373
237	374
237	376
237	172
238	144
238	263
238	146
238	341
238	162
238	170
238	155
238	151
238	377
238	153
238	349
238	240
238	369
238	156
238	161
238	371
238	168
238	169
238	257
238	260
238	373
238	374
238	378
238	172
239	144
239	263
239	146
239	341
239	162
239	170
239	155
239	151
239	379
239	153
239	349
239	240
239	369
239	156
239	161
239	371
239	168
239	169
239	257
239	260
239	373
239	374
239	380
239	172
240	144
240	263
240	146
240	341
240	162
240	170
240	155
240	151
240	381
240	153
240	349
240	240
240	369
240	156
240	161
240	371
240	168
240	169
240	257
240	260
240	373
240	374
240	382
240	172
241	144
241	263
241	146
241	341
241	162
241	170
241	155
241	151
241	383
241	153
241	349
241	240
241	369
241	156
241	161
241	371
241	168
241	169
241	257
241	260
241	373
241	374
241	384
241	172
242	144
242	263
242	146
242	341
242	162
242	170
242	155
242	151
242	385
242	153
242	349
242	240
242	369
242	156
242	161
242	371
242	168
242	169
242	257
242	260
242	373
242	374
242	386
242	172
243	144
243	263
243	146
243	341
243	162
243	170
243	155
243	151
243	387
243	153
243	349
243	240
243	369
243	156
243	161
243	371
243	168
243	169
243	257
243	260
243	373
243	374
243	388
243	172
244	144
244	263
244	146
244	341
244	162
244	170
244	155
244	151
244	389
244	153
244	349
244	240
244	369
244	156
244	161
244	371
244	168
244	169
244	257
244	260
244	373
244	374
244	390
244	172
245	144
245	263
245	146
245	341
245	162
245	170
245	155
245	151
245	391
245	153
245	349
245	240
245	369
245	156
245	161
245	371
245	168
245	169
245	257
245	260
245	373
245	374
245	392
245	172
246	144
246	263
246	146
246	341
246	162
246	170
246	155
246	151
246	393
246	153
246	349
246	240
246	369
246	156
246	161
246	371
246	168
246	169
246	257
246	260
246	373
246	374
246	394
246	172
247	144
247	263
247	146
247	341
247	162
247	170
247	155
247	151
247	395
247	153
247	349
247	240
247	369
247	156
247	161
247	371
247	168
247	169
247	257
247	260
247	373
247	374
247	396
247	172
248	144
248	263
248	146
248	341
248	162
248	170
248	155
248	151
248	397
248	153
248	349
248	240
248	369
248	156
248	161
248	371
248	168
248	169
248	257
248	260
248	373
248	374
248	398
248	172
249	144
249	263
249	146
249	341
249	162
249	170
249	155
249	151
249	399
249	153
249	349
249	240
249	369
249	156
249	161
249	371
249	168
249	169
249	257
249	260
249	373
249	374
249	400
249	172
250	144
250	263
250	146
250	341
250	162
250	170
250	155
250	151
250	401
250	153
250	349
250	240
250	369
250	156
250	161
250	371
250	168
250	169
250	257
250	260
250	373
250	374
250	402
250	172
251	144
251	263
251	146
251	341
251	162
251	170
251	155
251	151
251	403
251	153
251	349
251	240
251	369
251	156
251	161
251	371
251	168
251	169
251	257
251	260
251	373
251	374
251	404
251	172
252	144
252	263
252	146
252	341
252	162
252	170
252	155
252	151
252	405
252	153
252	349
252	240
252	369
252	156
252	161
252	371
252	168
252	169
252	257
252	260
252	373
252	374
252	406
252	172
253	144
253	263
253	146
253	341
253	162
253	170
253	155
253	151
253	407
253	153
253	349
253	240
253	156
253	161
253	371
253	168
253	169
253	257
253	260
253	373
253	374
253	406
253	408
253	172
254	144
254	263
254	146
254	341
254	162
254	170
254	155
254	151
254	409
254	153
254	349
254	240
254	156
254	161
254	168
254	169
254	257
254	260
254	408
254	410
254	411
254	412
254	413
254	172
255	144
255	263
255	146
255	341
255	162
255	170
255	155
255	151
255	414
255	153
255	349
255	240
255	156
255	161
255	168
255	169
255	257
255	260
255	410
255	411
255	412
255	413
255	415
255	172
256	144
256	263
256	146
256	341
256	162
256	170
256	155
256	151
256	416
256	153
256	349
256	240
256	156
256	161
256	168
256	169
256	257
256	260
256	411
256	412
256	413
256	415
256	417
256	172
257	144
257	263
257	146
257	341
257	162
257	170
257	155
257	151
257	418
257	153
257	349
257	240
257	156
257	161
257	168
257	169
257	257
257	260
257	411
257	412
257	413
257	417
257	419
257	172
258	144
258	263
258	146
258	341
258	162
258	170
258	155
258	151
258	420
258	153
258	349
258	240
258	156
258	161
258	168
258	169
258	257
258	260
258	419
258	421
258	422
258	423
258	424
258	172
259	144
259	263
259	146
259	341
259	162
259	170
259	155
259	151
259	425
259	153
259	426
259	427
259	349
259	240
259	156
259	161
259	168
259	169
259	257
259	260
259	421
259	422
259	423
259	172
260	144
260	263
260	146
260	341
260	162
260	170
260	155
260	151
260	428
260	153
260	426
260	427
260	429
260	349
260	240
260	156
260	161
260	168
260	169
260	257
260	260
260	422
260	423
260	172
261	144
261	263
261	146
261	341
261	162
261	170
261	155
261	151
261	430
261	153
261	427
261	429
261	431
261	349
261	240
261	156
261	161
261	168
261	169
261	257
261	260
261	422
261	423
261	172
262	144
262	263
262	146
262	341
262	162
262	170
262	155
262	151
262	432
262	153
262	427
262	429
262	431
262	349
262	240
262	156
262	161
262	168
262	169
262	257
262	260
262	422
262	423
262	172
263	144
263	263
263	146
263	341
263	162
263	170
263	155
263	151
263	433
263	153
263	431
263	434
263	435
263	436
263	437
263	349
263	240
263	156
263	161
263	168
263	169
263	257
263	260
263	172
264	144
264	263
264	146
264	341
264	162
264	170
264	155
264	151
264	438
264	153
264	434
264	435
264	436
264	437
264	439
264	349
264	240
264	156
264	161
264	168
264	169
264	257
264	260
264	172
265	144
265	263
265	146
265	341
265	162
265	170
265	155
265	151
265	440
265	153
265	434
265	435
265	436
265	437
265	441
265	349
265	240
265	156
265	161
265	168
265	169
265	257
265	260
265	172
266	144
266	263
266	146
266	341
266	162
266	170
266	155
266	151
266	442
266	153
266	435
266	436
266	437
266	441
266	443
266	349
266	240
266	156
266	161
266	168
266	169
266	257
266	260
266	172
267	144
267	263
267	146
267	341
267	162
267	170
267	155
267	151
267	444
267	153
267	435
267	436
267	437
267	443
267	445
267	349
267	240
267	156
267	161
267	168
267	169
267	257
267	260
267	172
268	144
268	263
268	146
268	341
268	162
268	170
268	155
268	151
268	446
268	153
268	445
268	447
268	448
268	449
268	450
268	349
268	240
268	156
268	161
268	168
268	169
268	257
268	260
268	172
269	144
269	263
269	146
269	341
269	162
269	170
269	155
269	151
269	451
269	153
269	445
269	447
269	448
269	449
269	452
269	349
269	240
269	156
269	161
269	168
269	169
269	257
269	260
269	172
270	144
270	263
270	146
270	341
270	162
270	170
270	155
270	151
270	453
270	153
270	447
270	448
270	449
270	452
270	454
270	349
270	240
270	156
270	161
270	168
270	169
270	257
270	260
270	172
271	144
271	263
271	146
271	341
271	162
271	170
271	155
271	151
271	455
271	153
271	447
271	448
271	449
271	452
271	456
271	349
271	240
271	156
271	161
271	168
271	169
271	257
271	260
271	172
272	144
272	263
272	146
272	341
272	162
272	170
272	155
272	151
272	457
272	153
272	447
272	448
272	449
272	452
272	349
272	458
272	240
272	156
272	161
272	168
272	169
272	257
272	260
272	172
273	144
273	263
273	146
273	341
273	162
273	170
273	155
273	151
273	459
273	153
273	447
273	448
273	449
273	452
273	349
273	460
273	240
273	156
273	161
273	168
273	169
273	257
273	260
273	172
274	144
274	263
274	146
274	341
274	162
274	170
274	155
274	151
274	461
274	153
274	447
274	448
274	449
274	452
274	349
274	240
274	462
274	156
274	161
274	168
274	169
274	257
274	260
274	172
275	144
275	263
275	146
275	341
275	162
275	170
275	155
275	151
275	463
275	153
275	447
275	448
275	449
275	452
275	349
275	240
275	464
275	156
275	161
275	168
275	169
275	257
275	260
275	172
276	144
276	263
276	146
276	341
276	162
276	170
276	155
276	151
276	465
276	153
276	447
276	448
276	449
276	452
276	349
276	240
276	464
276	156
276	161
276	168
276	169
276	257
276	260
276	172
277	144
277	263
277	146
277	341
277	162
277	170
277	155
277	151
277	466
277	153
277	447
277	448
277	449
277	452
277	349
277	240
277	467
277	156
277	161
277	168
277	169
277	257
277	260
277	172
278	144
278	263
278	146
278	341
278	162
278	170
278	155
278	151
278	468
278	153
278	447
278	448
278	449
278	452
278	349
278	240
278	469
278	156
278	161
278	168
278	169
278	257
278	260
278	172
279	144
279	263
279	146
279	341
279	162
279	170
279	155
279	151
279	470
279	153
279	447
279	448
279	449
279	349
279	240
279	469
279	471
279	156
279	161
279	168
279	169
279	257
279	260
279	172
280	144
280	263
280	146
280	341
280	162
280	170
280	155
280	151
280	472
280	153
280	447
280	448
280	349
280	240
280	469
280	471
280	473
280	156
280	161
280	168
280	169
280	257
280	260
280	172
281	144
281	263
281	146
281	341
281	162
281	170
281	155
281	151
281	474
281	153
281	447
281	448
281	349
281	240
281	469
281	471
281	475
281	156
281	161
281	168
281	169
281	257
281	260
281	172
282	144
282	263
282	146
282	341
282	162
282	170
282	155
282	151
282	476
282	153
282	447
282	448
282	349
282	240
282	469
282	471
282	477
282	156
282	161
282	168
282	169
282	257
282	260
282	172
283	144
283	263
283	146
283	341
283	162
283	170
283	155
283	151
283	478
283	153
283	447
283	448
283	349
283	240
283	471
283	477
283	479
283	156
283	161
283	168
283	169
283	257
283	260
283	172
284	144
284	263
284	146
284	341
284	162
284	170
284	155
284	151
284	480
284	153
284	447
284	448
284	349
284	240
284	471
284	477
284	156
284	161
284	481
284	168
284	169
284	257
284	260
284	172
285	144
285	263
285	146
285	341
285	162
285	170
285	155
285	151
285	482
285	153
285	447
285	448
285	349
285	240
285	477
285	156
285	161
285	481
285	483
285	168
285	169
285	257
285	260
285	172
286	144
286	263
286	146
286	341
286	162
286	170
286	155
286	151
286	484
286	153
286	447
286	448
286	349
286	240
286	156
286	161
286	481
286	483
286	485
286	168
286	169
286	257
286	260
286	172
287	144
287	263
287	146
287	341
287	162
287	170
287	155
287	151
287	486
287	153
287	447
287	448
287	349
287	240
287	156
287	161
287	481
287	483
287	487
287	168
287	169
287	257
287	260
287	172
288	144
288	263
288	146
288	341
288	162
288	170
288	155
288	151
288	488
288	153
288	448
288	349
288	240
288	156
288	161
288	168
288	169
288	489
288	257
288	260
288	490
288	491
288	492
288	172
289	144
289	263
289	146
289	341
289	162
289	170
289	155
289	151
289	493
289	153
289	349
289	240
289	156
289	161
289	168
289	169
289	257
289	260
289	490
289	494
289	495
289	496
289	497
289	172
290	144
290	263
290	146
290	341
290	162
290	170
290	155
290	151
290	498
290	153
290	349
290	240
290	156
290	161
290	168
290	169
290	257
290	260
290	494
290	495
290	496
290	497
290	499
290	172
291	144
291	263
291	146
291	341
291	162
291	170
291	155
291	151
291	500
291	153
291	349
291	240
291	156
291	161
291	168
291	169
291	257
291	260
291	496
291	499
291	501
291	502
291	503
291	172
292	144
292	263
292	146
292	341
292	162
292	170
292	155
292	151
292	504
292	153
292	349
292	240
292	156
292	161
292	168
292	169
292	257
292	260
292	499
292	501
292	502
292	503
292	505
292	172
293	144
293	263
293	146
293	341
293	162
293	170
293	155
293	151
293	506
293	153
293	349
293	240
293	156
293	161
293	168
293	169
293	257
293	260
293	501
293	502
293	503
293	505
293	507
293	172
294	144
294	263
294	146
294	341
294	162
294	170
294	155
294	151
294	508
294	153
294	349
294	240
294	156
294	161
294	168
294	169
294	257
294	260
294	501
294	502
294	509
294	510
294	511
294	172
295	144
295	263
295	146
295	341
295	162
295	170
295	155
295	151
295	512
295	153
295	349
295	240
295	156
295	161
295	168
295	169
295	257
295	260
295	501
295	502
295	509
295	510
295	513
295	172
296	144
296	263
296	146
296	341
296	162
296	170
296	155
296	151
296	514
296	153
296	349
296	240
296	156
296	161
296	168
296	169
296	257
296	260
296	501
296	502
296	509
296	510
296	515
296	172
297	144
297	263
297	146
297	341
297	162
297	170
297	155
297	151
297	516
297	153
297	349
297	240
297	156
297	161
297	168
297	169
297	257
297	260
297	509
297	510
297	515
297	517
297	518
297	172
298	144
298	263
298	146
298	341
298	162
298	170
298	155
298	151
298	519
298	153
298	349
298	240
298	156
298	161
298	168
298	169
298	257
298	260
298	509
298	510
298	517
298	518
298	520
298	172
299	144
299	263
299	146
299	341
299	162
299	170
299	155
299	151
299	521
299	153
299	349
299	240
299	156
299	161
299	168
299	169
299	257
299	260
299	520
299	522
299	523
299	524
299	525
299	172
300	144
300	263
300	146
300	341
300	162
300	170
300	155
300	151
300	526
300	153
300	349
300	240
300	156
300	161
300	168
300	169
300	257
300	260
300	522
300	523
300	524
300	525
300	527
300	172
301	144
301	263
301	146
301	341
301	162
301	170
301	155
301	151
301	528
301	153
301	349
301	240
301	156
301	161
301	168
301	169
301	257
301	260
301	527
301	529
301	530
301	531
301	532
301	172
302	144
302	263
302	146
302	341
302	162
302	170
302	155
302	151
302	533
302	153
302	534
302	349
302	240
302	156
302	161
302	168
302	169
302	257
302	260
302	527
302	530
302	531
302	532
302	172
303	144
303	263
303	146
303	341
303	162
303	170
303	155
303	151
303	535
303	153
303	536
303	349
303	240
303	156
303	161
303	168
303	169
303	257
303	260
303	527
303	530
303	531
303	532
303	172
304	144
304	263
304	146
304	341
304	162
304	170
304	155
304	151
304	535
304	153
304	536
304	537
304	349
304	240
304	156
304	161
304	168
304	169
304	260
304	527
304	530
304	531
304	532
304	172
305	144
305	263
305	146
305	341
305	162
305	170
305	155
305	151
305	538
305	153
305	536
305	537
305	349
305	240
305	156
305	161
305	168
305	169
305	260
305	527
305	530
305	531
305	532
305	172
306	144
306	263
306	146
306	341
306	162
306	170
306	155
306	151
306	538
306	153
306	536
306	539
306	349
306	240
306	156
306	161
306	168
306	169
306	260
306	527
306	530
306	531
306	532
306	172
307	144
307	263
307	146
307	341
307	162
307	170
307	155
307	151
307	540
307	153
307	536
307	539
307	349
307	240
307	156
307	161
307	168
307	169
307	260
307	527
307	530
307	531
307	532
307	172
308	144
308	263
308	146
308	341
308	162
308	170
308	155
308	151
308	541
308	153
308	536
308	539
308	542
308	349
308	240
308	156
308	161
308	168
308	169
308	260
308	530
308	531
308	532
308	172
309	144
309	263
309	146
309	341
309	162
309	170
309	155
309	151
309	543
309	153
309	536
309	539
309	542
309	544
309	545
309	240
309	156
309	161
309	168
309	169
309	260
309	530
309	531
309	172
310	144
310	263
310	146
310	341
310	162
310	170
310	155
310	151
310	546
310	153
310	536
310	539
310	542
310	544
310	545
310	547
310	240
310	156
310	161
310	168
310	169
310	260
310	530
310	172
311	144
311	263
311	146
311	341
311	162
311	170
311	155
311	151
311	548
311	153
311	539
311	542
311	544
311	545
311	547
311	549
311	240
311	156
311	161
311	168
311	169
311	260
311	530
311	172
312	144
312	263
312	146
312	341
312	162
312	170
312	155
312	151
312	550
312	153
312	539
312	542
312	544
312	545
312	547
312	549
312	551
312	240
312	156
312	161
312	168
312	169
312	260
312	172
313	144
313	263
313	146
313	341
313	162
313	170
313	155
313	151
313	552
313	153
313	539
313	544
313	545
313	547
313	549
313	551
313	553
313	240
313	156
313	161
313	168
313	169
313	260
313	172
314	144
314	263
314	146
314	341
314	162
314	170
314	155
314	151
314	554
314	153
314	539
314	544
314	553
314	555
314	556
314	557
314	558
314	240
314	156
314	161
314	168
314	169
314	260
314	172
315	144
315	263
315	146
315	341
315	162
315	170
315	155
315	151
315	559
315	153
315	539
315	553
315	555
315	556
315	557
315	558
315	560
315	240
315	156
315	161
315	168
315	169
315	260
315	172
316	144
316	263
316	146
316	341
316	162
316	170
316	155
316	151
316	561
316	153
316	539
316	555
316	556
316	557
316	558
316	560
316	562
316	240
316	156
316	161
316	168
316	169
316	260
316	172
317	144
317	263
317	146
317	341
317	162
317	170
317	155
317	151
317	563
317	153
317	539
317	560
317	562
317	564
317	565
317	566
317	567
317	240
317	156
317	161
317	168
317	169
317	260
317	172
318	144
318	263
318	146
318	341
318	162
318	170
318	155
318	151
318	568
318	153
318	539
318	560
318	564
318	565
318	566
318	567
318	240
318	569
318	156
318	161
318	168
318	169
318	260
318	172
319	144
319	263
319	146
319	341
319	162
319	170
319	155
319	151
319	570
319	153
319	539
319	560
319	564
319	565
319	566
319	567
319	240
319	571
319	156
319	161
319	168
319	169
319	260
319	172
320	144
320	263
320	146
320	341
320	162
320	170
320	155
320	151
320	572
320	153
320	539
320	560
320	564
320	565
320	566
320	567
320	240
320	573
320	156
320	161
320	168
320	169
320	260
320	172
321	144
321	263
321	146
321	341
321	162
321	170
321	155
321	151
321	574
321	153
321	539
321	560
321	565
321	566
321	567
321	240
321	573
321	575
321	156
321	161
321	168
321	169
321	260
321	172
322	144
322	263
322	146
322	341
322	162
322	170
322	155
322	151
322	576
322	153
322	539
322	565
322	566
322	567
322	240
322	575
322	577
322	578
322	156
322	161
322	168
322	169
322	260
322	172
323	144
323	263
323	146
323	341
323	162
323	170
323	155
323	151
323	579
323	153
323	539
323	566
323	567
323	240
323	575
323	577
323	578
323	580
323	156
323	161
323	168
323	169
323	260
323	172
324	144
324	263
324	146
324	341
324	162
324	170
324	155
324	151
324	581
324	153
324	539
324	566
324	567
324	240
324	578
324	580
324	582
324	583
324	156
324	161
324	168
324	169
324	260
324	172
325	144
325	263
325	146
325	341
325	162
325	170
325	155
325	151
325	584
325	153
325	539
325	567
325	240
325	578
325	580
325	582
325	583
325	156
325	161
325	585
325	168
325	169
325	260
325	172
326	144
326	263
326	146
326	341
326	162
326	170
326	155
326	151
326	586
326	153
326	539
326	567
326	240
326	578
326	580
326	582
326	583
326	156
326	161
326	587
326	168
326	169
326	260
326	172
327	144
327	263
327	146
327	341
327	162
327	170
327	155
327	151
327	588
327	153
327	539
327	240
327	578
327	580
327	582
327	583
327	156
327	161
327	587
327	589
327	168
327	169
327	260
327	172
328	144
328	263
328	146
328	341
328	162
328	170
328	155
328	151
328	590
328	153
328	539
328	240
328	580
328	582
328	583
328	156
328	161
328	587
328	589
328	591
328	168
328	169
328	260
328	172
329	144
329	263
329	146
329	341
329	162
329	170
329	155
329	151
329	592
329	153
329	539
329	240
329	583
329	156
329	161
329	591
329	168
329	169
329	593
329	260
329	594
329	595
329	596
329	172
330	144
330	263
330	146
330	341
330	162
330	170
330	155
330	151
330	597
330	153
330	539
330	240
330	583
330	156
330	161
330	168
330	169
330	593
330	260
330	594
330	595
330	596
330	598
330	172
331	144
331	263
331	146
331	341
331	162
331	170
331	155
331	151
331	599
331	153
331	539
331	240
331	583
331	156
331	161
331	168
331	169
331	593
331	260
331	594
331	595
331	596
331	600
331	172
332	144
332	263
332	146
332	341
332	162
332	170
332	155
332	151
332	601
332	153
332	539
332	240
332	583
332	156
332	161
332	168
332	169
332	593
332	260
332	594
332	595
332	596
332	602
332	172
333	144
333	263
333	146
333	341
333	162
333	170
333	155
333	151
333	603
333	153
333	539
333	240
333	156
333	161
333	168
333	169
333	593
333	260
333	594
333	595
333	596
333	602
333	604
333	172
334	144
334	263
334	146
334	341
334	162
334	170
334	155
334	151
334	605
334	153
334	539
334	240
334	156
334	161
334	168
334	169
334	593
334	260
334	594
334	595
334	596
334	602
334	606
334	172
335	144
335	263
335	146
335	341
335	162
335	170
335	155
335	151
335	607
335	153
335	539
335	240
335	156
335	161
335	168
335	169
335	593
335	260
335	594
335	595
335	596
335	606
335	608
335	172
336	144
336	263
336	146
336	341
336	162
336	170
336	155
336	151
336	609
336	153
336	539
336	240
336	156
336	161
336	168
336	169
336	260
336	606
336	608
336	610
336	611
336	612
336	613
336	172
337	144
337	263
337	146
337	341
337	162
337	170
337	155
337	151
337	614
337	153
337	539
337	240
337	156
337	161
337	168
337	169
337	260
337	606
337	608
337	610
337	611
337	612
337	613
337	172
338	144
338	263
338	146
338	341
338	162
338	170
338	155
338	151
338	615
338	153
338	539
338	240
338	156
338	161
338	168
338	169
338	260
338	606
338	610
338	611
338	612
338	613
338	616
338	172
339	144
339	263
339	146
339	341
339	162
339	170
339	155
339	151
339	617
339	153
339	539
339	240
339	156
339	161
339	168
339	169
339	260
339	606
339	610
339	611
339	612
339	613
339	618
339	172
340	144
340	263
340	146
340	341
340	162
340	170
340	155
340	151
340	619
340	153
340	539
340	240
340	156
340	161
340	168
340	169
340	260
340	606
340	612
340	613
340	618
340	620
340	621
340	172
341	144
341	263
341	146
341	341
341	162
341	170
341	155
341	151
341	622
341	153
341	539
341	240
341	156
341	161
341	168
341	169
341	260
341	606
341	612
341	613
341	620
341	621
341	623
341	172
342	144
342	263
342	146
342	341
342	162
342	170
342	155
342	151
342	624
342	153
342	539
342	240
342	156
342	161
342	168
342	169
342	260
342	606
342	612
342	613
342	620
342	621
342	625
342	172
343	144
343	263
343	146
343	341
343	162
343	170
343	155
343	151
343	626
343	153
343	539
343	240
343	156
343	161
343	168
343	169
343	260
343	612
343	613
343	620
343	621
343	625
343	627
343	172
344	144
344	263
344	146
344	341
344	162
344	170
344	155
344	151
344	628
344	153
344	539
344	240
344	156
344	161
344	168
344	169
344	260
344	612
344	613
344	620
344	621
344	625
344	629
344	172
345	144
345	263
345	146
345	341
345	162
345	170
345	155
345	151
345	630
345	153
345	539
345	156
345	161
345	168
345	169
345	260
345	612
345	613
345	620
345	621
345	625
345	629
345	631
345	172
346	144
346	263
346	146
346	341
346	162
346	170
346	155
346	151
346	632
346	153
346	539
346	156
346	161
346	168
346	169
346	260
346	612
346	613
346	620
346	621
346	625
346	629
346	631
346	172
347	144
347	263
347	146
347	341
347	162
347	170
347	155
347	151
347	633
347	153
347	539
347	156
347	161
347	168
347	169
347	260
347	612
347	613
347	620
347	621
347	625
347	629
347	631
347	172
348	144
348	263
348	146
348	341
348	162
348	170
348	155
348	151
348	634
348	153
348	539
348	156
348	161
348	168
348	169
348	260
348	612
348	613
348	620
348	621
348	629
348	631
348	635
348	172
349	144
349	263
349	146
349	341
349	162
349	170
349	155
349	151
349	636
349	153
349	539
349	156
349	161
349	168
349	169
349	260
349	612
349	613
349	620
349	629
349	631
349	635
349	637
349	172
350	144
350	263
350	146
350	341
350	162
350	170
350	155
350	151
350	638
350	153
350	639
350	539
350	156
350	161
350	168
350	169
350	260
350	612
350	613
350	620
350	629
350	631
350	637
350	172
351	144
351	263
351	146
351	341
351	162
351	170
351	155
351	151
351	640
351	153
351	641
351	539
351	156
351	161
351	168
351	169
351	260
351	612
351	613
351	620
351	629
351	631
351	637
351	172
352	144
352	263
352	146
352	341
352	162
352	170
352	155
352	151
352	642
352	153
352	641
352	643
352	539
352	644
352	156
352	161
352	168
352	169
352	260
352	612
352	613
352	629
352	631
352	172
353	645
353	646
353	647
353	648
353	649
353	650
353	651
353	652
353	653
353	654
353	655
354	144
354	263
354	146
354	341
354	162
354	170
354	155
354	151
354	656
354	153
354	641
354	643
354	539
354	644
354	156
354	161
354	168
354	169
354	260
354	612
354	613
354	629
354	631
354	172
355	144
355	263
355	146
355	341
355	162
355	170
355	155
355	151
355	656
355	153
355	539
355	657
355	658
355	659
355	660
355	661
355	662
355	663
355	156
355	161
355	168
355	169
355	260
355	172
356	144
356	263
356	146
356	341
356	162
356	170
356	155
356	151
356	664
356	153
356	539
356	665
356	666
356	667
356	668
356	669
356	670
356	671
356	156
356	161
356	168
356	169
356	260
356	172
357	144
357	263
357	146
357	341
357	162
357	170
357	155
357	151
357	664
357	153
357	539
357	672
357	673
357	674
357	675
357	676
357	677
357	678
357	156
357	161
357	168
357	169
357	260
357	172
358	144
358	263
358	146
358	341
358	162
358	170
358	155
358	151
358	679
358	153
358	539
358	680
358	681
358	682
358	683
358	684
358	685
358	156
358	161
358	686
358	168
358	169
358	260
358	172
359	144
359	263
359	146
359	341
359	162
359	170
359	155
359	151
359	679
359	153
359	539
359	156
359	161
359	687
359	688
359	689
359	168
359	169
359	690
359	260
359	691
359	692
359	693
359	172
360	144
360	263
360	146
360	341
360	162
360	170
360	155
360	151
360	694
360	153
360	539
360	156
360	161
360	168
360	169
360	260
360	695
360	696
360	697
360	698
360	699
360	700
360	701
360	172
361	144
361	263
361	146
361	341
361	162
361	170
361	155
361	151
361	694
361	153
361	539
361	156
361	161
361	168
361	169
361	260
361	702
361	703
361	704
361	705
361	706
361	707
361	708
361	172
362	144
362	263
362	146
362	341
362	162
362	170
362	155
362	151
362	709
362	153
362	539
362	156
362	161
362	168
362	169
362	260
362	710
362	711
362	712
362	713
362	714
362	715
362	716
362	172
363	144
363	263
363	146
363	341
363	162
363	170
363	155
363	151
363	709
363	153
363	539
363	156
363	161
363	168
363	169
363	260
363	717
363	718
363	719
363	720
363	721
363	722
363	723
363	172
364	144
364	263
364	146
364	341
364	162
364	170
364	155
364	151
364	724
364	153
364	725
364	726
364	727
364	539
364	728
364	729
364	730
364	731
364	156
364	161
364	168
364	169
364	260
364	172
365	144
365	263
365	146
365	341
365	162
365	170
365	155
365	151
365	724
365	153
365	539
365	732
365	733
365	734
365	735
365	736
365	737
365	738
365	156
365	161
365	168
365	169
365	260
365	172
386	144
386	263
386	146
386	341
386	162
386	170
386	155
386	151
386	744
386	153
386	539
386	745
386	746
386	747
386	748
386	749
386	750
386	751
386	156
386	161
386	168
386	169
386	260
386	172
387	645
387	646
387	647
387	648
387	649
387	650
387	651
387	652
387	653
387	654
387	752
387	753
387	754
387	755
387	756
387	757
387	655
388	144
388	263
388	146
388	341
388	162
388	170
388	155
388	151
388	758
388	153
388	539
388	745
388	746
388	747
388	748
388	749
388	750
388	751
388	156
388	161
388	168
388	169
388	260
388	172
389	645
389	759
389	647
389	648
389	649
389	650
389	651
389	652
389	760
389	654
389	752
389	753
389	754
389	755
389	756
389	757
389	655
390	645
390	759
390	647
390	648
390	649
390	650
390	651
390	652
390	760
390	654
390	761
390	762
390	763
390	764
390	765
390	766
390	655
391	144
391	263
391	146
391	341
391	162
391	170
391	155
391	151
391	767
391	153
391	539
391	745
391	746
391	747
391	748
391	749
391	750
391	751
391	156
391	161
391	168
391	169
391	260
391	172
392	144
392	263
392	146
392	341
392	162
392	170
392	155
392	151
392	768
392	153
392	539
392	745
392	746
392	747
392	748
392	749
392	750
392	751
392	156
392	161
392	168
392	169
392	260
392	172
393	769
393	770
393	771
393	772
393	773
393	774
393	775
393	776
393	777
393	778
393	779
393	780
393	781
394	144
394	263
394	146
394	341
394	162
394	170
394	155
394	151
394	782
394	153
394	539
394	745
394	746
394	747
394	748
394	749
394	750
394	751
394	156
394	161
394	168
394	169
394	260
394	783
394	172
395	769
395	770
395	771
395	772
395	773
395	774
395	775
395	776
395	777
395	778
395	779
395	784
395	785
395	786
395	787
395	788
395	789
395	790
395	781
396	144
396	263
396	146
396	341
396	162
396	170
396	155
396	151
396	791
396	153
396	539
396	746
396	747
396	748
396	749
396	750
396	751
396	156
396	161
396	792
396	168
396	169
396	260
396	793
396	172
397	769
397	770
397	771
397	772
397	773
397	774
397	775
397	776
397	777
397	778
397	779
397	794
397	795
397	796
397	797
397	798
397	799
397	800
397	781
398	144
398	263
398	146
398	341
398	162
398	170
398	155
398	151
398	801
398	153
398	539
398	746
398	747
398	748
398	749
398	750
398	751
398	156
398	161
398	802
398	168
398	169
398	260
398	803
398	172
399	769
399	770
399	771
399	772
399	773
399	774
399	775
399	776
399	777
399	778
399	779
399	804
399	795
399	796
399	797
399	798
399	799
399	800
399	781
400	144
400	263
400	146
400	341
400	162
400	170
400	155
400	151
400	805
400	153
400	539
400	750
400	751
400	156
400	161
400	802
400	168
400	169
400	806
400	260
400	807
400	808
400	809
400	810
400	172
401	769
401	770
401	771
401	772
401	773
401	774
401	775
401	776
401	777
401	778
401	779
401	811
401	795
401	796
401	797
401	798
401	799
401	800
401	781
402	144
402	263
402	146
402	341
402	162
402	170
402	155
402	151
402	812
402	153
402	539
402	751
402	156
402	161
402	802
402	168
402	169
402	806
402	260
402	807
402	808
402	809
402	813
402	814
402	172
403	769
403	770
403	771
403	772
403	773
403	774
403	775
403	776
403	777
403	778
403	779
403	815
403	795
403	796
403	797
403	798
403	799
403	800
403	781
404	144
404	263
404	146
404	341
404	162
404	170
404	155
404	151
404	816
404	153
404	539
404	751
404	156
404	161
404	802
404	168
404	169
404	806
404	260
404	807
404	808
404	809
404	813
404	817
404	172
405	769
405	770
405	771
405	772
405	773
405	774
405	775
405	776
405	777
405	778
405	779
405	818
405	795
405	796
405	797
405	798
405	799
405	800
405	781
406	144
406	263
406	146
406	341
406	162
406	170
406	155
406	151
406	819
406	153
406	539
406	751
406	156
406	161
406	168
406	169
406	806
406	260
406	807
406	808
406	809
406	813
406	820
406	821
406	172
407	769
407	770
407	771
407	772
407	773
407	774
407	775
407	776
407	777
407	778
407	779
407	822
407	795
407	796
407	797
407	798
407	799
407	800
407	781
408	144
408	263
408	146
408	341
408	162
408	170
408	155
408	151
408	823
408	153
408	539
408	751
408	156
408	161
408	168
408	169
408	806
408	260
408	807
408	808
408	809
408	813
408	824
408	825
408	172
409	769
409	770
409	771
409	772
409	773
409	774
409	775
409	776
409	777
409	778
409	779
409	826
409	795
409	796
409	797
409	798
409	799
409	800
409	781
410	144
410	263
410	146
410	341
410	162
410	170
410	155
410	151
410	827
410	153
410	539
410	751
410	156
410	161
410	168
410	169
410	806
410	260
410	807
410	808
410	809
410	813
410	828
410	829
410	172
411	769
411	770
411	771
411	772
411	773
411	774
411	775
411	776
411	777
411	778
411	779
411	830
411	795
411	796
411	797
411	798
411	799
411	800
411	781
412	144
412	263
412	146
412	341
412	162
412	170
412	155
412	151
412	831
412	153
412	539
412	156
412	161
412	168
412	169
412	806
412	260
412	807
412	808
412	809
412	813
412	828
412	832
412	833
412	172
413	769
413	770
413	771
413	772
413	773
413	774
413	775
413	776
413	777
413	778
413	779
413	834
413	795
413	796
413	797
413	798
413	799
413	800
413	781
414	144
414	263
414	146
414	341
414	162
414	170
414	155
414	151
414	835
414	153
414	539
414	156
414	161
414	168
414	169
414	806
414	260
414	807
414	808
414	809
414	813
414	832
414	836
414	837
414	172
415	769
415	770
415	771
415	772
415	773
415	774
415	775
415	776
415	777
415	778
415	779
415	838
415	795
415	796
415	797
415	798
415	799
415	800
415	781
416	144
416	263
416	146
416	341
416	162
416	170
416	155
416	151
416	839
416	153
416	539
416	156
416	161
416	168
416	169
416	806
416	260
416	808
416	809
416	813
416	832
416	836
416	840
416	841
416	172
417	769
417	770
417	771
417	772
417	773
417	774
417	775
417	776
417	777
417	778
417	779
417	842
417	795
417	796
417	797
417	798
417	799
417	800
417	781
418	144
418	263
418	146
418	341
418	162
418	170
418	155
418	151
418	843
418	153
418	539
418	156
418	161
418	168
418	169
418	806
418	260
418	808
418	809
418	813
418	832
418	836
418	844
418	845
418	172
419	769
419	770
419	771
419	772
419	773
419	774
419	775
419	776
419	777
419	778
419	779
419	846
419	795
419	796
419	797
419	798
419	799
419	800
419	781
420	144
420	263
420	146
420	341
420	162
420	170
420	155
420	151
420	847
420	153
420	539
420	156
420	161
420	168
420	169
420	806
420	260
420	808
420	809
420	813
420	832
420	836
420	848
420	849
420	172
421	769
421	770
421	771
421	772
421	773
421	774
421	775
421	776
421	777
421	778
421	779
421	850
421	795
421	796
421	797
421	798
421	799
421	800
421	781
422	144
422	263
422	146
422	341
422	162
422	170
422	155
422	151
422	851
422	153
422	539
422	156
422	161
422	168
422	169
422	806
422	260
422	808
422	809
422	832
422	836
422	848
422	852
422	853
422	172
423	769
423	770
423	771
423	772
423	773
423	774
423	775
423	776
423	777
423	778
423	779
423	854
423	795
423	796
423	797
423	798
423	799
423	800
423	781
424	144
424	263
424	146
424	341
424	162
424	170
424	155
424	151
424	855
424	153
424	539
424	156
424	161
424	168
424	169
424	806
424	260
424	808
424	809
424	832
424	836
424	848
424	856
424	857
424	172
425	769
425	770
425	771
425	772
425	773
425	774
425	775
425	776
425	777
425	778
425	779
425	858
425	795
425	796
425	797
425	798
425	799
425	800
425	781
426	144
426	263
426	146
426	341
426	162
426	170
426	155
426	151
426	859
426	153
426	539
426	156
426	161
426	168
426	169
426	806
426	260
426	808
426	809
426	832
426	836
426	848
426	860
426	861
426	172
427	769
427	770
427	771
427	772
427	773
427	774
427	775
427	776
427	777
427	778
427	779
427	862
427	795
427	796
427	797
427	798
427	799
427	800
427	781
428	144
428	263
428	146
428	341
428	162
428	170
428	155
428	151
428	863
428	153
428	539
428	156
428	161
428	168
428	169
428	806
428	260
428	808
428	809
428	832
428	836
428	848
428	864
428	865
428	172
429	769
429	770
429	771
429	772
429	773
429	774
429	775
429	776
429	777
429	778
429	779
429	866
429	795
429	796
429	797
429	798
429	799
429	800
429	781
430	144
430	263
430	146
430	341
430	162
430	170
430	155
430	151
430	867
430	153
430	539
430	156
430	161
430	168
430	169
430	806
430	260
430	808
430	809
430	832
430	836
430	864
430	868
430	869
430	172
431	769
431	770
431	771
431	772
431	773
431	774
431	775
431	776
431	777
431	778
431	779
431	870
431	795
431	796
431	797
431	798
431	799
431	800
431	781
432	144
432	263
432	146
432	341
432	162
432	170
432	155
432	151
432	871
432	153
432	539
432	156
432	161
432	168
432	169
432	806
432	260
432	808
432	809
432	832
432	836
432	868
432	872
432	873
432	172
433	769
433	770
433	771
433	772
433	773
433	774
433	775
433	776
433	777
433	778
433	779
433	874
433	795
433	796
433	797
433	798
433	799
433	800
433	781
434	144
434	263
434	146
434	341
434	162
434	170
434	155
434	151
434	875
434	153
434	539
434	156
434	161
434	168
434	169
434	806
434	260
434	808
434	809
434	832
434	836
434	868
434	876
434	877
434	172
435	769
435	770
435	771
435	772
435	773
435	774
435	775
435	776
435	777
435	778
435	779
435	878
435	795
435	796
435	797
435	798
435	799
435	800
435	781
436	144
436	263
436	146
436	341
436	162
436	170
436	155
436	151
436	879
436	153
436	539
436	156
436	161
436	168
436	169
436	806
436	260
436	808
436	809
436	832
436	836
436	868
436	880
436	881
436	172
437	769
437	770
437	771
437	772
437	773
437	774
437	775
437	776
437	777
437	778
437	779
437	882
437	795
437	796
437	797
437	798
437	799
437	800
437	781
438	144
438	263
438	146
438	341
438	162
438	170
438	155
438	151
438	883
438	153
438	539
438	156
438	161
438	168
438	169
438	806
438	260
438	808
438	809
438	836
438	868
438	880
438	884
438	885
438	172
439	769
439	770
439	771
439	772
439	773
439	774
439	775
439	776
439	777
439	778
439	779
439	886
439	795
439	796
439	797
439	798
439	799
439	800
439	781
440	144
440	263
440	146
440	341
440	162
440	170
440	155
440	151
440	887
440	153
440	539
440	156
440	161
440	168
440	169
440	806
440	260
440	808
440	809
440	868
440	880
440	884
440	888
440	889
440	172
441	769
441	770
441	771
441	772
441	773
441	774
441	775
441	776
441	777
441	778
441	779
441	890
441	795
441	796
441	797
441	798
441	799
441	800
441	781
442	144
442	263
442	146
442	341
442	162
442	170
442	155
442	151
442	891
442	153
442	539
442	156
442	161
442	168
442	169
442	806
442	260
442	808
442	809
442	880
442	884
442	888
442	892
442	893
442	894
442	172
443	769
443	770
443	771
443	772
443	773
443	774
443	775
443	776
443	777
443	778
443	779
443	895
443	795
443	796
443	797
443	798
443	799
443	800
443	781
444	144
444	263
444	146
444	341
444	162
444	170
444	155
444	151
444	896
444	153
444	539
444	156
444	161
444	168
444	169
444	806
444	260
444	808
444	809
444	880
444	884
444	888
444	893
444	897
444	898
444	172
445	769
445	770
445	771
445	772
445	773
445	774
445	775
445	776
445	777
445	778
445	779
445	899
445	795
445	796
445	797
445	798
445	799
445	800
445	781
446	144
446	263
446	146
446	341
446	162
446	170
446	155
446	151
446	900
446	153
446	539
446	156
446	161
446	168
446	169
446	806
446	260
446	808
446	809
446	884
446	888
446	897
446	901
446	902
446	903
446	172
447	769
447	770
447	771
447	772
447	773
447	774
447	775
447	776
447	777
447	778
447	779
447	904
447	795
447	796
447	797
447	798
447	799
447	800
447	781
448	144
448	263
448	146
448	341
448	162
448	170
448	155
448	151
448	905
448	153
448	539
448	156
448	161
448	168
448	169
448	806
448	260
448	808
448	809
448	884
448	888
448	897
448	906
448	907
448	908
448	172
449	769
449	770
449	771
449	772
449	773
449	774
449	775
449	776
449	777
449	778
449	779
449	909
449	795
449	796
449	797
449	798
449	799
449	800
449	781
450	144
450	263
450	146
450	341
450	162
450	170
450	155
450	151
450	910
450	153
450	539
450	156
450	161
450	168
450	169
450	260
450	808
450	809
450	884
450	888
450	897
450	906
450	911
450	912
450	913
450	172
451	769
451	770
451	771
451	772
451	773
451	774
451	775
451	776
451	777
451	778
451	779
451	914
451	795
451	796
451	797
451	798
451	799
451	800
451	781
452	144
452	263
452	146
452	341
452	162
452	170
452	155
452	151
452	915
452	153
452	539
452	156
452	161
452	168
452	169
452	260
452	808
452	809
452	884
452	888
452	897
452	906
452	912
452	916
452	917
452	172
453	769
453	770
453	771
453	772
453	773
453	774
453	775
453	776
453	777
453	778
453	779
453	918
453	795
453	796
453	797
453	798
453	799
453	800
453	781
454	144
454	263
454	146
454	341
454	162
454	170
454	155
454	151
454	919
454	153
454	539
454	156
454	161
454	168
454	169
454	260
454	808
454	809
454	884
454	897
454	906
454	916
454	920
454	921
454	922
454	172
455	769
455	770
455	771
455	772
455	773
455	774
455	775
455	776
455	777
455	778
455	779
455	923
455	795
455	796
455	797
455	798
455	799
455	800
455	781
456	144
456	263
456	146
456	341
456	162
456	170
456	155
456	151
456	924
456	153
456	925
456	926
456	927
456	539
456	928
456	156
456	161
456	168
456	169
456	260
456	884
456	906
456	920
456	921
456	929
456	172
457	769
457	770
457	771
457	772
457	773
457	774
457	775
457	776
457	777
457	778
457	779
457	930
457	795
457	796
457	797
457	798
457	799
457	800
457	781
458	144
458	263
458	146
458	341
458	162
458	170
458	155
458	151
458	931
458	153
458	925
458	926
458	927
458	539
458	928
458	932
458	156
458	161
458	168
458	169
458	260
458	884
458	906
458	920
458	933
458	172
459	769
459	770
459	771
459	772
459	773
459	774
459	775
459	776
459	777
459	778
459	779
459	934
459	795
459	796
459	797
459	798
459	799
459	800
459	781
460	144
460	263
460	146
460	341
460	162
460	170
460	155
460	151
460	935
460	153
460	925
460	926
460	927
460	539
460	928
460	932
460	936
460	156
460	161
460	168
460	169
460	260
460	884
460	906
460	937
460	172
461	769
461	770
461	771
461	772
461	773
461	774
461	775
461	776
461	777
461	778
461	779
461	938
461	795
461	796
461	797
461	798
461	799
461	800
461	781
462	144
462	263
462	146
462	939
462	162
462	170
462	155
462	151
462	940
462	153
462	925
462	926
462	927
462	539
462	928
462	932
462	936
462	156
462	161
462	168
462	169
462	260
462	884
462	906
462	941
462	172
463	769
463	770
463	771
463	772
463	773
463	774
463	775
463	776
463	777
463	778
463	779
463	942
463	795
463	796
463	797
463	798
463	799
463	800
463	781
464	144
464	263
464	146
464	943
464	162
464	170
464	155
464	151
464	944
464	153
464	539
464	932
464	936
464	945
464	946
464	947
464	948
464	156
464	161
464	168
464	169
464	260
464	884
464	906
464	949
464	172
465	769
465	770
465	771
465	772
465	773
465	774
465	775
465	776
465	777
465	778
465	779
465	950
465	795
465	796
465	797
465	798
465	799
465	800
465	781
466	144
466	263
466	146
466	943
466	162
466	170
466	155
466	151
466	951
466	153
466	539
466	932
466	936
466	945
466	946
466	947
466	948
466	156
466	161
466	168
466	169
466	260
466	884
466	906
466	952
466	172
467	769
467	770
467	771
467	772
467	773
467	774
467	775
467	776
467	777
467	778
467	779
467	953
467	795
467	954
467	797
467	798
467	799
467	800
467	781
468	144
468	263
468	146
468	943
468	162
468	170
468	155
468	151
468	955
468	153
468	539
468	932
468	936
468	945
468	946
468	947
468	948
468	156
468	161
468	168
468	169
468	260
468	884
468	906
468	956
468	172
469	957
469	770
469	771
469	772
469	773
469	774
469	775
469	776
469	777
469	958
469	779
469	959
469	960
469	954
469	961
469	962
469	963
469	800
469	781
470	144
470	263
470	146
470	943
470	162
470	170
470	155
470	151
470	964
470	153
470	539
470	932
470	936
470	945
470	946
470	947
470	948
470	156
470	161
470	168
470	169
470	260
470	884
470	906
470	965
470	172
471	966
471	770
471	771
471	772
471	773
471	774
471	775
471	776
471	777
471	967
471	779
471	968
471	960
471	954
471	969
471	970
471	961
471	962
471	963
471	971
471	781
472	144
472	263
472	146
472	943
472	162
472	170
472	155
472	151
472	972
472	153
472	539
472	932
472	936
472	945
472	946
472	947
472	948
472	156
472	161
472	168
472	169
472	260
472	884
472	906
472	973
472	172
473	966
473	770
473	771
473	772
473	773
473	774
473	775
473	776
473	777
473	974
473	779
473	975
473	960
473	954
473	976
473	970
473	961
473	962
473	963
473	971
473	781
474	144
474	263
474	146
474	943
474	162
474	170
474	155
474	151
474	977
474	153
474	539
474	932
474	936
474	945
474	946
474	947
474	948
474	156
474	161
474	168
474	169
474	260
474	884
474	906
474	978
474	172
475	966
475	770
475	771
475	772
475	773
475	774
475	775
475	776
475	777
475	979
475	779
475	980
475	960
475	981
475	976
475	970
475	961
475	962
475	963
475	971
475	781
476	144
476	263
476	146
476	943
476	162
476	170
476	155
476	151
476	982
476	153
476	539
476	932
476	936
476	945
476	946
476	947
476	948
476	156
476	161
476	168
476	169
476	260
476	884
476	906
476	983
476	172
477	966
477	770
477	771
477	772
477	773
477	774
477	775
477	776
477	777
477	984
477	779
477	985
477	960
477	986
477	976
477	970
477	961
477	962
477	963
477	971
477	781
478	144
478	263
478	146
478	943
478	162
478	170
478	155
478	151
478	987
478	153
478	539
478	932
478	936
478	945
478	946
478	947
478	948
478	156
478	161
478	168
478	169
478	260
478	884
478	906
478	988
478	172
479	989
479	770
479	771
479	772
479	773
479	774
479	775
479	776
479	777
479	990
479	779
479	991
479	992
479	986
479	976
479	970
479	993
479	994
479	995
479	971
479	781
480	144
480	263
480	146
480	943
480	162
480	170
480	155
480	151
480	996
480	153
480	539
480	932
480	936
480	945
480	946
480	947
480	948
480	156
480	161
480	168
480	169
480	260
480	884
480	906
480	997
480	172
481	998
481	770
481	771
481	772
481	773
481	774
481	775
481	776
481	777
481	999
481	779
481	1000
481	992
481	986
481	976
481	1001
481	993
481	994
481	995
481	1002
481	781
482	144
482	263
482	146
482	943
482	162
482	170
482	155
482	151
482	1003
482	153
482	539
482	932
482	945
482	946
482	947
482	948
482	1004
482	156
482	161
482	168
482	169
482	260
482	884
482	906
482	1005
482	172
483	998
483	770
483	771
483	772
483	773
483	774
483	775
483	776
483	777
483	999
483	779
483	1006
483	1007
483	1008
483	1009
483	1010
483	1011
483	1012
483	1013
483	1014
483	781
484	144
484	263
484	146
484	1015
484	162
484	170
484	155
484	151
484	1016
484	153
484	539
484	945
484	946
484	947
484	948
484	1004
484	1017
484	156
484	161
484	168
484	169
484	260
484	884
484	906
484	1018
484	172
485	998
485	770
485	771
485	772
485	773
485	774
485	775
485	776
485	777
485	999
485	779
485	1019
485	1007
485	1008
485	1009
485	1010
485	1011
485	1012
485	1013
485	1014
485	781
486	144
486	263
486	146
486	1020
486	162
486	170
486	155
486	151
486	1021
486	153
486	539
486	1004
486	1022
486	1023
486	1024
486	1025
486	1026
486	156
486	161
486	168
486	169
486	260
486	884
486	906
486	1027
486	172
487	998
487	770
487	771
487	772
487	773
487	774
487	775
487	776
487	777
487	999
487	779
487	1028
487	1007
487	1008
487	1009
487	1010
487	1011
487	1012
487	1013
487	1014
487	781
488	144
488	263
488	146
488	1020
488	162
488	170
488	155
488	151
488	1029
488	153
488	539
488	1004
488	1022
488	1023
488	1024
488	1025
488	1026
488	1030
488	156
488	161
488	168
488	169
488	260
488	884
488	1031
488	172
489	998
489	770
489	771
489	772
489	773
489	774
489	775
489	776
489	777
489	999
489	779
489	1032
489	1007
489	1008
489	1009
489	1010
489	1011
489	1012
489	1013
489	1014
489	781
490	144
490	263
490	146
490	1033
490	162
490	170
490	155
490	151
490	1034
490	153
490	539
490	1004
490	1022
490	1023
490	1024
490	1025
490	1030
490	1035
490	156
490	161
490	168
490	169
490	260
490	884
490	1036
490	172
491	998
491	770
491	771
491	772
491	773
491	774
491	775
491	776
491	777
491	999
491	779
491	1037
491	1007
491	1008
491	1009
491	1010
491	1011
491	1012
491	1013
491	1014
491	781
492	144
492	263
492	146
492	1033
492	162
492	170
492	155
492	151
492	1038
492	153
492	539
492	1004
492	1022
492	1023
492	1024
492	1025
492	1030
492	1035
492	156
492	161
492	168
492	169
492	260
492	884
492	1039
492	172
493	998
493	770
493	771
493	772
493	773
493	774
493	775
493	776
493	777
493	999
493	779
493	1040
493	1007
493	1008
493	1009
493	1010
493	1011
493	1012
493	1013
493	1014
493	781
494	144
494	263
494	146
494	1033
494	162
494	170
494	155
494	151
494	1041
494	153
494	539
494	1022
494	1023
494	1024
494	1025
494	1030
494	1035
494	1042
494	156
494	161
494	168
494	169
494	260
494	884
494	1043
494	172
495	998
495	770
495	771
495	772
495	773
495	774
495	775
495	776
495	777
495	999
495	779
495	1044
495	1007
495	1008
495	1009
495	1010
495	1011
495	1012
495	1013
495	1014
495	781
496	144
496	263
496	146
496	1045
496	162
496	170
496	155
496	151
496	1046
496	153
496	539
496	1030
496	1042
496	1047
496	156
496	161
496	1048
496	1049
496	168
496	169
496	1050
496	260
496	1051
496	884
496	1052
496	172
497	998
497	770
497	771
497	772
497	773
497	774
497	775
497	776
497	777
497	999
497	779
497	1053
497	1007
497	1008
497	1009
497	1010
497	1011
497	1012
497	1013
497	1014
497	781
498	144
498	263
498	146
498	1045
498	162
498	170
498	155
498	151
498	1054
498	153
498	539
498	1030
498	1047
498	156
498	161
498	1048
498	1049
498	168
498	169
498	1050
498	260
498	1051
498	1055
498	884
498	1056
498	172
499	998
499	770
499	771
499	772
499	773
499	774
499	775
499	776
499	777
499	999
499	779
499	1057
499	1007
499	1008
499	1009
499	1010
499	1011
499	1012
499	1013
499	1014
499	781
500	144
500	263
500	146
500	1045
500	162
500	170
500	155
500	151
500	1058
500	153
500	539
500	1030
500	156
500	161
500	168
500	169
500	260
500	1051
500	1055
500	1059
500	1060
500	1061
500	1062
500	884
500	1063
500	172
501	998
501	770
501	771
501	772
501	773
501	774
501	775
501	776
501	777
501	999
501	779
501	1064
501	1007
501	1008
501	1009
501	1010
501	1011
501	1012
501	1013
501	1014
501	781
502	144
502	263
502	146
502	1045
502	162
502	170
502	155
502	151
502	1065
502	153
502	539
502	1030
502	156
502	161
502	168
502	169
502	260
502	1051
502	1059
502	1060
502	1061
502	1062
502	1066
502	884
502	1067
502	172
503	998
503	770
503	771
503	772
503	773
503	774
503	775
503	776
503	777
503	999
503	779
503	1068
503	1007
503	1008
503	1009
503	1010
503	1011
503	1012
503	1013
503	1014
503	781
504	144
504	263
504	146
504	1045
504	162
504	170
504	155
504	151
504	1069
504	153
504	539
504	1030
504	156
504	161
504	168
504	169
504	260
504	1051
504	1059
504	1060
504	1061
504	1062
504	1070
504	884
504	1071
504	172
505	998
505	770
505	771
505	772
505	773
505	774
505	775
505	776
505	777
505	999
505	779
505	1072
505	1007
505	1008
505	1009
505	1010
505	1011
505	1012
505	1013
505	1014
505	781
506	144
506	263
506	146
506	1045
506	162
506	170
506	155
506	151
506	1073
506	153
506	539
506	1030
506	156
506	161
506	168
506	169
506	260
506	1051
506	1059
506	1060
506	1061
506	1062
506	1074
506	884
506	1075
506	172
507	998
507	770
507	771
507	772
507	773
507	774
507	775
507	776
507	777
507	999
507	779
507	1076
507	1007
507	1008
507	1009
507	1010
507	1011
507	1012
507	1013
507	1014
507	781
508	144
508	263
508	146
508	1045
508	162
508	170
508	155
508	151
508	1077
508	153
508	539
508	1030
508	156
508	161
508	168
508	169
508	260
508	1051
508	1074
508	1078
508	1079
508	1080
508	1081
508	884
508	1082
508	172
509	998
509	770
509	771
509	772
509	773
509	774
509	775
509	776
509	777
509	999
509	779
509	1083
509	1007
509	1008
509	1009
509	1010
509	1011
509	1012
509	1013
509	1014
509	781
510	144
510	263
510	146
510	1045
510	162
510	170
510	155
510	151
510	1084
510	153
510	539
510	1030
510	156
510	161
510	168
510	169
510	260
510	1051
510	1078
510	1079
510	1080
510	1081
510	1085
510	884
510	1086
510	172
511	998
511	770
511	771
511	772
511	773
511	774
511	775
511	776
511	777
511	999
511	779
511	1087
511	1007
511	1008
511	1009
511	1010
511	1011
511	1012
511	1013
511	1014
511	781
512	144
512	263
512	146
512	1045
512	162
512	170
512	155
512	151
512	1088
512	153
512	539
512	1030
512	156
512	161
512	168
512	169
512	260
512	1051
512	1085
512	1089
512	1090
512	1091
512	1092
512	884
512	1093
512	172
513	998
513	770
513	771
513	772
513	773
513	774
513	775
513	776
513	777
513	999
513	779
513	1094
513	1007
513	1008
513	1009
513	1010
513	1011
513	1012
513	1013
513	1014
513	781
514	144
514	263
514	146
514	1045
514	162
514	170
514	155
514	151
514	1095
514	153
514	539
514	1030
514	156
514	161
514	168
514	169
514	260
514	1051
514	1089
514	1090
514	1091
514	1092
514	884
514	1096
514	1097
514	172
515	998
515	770
515	771
515	772
515	773
515	774
515	775
515	776
515	777
515	999
515	779
515	1098
515	1007
515	1008
515	1009
515	1010
515	1011
515	1012
515	1013
515	1014
515	781
516	144
516	263
516	146
516	1045
516	162
516	170
516	155
516	151
516	1099
516	153
516	539
516	1030
516	156
516	161
516	168
516	169
516	260
516	1051
516	1089
516	1090
516	884
516	1096
516	1100
516	1101
516	1102
516	172
517	998
517	770
517	771
517	772
517	773
517	774
517	775
517	776
517	777
517	999
517	779
517	1103
517	1007
517	1008
517	1009
517	1010
517	1011
517	1012
517	1013
517	1014
517	781
518	144
518	263
518	146
518	1045
518	162
518	170
518	155
518	151
518	1104
518	153
518	539
518	1030
518	156
518	161
518	168
518	169
518	260
518	1051
518	1089
518	1090
518	884
518	1100
518	1101
518	1105
518	1106
518	172
519	998
519	770
519	771
519	772
519	773
519	774
519	775
519	776
519	777
519	999
519	779
519	1107
519	1007
519	1008
519	1009
519	1010
519	1011
519	1012
519	1013
519	1014
519	781
520	144
520	263
520	146
520	1045
520	162
520	170
520	155
520	151
520	1108
520	153
520	539
520	1030
520	156
520	161
520	168
520	169
520	260
520	1051
520	1089
520	1090
520	884
520	1100
520	1101
520	1109
520	1110
520	172
521	998
521	770
521	771
521	772
521	773
521	774
521	775
521	776
521	777
521	999
521	779
521	1111
521	1007
521	1008
521	1009
521	1010
521	1011
521	1012
521	1013
521	1014
521	781
522	144
522	263
522	146
522	1045
522	162
522	170
522	155
522	151
522	1112
522	153
522	539
522	1030
522	156
522	161
522	168
522	169
522	260
522	1051
522	1089
522	1090
522	884
522	1100
522	1101
522	1109
522	1113
522	172
523	998
523	770
523	771
523	772
523	773
523	774
523	775
523	776
523	777
523	999
523	779
523	1114
523	1007
523	1008
523	1009
523	1010
523	1011
523	1012
523	1013
523	1014
523	781
524	144
524	263
524	146
524	1045
524	162
524	170
524	155
524	151
524	1115
524	153
524	539
524	1030
524	156
524	161
524	168
524	169
524	260
524	1051
524	1089
524	1090
524	1100
524	1101
524	1109
524	1116
524	1117
524	172
525	998
525	770
525	771
525	772
525	773
525	774
525	775
525	776
525	777
525	999
525	779
525	1118
525	1007
525	1008
525	1009
525	1010
525	1011
525	1012
525	1013
525	1014
525	781
526	1119
526	1120
526	1121
526	1122
526	1123
526	1124
526	1125
526	1126
526	1127
526	1128
526	1129
527	1119
527	1130
527	1121
527	1122
527	1123
527	1124
527	1125
527	1126
527	1131
527	1128
527	1129
528	1119
528	1130
528	1121
528	1122
528	1123
528	1124
528	1125
528	1126
528	1131
528	1128
528	1132
528	1129
529	1119
529	1130
529	1121
529	1122
529	1123
529	1124
529	1125
529	1126
529	1131
529	1128
529	1132
529	1133
529	1129
530	1119
530	1130
530	1121
530	1122
530	1123
530	1124
530	1125
530	1126
530	1131
530	1128
530	1132
530	1134
530	1129
531	1119
531	1135
531	1121
531	1122
531	1123
531	1124
531	1125
531	1126
531	1136
531	1128
531	1132
531	1134
531	1129
532	1119
532	1135
532	1121
532	1122
532	1123
532	1124
532	1125
532	1126
532	1136
532	1128
532	1137
532	1138
532	1129
533	19
533	184
533	21
533	29
533	124
533	55
533	30
533	26
533	1139
533	28
533	33
533	60
533	123
533	126
533	140
533	141
533	173
533	177
533	57
534	1119
534	1135
534	1121
534	1122
534	1123
534	1124
534	1125
534	1126
534	1140
534	1128
534	1137
534	1141
534	1129
535	19
535	184
535	21
535	29
535	124
535	55
535	30
535	26
535	1142
535	28
535	33
535	60
535	123
535	126
535	140
535	141
535	173
535	177
535	57
536	1119
536	1135
536	1121
536	1122
536	1123
536	1124
536	1125
536	1126
536	1143
536	1128
536	1141
536	1144
536	1145
536	1146
536	1147
536	1129
537	19
537	184
537	21
537	29
537	124
537	55
537	30
537	26
537	1148
537	28
537	33
537	60
537	123
537	126
537	140
537	141
537	173
537	177
537	57
538	1119
538	1135
538	1121
538	1122
538	1123
538	1124
538	1125
538	1126
538	1149
538	1128
538	1141
538	1144
538	1145
538	1146
538	1147
538	1150
538	1129
539	19
539	184
539	21
539	29
539	124
539	55
539	30
539	26
539	1151
539	28
539	33
539	60
539	123
539	126
539	140
539	141
539	173
539	177
539	57
540	1119
540	1135
540	1121
540	1122
540	1123
540	1124
540	1125
540	1126
540	1152
540	1128
540	1141
540	1144
540	1145
540	1146
540	1147
540	1150
540	1153
540	1129
541	19
541	184
541	21
541	29
541	124
541	55
541	30
541	26
541	1154
541	28
541	33
541	60
541	123
541	126
541	140
541	141
541	173
541	177
541	57
542	1119
542	1135
542	1121
542	1122
542	1123
542	1124
542	1125
542	1126
542	1155
542	1128
542	1141
542	1144
542	1145
542	1146
542	1147
542	1150
542	1153
542	1129
543	19
543	184
543	1156
543	29
543	124
543	55
543	30
543	26
543	1157
543	28
543	33
543	60
543	123
543	126
543	140
543	141
543	173
543	177
543	57
544	1119
544	1135
544	1158
544	1122
544	1123
544	1124
544	1125
544	1126
544	1159
544	1128
544	1141
544	1144
544	1145
544	1146
544	1147
544	1150
544	1153
544	1129
545	19
545	184
545	1156
545	29
545	124
545	55
545	30
545	26
545	1160
545	28
545	33
545	60
545	123
545	126
545	140
545	141
545	173
545	177
545	57
546	1119
546	1135
546	1158
546	1122
546	1123
546	1124
546	1125
546	1126
546	1161
546	1128
546	1141
546	1144
546	1145
546	1146
546	1147
546	1150
546	1153
546	1129
547	19
547	184
547	1156
547	29
547	124
547	55
547	30
547	26
547	1162
547	28
547	33
547	60
547	123
547	126
547	140
547	141
547	173
547	177
547	57
548	1119
548	1135
548	1158
548	1122
548	1123
548	1124
548	1125
548	1126
548	1163
548	1128
548	1141
548	1144
548	1145
548	1146
548	1147
548	1150
548	1153
548	1129
549	19
549	184
549	1156
549	29
549	124
549	55
549	30
549	26
549	1164
549	28
549	33
549	60
549	123
549	126
549	140
549	141
549	173
549	177
549	57
550	1119
550	1135
550	1165
550	1122
550	1123
550	1124
550	1125
550	1126
550	1166
550	1128
550	1141
550	1144
550	1145
550	1146
550	1147
550	1150
550	1153
550	1129
551	19
551	184
551	1156
551	29
551	124
551	55
551	30
551	26
551	1167
551	28
551	33
551	60
551	123
551	126
551	140
551	141
551	173
551	177
551	57
552	1119
552	1135
552	1168
552	1122
552	1123
552	1124
552	1125
552	1126
552	1169
552	1128
552	1141
552	1144
552	1145
552	1146
552	1147
552	1150
552	1153
552	1129
553	19
553	184
553	1156
553	29
553	124
553	55
553	30
553	26
553	1170
553	28
553	33
553	60
553	123
553	126
553	140
553	141
553	173
553	177
553	1171
553	57
554	1119
554	1135
554	1168
554	1122
554	1123
554	1124
554	1125
554	1126
554	1172
554	1128
554	1141
554	1144
554	1145
554	1146
554	1147
554	1150
554	1153
554	1129
555	19
555	184
555	1156
555	29
555	124
555	55
555	30
555	26
555	1173
555	28
555	1174
555	33
555	1175
555	60
555	123
555	126
555	140
555	141
555	173
555	177
555	1171
555	1176
555	1177
555	57
556	1119
556	1135
556	1168
556	1122
556	1123
556	1124
556	1125
556	1126
556	1178
556	1128
556	1141
556	1144
556	1145
556	1146
556	1147
556	1150
556	1153
556	1129
557	19
557	184
557	1156
557	29
557	124
557	55
557	30
557	26
557	1179
557	28
557	1174
557	33
557	1175
557	1180
557	60
557	123
557	126
557	140
557	141
557	173
557	177
557	1171
557	1176
557	1177
557	57
558	1119
558	1135
558	1168
558	1122
558	1123
558	1124
558	1125
558	1126
558	1181
558	1128
558	1141
558	1144
558	1145
558	1146
558	1147
558	1150
558	1153
558	1129
559	19
559	184
559	1156
559	29
559	124
559	55
559	30
559	26
559	1182
559	28
559	1174
559	33
559	1175
559	1180
559	60
559	123
559	126
559	140
559	141
559	173
559	177
559	1171
559	1176
559	1177
559	57
560	1119
560	1135
560	1168
560	1122
560	1123
560	1124
560	1125
560	1126
560	1183
560	1128
560	1141
560	1144
560	1145
560	1146
560	1147
560	1150
560	1153
560	1129
561	19
561	184
561	1156
561	29
561	124
561	55
561	30
561	26
561	1184
561	28
561	1174
561	33
561	1175
561	1180
561	60
561	123
561	126
561	140
561	141
561	173
561	177
561	1171
561	1176
561	1177
561	57
562	1119
562	1135
562	1168
562	1122
562	1123
562	1124
562	1125
562	1126
562	1185
562	1128
562	1141
562	1144
562	1145
562	1146
562	1147
562	1150
562	1153
562	1129
563	19
563	184
563	1156
563	29
563	124
563	55
563	30
563	26
563	1186
563	28
563	1174
563	33
563	1175
563	1180
563	60
563	123
563	126
563	140
563	141
563	173
563	177
563	1171
563	1176
563	1177
563	57
564	1119
564	1135
564	1168
564	1122
564	1123
564	1124
564	1125
564	1126
564	1187
564	1128
564	1141
564	1144
564	1145
564	1146
564	1147
564	1150
564	1153
564	1129
565	19
565	184
565	1156
565	29
565	124
565	55
565	30
565	26
565	1188
565	28
565	1174
565	33
565	1175
565	1180
565	60
565	123
565	126
565	140
565	141
565	173
565	177
565	1171
565	1176
565	1177
565	57
566	1119
566	1135
566	1168
566	1122
566	1123
566	1124
566	1125
566	1126
566	1189
566	1128
566	1141
566	1144
566	1145
566	1146
566	1147
566	1150
566	1153
566	1129
567	19
567	184
567	1156
567	29
567	124
567	55
567	30
567	26
567	1190
567	28
567	1174
567	33
567	1175
567	1180
567	60
567	123
567	126
567	140
567	141
567	173
567	177
567	1171
567	1176
567	1177
567	57
568	1119
568	1135
568	1168
568	1122
568	1123
568	1124
568	1125
568	1126
568	1191
568	1128
568	1141
568	1144
568	1145
568	1146
568	1147
568	1150
568	1153
568	1129
569	19
569	184
569	1156
569	29
569	124
569	55
569	30
569	26
569	1192
569	28
569	1174
569	33
569	1175
569	1180
569	60
569	123
569	126
569	140
569	141
569	173
569	177
569	1171
569	1176
569	1177
569	57
570	1119
570	1135
570	1168
570	1122
570	1123
570	1124
570	1125
570	1126
570	1193
570	1128
570	1141
570	1144
570	1145
570	1146
570	1147
570	1150
570	1153
570	1129
571	19
571	184
571	1156
571	29
571	124
571	55
571	30
571	26
571	1194
571	28
571	1174
571	33
571	1175
571	1180
571	60
571	123
571	126
571	140
571	141
571	173
571	177
571	1171
571	1176
571	1177
571	57
572	1119
572	1135
572	1168
572	1122
572	1123
572	1124
572	1125
572	1126
572	1195
572	1128
572	1141
572	1144
572	1145
572	1146
572	1147
572	1150
572	1153
572	1129
573	19
573	184
573	1156
573	29
573	124
573	55
573	30
573	26
573	1196
573	28
573	33
573	1197
573	1198
573	1199
573	1200
573	1201
573	1202
573	60
573	123
573	126
573	140
573	141
573	173
573	177
573	57
574	1119
574	1135
574	1168
574	1122
574	1123
574	1124
574	1125
574	1126
574	1203
574	1128
574	1204
574	1144
574	1145
574	1146
574	1147
574	1150
574	1153
574	1129
575	19
575	184
575	1156
575	29
575	124
575	55
575	30
575	26
575	1205
575	28
575	33
575	1197
575	1198
575	1199
575	1200
575	1201
575	1202
575	60
575	123
575	126
575	140
575	141
575	173
575	177
575	57
576	1119
576	1135
576	1168
576	1122
576	1123
576	1124
576	1125
576	1126
576	1206
576	1128
576	1207
576	1144
576	1145
576	1146
576	1147
576	1150
576	1153
576	1129
577	19
577	184
577	1156
577	29
577	124
577	55
577	30
577	26
577	1208
577	28
577	33
577	1197
577	1198
577	1199
577	1200
577	1201
577	1202
577	60
577	123
577	126
577	140
577	141
577	173
577	177
577	57
578	1119
578	1135
578	1168
578	1122
578	1123
578	1124
578	1125
578	1126
578	1209
578	1128
578	1210
578	1144
578	1145
578	1146
578	1147
578	1150
578	1153
578	1129
579	19
579	184
579	1156
579	29
579	124
579	55
579	30
579	26
579	1211
579	28
579	33
579	1197
579	1198
579	1199
579	1200
579	1201
579	1202
579	60
579	123
579	126
579	140
579	141
579	173
579	177
579	57
580	1119
580	1135
580	1168
580	1122
580	1123
580	1124
580	1125
580	1126
580	1212
580	1128
580	1213
580	1144
580	1145
580	1146
580	1147
580	1150
580	1153
580	1129
581	19
581	184
581	1156
581	29
581	124
581	55
581	30
581	26
581	1214
581	28
581	33
581	1197
581	1198
581	1199
581	1200
581	1201
581	1202
581	60
581	123
581	126
581	140
581	141
581	173
581	177
581	57
582	1119
582	1135
582	1168
582	1122
582	1123
582	1124
582	1125
582	1126
582	1215
582	1128
582	1213
582	1144
582	1145
582	1146
582	1147
582	1150
582	1153
582	1129
583	19
583	184
583	1156
583	29
583	124
583	55
583	30
583	26
583	1216
583	28
583	33
583	1197
583	1198
583	1199
583	1200
583	1201
583	1202
583	60
583	123
583	126
583	140
583	141
583	173
583	177
583	57
584	1119
584	1135
584	1168
584	1122
584	1123
584	1124
584	1125
584	1126
584	1217
584	1128
584	1218
584	1144
584	1145
584	1146
584	1147
584	1150
584	1153
584	1129
585	19
585	184
585	1156
585	29
585	124
585	55
585	30
585	26
585	1219
585	28
585	33
585	1197
585	1198
585	1199
585	1200
585	1201
585	1202
585	60
585	123
585	126
585	140
585	141
585	173
585	177
585	57
586	1119
586	1135
586	1168
586	1122
586	1123
586	1124
586	1125
586	1126
586	1220
586	1128
586	1221
586	1144
586	1145
586	1146
586	1147
586	1150
586	1153
586	1129
587	19
587	184
587	1156
587	29
587	124
587	55
587	30
587	26
587	1222
587	28
587	33
587	1197
587	1198
587	1199
587	1200
587	1201
587	1202
587	60
587	123
587	126
587	140
587	141
587	173
587	177
587	57
588	1119
588	1135
588	1168
588	1122
588	1123
588	1124
588	1125
588	1126
588	1223
588	1128
588	1224
588	1144
588	1145
588	1146
588	1147
588	1150
588	1153
588	1129
589	19
589	184
589	1156
589	29
589	124
589	55
589	30
589	26
589	1225
589	28
589	33
589	1197
589	1198
589	1199
589	1200
589	1201
589	1202
589	60
589	123
589	126
589	140
589	141
589	173
589	177
589	57
590	1119
590	1135
590	1168
590	1122
590	1123
590	1124
590	1125
590	1126
590	1226
590	1128
590	1224
590	1227
590	1228
590	1229
590	1230
590	1150
590	1153
590	1129
591	19
591	184
591	1156
591	29
591	124
591	55
591	30
591	26
591	1231
591	28
591	33
591	1197
591	1198
591	1199
591	1200
591	1201
591	1202
591	60
591	123
591	126
591	140
591	141
591	173
591	177
591	57
592	1119
592	1135
592	1168
592	1122
592	1123
592	1124
592	1125
592	1126
592	1232
592	1128
592	1224
592	1227
592	1228
592	1229
592	1230
592	1150
592	1153
592	1129
593	19
593	184
593	1156
593	29
593	124
593	55
593	30
593	26
593	1233
593	28
593	33
593	1197
593	1198
593	1199
593	1200
593	1201
593	1202
593	60
593	123
593	126
593	140
593	141
593	173
593	177
593	57
594	1119
594	1135
594	1168
594	1122
594	1123
594	1124
594	1125
594	1126
594	1234
594	1128
594	1227
594	1228
594	1229
594	1230
594	1235
594	1150
594	1153
594	1129
595	19
595	184
595	1156
595	29
595	124
595	55
595	30
595	26
595	1236
595	28
595	33
595	1197
595	1198
595	1199
595	1200
595	1201
595	1202
595	60
595	123
595	126
595	140
595	141
595	173
595	177
595	57
596	1119
596	1135
596	1168
596	1122
596	1123
596	1124
596	1125
596	1126
596	1237
596	1128
596	1227
596	1228
596	1229
596	1230
596	1238
596	1150
596	1153
596	1129
597	19
597	184
597	1156
597	29
597	124
597	55
597	30
597	26
597	1239
597	28
597	33
597	1197
597	1198
597	1199
597	1200
597	1201
597	1202
597	60
597	123
597	126
597	140
597	141
597	173
597	177
597	57
598	1119
598	1135
598	1168
598	1122
598	1123
598	1124
598	1125
598	1126
598	1240
598	1128
598	1227
598	1228
598	1229
598	1230
598	1241
598	1150
598	1153
598	1129
599	19
599	184
599	1156
599	29
599	124
599	55
599	30
599	26
599	1242
599	28
599	33
599	1197
599	1198
599	1199
599	1200
599	1201
599	1202
599	60
599	123
599	126
599	140
599	141
599	173
599	177
599	57
600	1119
600	1135
600	1168
600	1122
600	1123
600	1124
600	1125
600	1126
600	1243
600	1128
600	1227
600	1228
600	1229
600	1230
600	1244
600	1150
600	1153
600	1129
601	19
601	184
601	1156
601	29
601	124
601	55
601	30
601	26
601	1245
601	28
601	33
601	1197
601	1198
601	1199
601	1200
601	1201
601	1202
601	60
601	123
601	126
601	140
601	141
601	173
601	177
601	57
602	1119
602	1135
602	1168
602	1122
602	1123
602	1124
602	1125
602	1126
602	1246
602	1128
602	1227
602	1228
602	1229
602	1230
602	1247
602	1150
602	1153
602	1129
603	19
603	184
603	1156
603	29
603	124
603	55
603	30
603	26
603	1248
603	28
603	33
603	1197
603	1198
603	1199
603	1200
603	1201
603	1202
603	60
603	123
603	126
603	140
603	141
603	173
603	177
603	57
604	1119
604	1135
604	1168
604	1122
604	1123
604	1124
604	1125
604	1126
604	1249
604	1128
604	1227
604	1228
604	1229
604	1230
604	1250
604	1150
604	1153
604	1129
605	19
605	184
605	1156
605	29
605	124
605	55
605	30
605	26
605	1251
605	28
605	33
605	1197
605	1198
605	1199
605	1200
605	1201
605	1202
605	60
605	123
605	126
605	140
605	141
605	173
605	177
605	57
606	1119
606	1135
606	1168
606	1122
606	1123
606	1124
606	1125
606	1126
606	1252
606	1128
606	1227
606	1228
606	1229
606	1230
606	1253
606	1150
606	1153
606	1129
607	19
607	184
607	1156
607	29
607	124
607	55
607	30
607	26
607	1254
607	28
607	33
607	1197
607	1198
607	1199
607	1200
607	1201
607	1202
607	60
607	123
607	126
607	140
607	141
607	173
607	177
607	57
608	1119
608	1135
608	1168
608	1122
608	1123
608	1124
608	1125
608	1126
608	1255
608	1128
608	1229
608	1230
608	1253
608	1256
608	1257
608	1150
608	1153
608	1129
609	19
609	184
609	1156
609	29
609	124
609	55
609	30
609	26
609	1258
609	28
609	33
609	1197
609	1198
609	1199
609	1200
609	1201
609	1202
609	60
609	123
609	126
609	140
609	141
609	173
609	177
609	57
610	1119
610	1135
610	1168
610	1122
610	1123
610	1124
610	1125
610	1126
610	1259
610	1128
610	1229
610	1230
610	1253
610	1256
610	1257
610	1150
610	1153
610	1129
611	19
611	184
611	1156
611	29
611	124
611	55
611	30
611	26
611	1260
611	28
611	33
611	1197
611	1198
611	1199
611	1200
611	1201
611	1202
611	60
611	123
611	126
611	140
611	141
611	173
611	177
611	57
612	1119
612	1135
612	1168
612	1122
612	1123
612	1124
612	1125
612	1126
612	1261
612	1128
612	1229
612	1230
612	1253
612	1256
612	1257
612	1150
612	1153
612	1129
613	19
613	184
613	1156
613	29
613	124
613	55
613	30
613	26
613	1262
613	28
613	33
613	1197
613	1198
613	1199
613	1201
613	1202
613	60
613	123
613	126
613	140
613	141
613	173
613	177
613	1263
613	57
614	1119
614	1135
614	1168
614	1122
614	1123
614	1124
614	1125
614	1126
614	1264
614	1128
614	1229
614	1230
614	1253
614	1256
614	1257
614	1150
614	1153
614	1129
615	19
615	184
615	1156
615	29
615	124
615	55
615	30
615	26
615	1265
615	28
615	33
615	1199
615	60
615	123
615	126
615	140
615	141
615	173
615	177
615	1263
615	1266
615	1267
615	1268
615	1269
615	57
616	1119
616	1135
616	1168
616	1122
616	1123
616	1124
616	1125
616	1126
616	1270
616	1128
616	1229
616	1230
616	1253
616	1256
616	1257
616	1150
616	1153
616	1129
617	144
617	263
617	146
617	1045
617	162
617	170
617	155
617	151
617	1115
617	153
617	539
617	1030
617	156
617	161
617	168
617	169
617	260
617	1051
617	1089
617	1090
617	1100
617	1101
617	1109
617	1116
617	1271
617	172
618	144
618	263
618	146
618	1045
618	162
618	170
618	155
618	151
618	1115
618	153
618	539
618	1030
618	156
618	168
618	169
618	260
618	1051
618	1272
618	1089
618	1090
618	1100
618	1101
618	1109
618	1116
618	1271
618	172
619	144
619	263
619	146
619	1045
619	162
619	170
619	155
619	151
619	1115
619	153
619	539
619	156
619	168
619	169
619	260
619	1272
619	1273
619	1274
619	1275
619	1276
619	1277
619	1278
619	1279
619	1280
619	1271
619	172
620	144
620	263
620	146
620	1045
620	162
620	170
620	155
620	151
620	1115
620	153
620	539
620	156
620	169
620	260
620	1272
620	1273
620	1274
620	1275
620	1276
620	1277
620	1278
620	1279
620	1280
620	1281
620	1271
620	172
621	144
621	1282
621	146
621	1045
621	162
621	170
621	155
621	151
621	1283
621	153
621	539
621	156
621	169
621	260
621	1272
621	1273
621	1274
621	1275
621	1276
621	1277
621	1278
621	1279
621	1280
621	1281
621	1271
621	172
622	144
622	1282
622	146
622	1045
622	162
622	170
622	155
622	151
622	1283
622	153
622	539
622	156
622	169
622	1272
622	1273
622	1274
622	1275
622	1276
622	1277
622	1278
622	1279
622	1280
622	1281
622	1284
622	1271
622	172
623	144
623	1282
623	146
623	1045
623	162
623	170
623	155
623	151
623	1283
623	153
623	539
623	156
623	1272
623	1273
623	1274
623	1275
623	1276
623	1277
623	1278
623	1279
623	1280
623	1281
623	1284
623	1285
623	1271
623	172
624	144
624	1282
624	146
624	1045
624	162
624	170
624	155
624	151
624	1283
624	153
624	156
624	1272
624	1273
624	1274
624	1275
624	1276
624	1277
624	1278
624	1279
624	1280
624	1281
624	1284
624	1285
624	1286
624	1271
624	172
625	144
625	1282
625	146
625	1045
625	162
625	170
625	155
625	151
625	1283
625	153
625	156
625	1272
625	1273
625	1274
625	1275
625	1276
625	1277
625	1278
625	1279
625	1280
625	1281
625	1284
625	1285
625	1286
625	1287
625	1271
625	172
626	144
626	1282
626	146
626	1045
626	162
626	170
626	155
626	151
626	1283
626	153
626	156
626	1273
626	1274
626	1275
626	1276
626	1277
626	1278
626	1279
626	1280
626	1281
626	1284
626	1285
626	1286
626	1287
626	1288
626	1271
626	172
627	144
627	1289
627	146
627	1045
627	162
627	170
627	155
627	151
627	1290
627	153
627	156
627	1273
627	1274
627	1275
627	1276
627	1277
627	1278
627	1279
627	1280
627	1281
627	1284
627	1285
627	1286
627	1287
627	1288
627	1271
627	172
628	144
628	1289
628	146
628	1045
628	162
628	170
628	155
628	151
628	1290
628	153
628	156
628	1273
628	1274
628	1275
628	1276
628	1277
628	1278
628	1279
628	1280
628	1281
628	1285
628	1286
628	1287
628	1288
628	1291
628	1271
628	172
629	144
629	1289
629	146
629	1045
629	162
629	170
629	155
629	151
629	1290
629	153
629	156
629	1273
629	1274
629	1275
629	1276
629	1277
629	1278
629	1279
629	1280
629	1281
629	1286
629	1287
629	1288
629	1291
629	1292
629	1271
629	172
630	144
630	1289
630	146
630	1045
630	162
630	170
630	155
630	151
630	1290
630	153
630	156
630	1273
630	1274
630	1275
630	1276
630	1277
630	1278
630	1279
630	1280
630	1281
630	1286
630	1287
630	1288
630	1291
630	1292
630	1293
630	1271
630	172
631	144
631	1289
631	146
631	1045
631	162
631	170
631	155
631	151
631	1290
631	153
631	156
631	1273
631	1274
631	1275
631	1276
631	1277
631	1278
631	1279
631	1280
631	1281
631	1286
631	1287
631	1288
631	1291
631	1292
631	1293
631	1294
631	1271
631	172
632	144
632	1289
632	146
632	1045
632	162
632	170
632	155
632	151
632	1290
632	153
632	156
632	1273
632	1274
632	1275
632	1276
632	1277
632	1278
632	1279
632	1280
632	1281
632	1287
632	1288
632	1291
632	1292
632	1293
632	1294
632	1295
632	1271
632	172
633	144
633	1296
633	146
633	1045
633	162
633	170
633	155
633	151
633	1297
633	153
633	156
633	1273
633	1274
633	1275
633	1276
633	1277
633	1278
633	1279
633	1280
633	1281
633	1287
633	1288
633	1291
633	1292
633	1293
633	1294
633	1295
633	1271
633	172
634	144
634	1298
634	146
634	1045
634	162
634	170
634	155
634	151
634	1299
634	153
634	156
634	1273
634	1274
634	1275
634	1276
634	1277
634	1278
634	1279
634	1280
634	1281
634	1288
634	1295
634	1300
634	1301
634	1302
634	1303
634	1304
634	1271
634	172
635	144
635	1298
635	146
635	1045
635	162
635	170
635	155
635	151
635	1305
635	153
635	156
635	1273
635	1274
635	1275
635	1276
635	1277
635	1278
635	1279
635	1280
635	1288
635	1295
635	1300
635	1301
635	1302
635	1303
635	1304
635	1306
635	1271
635	172
636	144
636	1298
636	146
636	1045
636	162
636	170
636	155
636	151
636	1305
636	153
636	156
636	1273
636	1274
636	1275
636	1276
636	1277
636	1278
636	1279
636	1280
636	1295
636	1300
636	1301
636	1302
636	1303
636	1304
636	1306
636	1307
636	1271
636	172
637	144
637	1298
637	1308
637	1045
637	162
637	170
637	155
637	151
637	1309
637	153
637	156
637	1273
637	1274
637	1275
637	1276
637	1277
637	1278
637	1279
637	1280
637	1295
637	1300
637	1301
637	1302
637	1303
637	1304
637	1306
637	1307
637	1271
637	172
638	144
638	1298
638	1308
638	1045
638	162
638	170
638	155
638	151
638	1309
638	153
638	156
638	1273
638	1274
638	1275
638	1276
638	1277
638	1278
638	1279
638	1280
638	1295
638	1300
638	1301
638	1302
638	1303
638	1304
638	1306
638	1310
638	1271
638	172
639	144
639	1298
639	1308
639	1045
639	162
639	170
639	155
639	151
639	1311
639	153
639	156
639	1273
639	1274
639	1275
639	1276
639	1277
639	1278
639	1279
639	1280
639	1295
639	1300
639	1301
639	1302
639	1303
639	1304
639	1306
639	1310
639	1271
639	172
640	144
640	1298
640	1308
640	1045
640	162
640	170
640	155
640	151
640	1312
640	153
640	156
640	1273
640	1274
640	1275
640	1276
640	1277
640	1278
640	1279
640	1280
640	1295
640	1300
640	1301
640	1302
640	1303
640	1304
640	1306
640	1310
640	1271
640	172
641	1313
641	1314
641	1315
641	1316
641	1317
641	1318
641	1319
641	1320
641	1321
641	1322
642	1313
642	1314
642	1315
642	1323
642	1317
642	1318
642	1324
642	1320
642	1321
642	1322
643	1313
643	1314
643	1315
643	1325
643	1326
643	1327
643	1324
643	1320
643	1328
643	1322
643	1329
643	1330
643	1331
643	1332
643	1333
643	1334
643	1335
643	1336
643	1337
643	1338
643	1339
643	1340
643	1341
643	1342
643	1343
643	1344
643	1345
644	1313
644	1314
644	1315
644	1325
644	1326
644	1327
644	1324
644	1320
644	1328
644	1322
644	1329
644	1330
644	1331
644	1332
644	1333
644	1334
644	1335
644	1336
644	1337
644	1338
644	1339
644	1340
644	1341
644	1342
644	1343
644	1344
644	1346
644	1345
645	1313
645	1314
645	1347
645	1325
645	1326
645	1327
645	1324
645	1320
645	1348
645	1322
645	1329
645	1330
645	1331
645	1332
645	1333
645	1334
645	1335
645	1336
645	1337
645	1338
645	1339
645	1340
645	1341
645	1342
645	1343
645	1344
645	1346
645	1345
646	1313
646	1314
646	1347
646	1325
646	1326
646	1327
646	1324
646	1320
646	1348
646	1322
646	1329
646	1330
646	1332
646	1333
646	1334
646	1335
646	1336
646	1337
646	1338
646	1339
646	1340
646	1341
646	1342
646	1343
646	1344
646	1346
646	1349
646	1345
647	1313
647	1314
647	1347
647	1325
647	1326
647	1327
647	1324
647	1320
647	1350
647	1322
647	1329
647	1330
647	1332
647	1333
647	1334
647	1335
647	1336
647	1337
647	1338
647	1339
647	1340
647	1341
647	1342
647	1343
647	1344
647	1346
647	1351
647	1345
648	1313
648	1314
648	1347
648	1325
648	1326
648	1327
648	1324
648	1320
648	1352
648	1322
648	1329
648	1330
648	1332
648	1333
648	1334
648	1335
648	1336
648	1337
648	1338
648	1339
648	1340
648	1341
648	1342
648	1343
648	1344
648	1346
648	1351
648	1345
649	1313
649	1353
649	1347
649	1325
649	1326
649	1327
649	1324
649	1320
649	1354
649	1322
649	1329
649	1330
649	1332
649	1333
649	1334
649	1335
649	1336
649	1337
649	1338
649	1339
649	1340
649	1341
649	1342
649	1343
649	1344
649	1346
649	1351
649	1345
650	1313
650	1353
650	1347
650	1325
650	1326
650	1327
650	1324
650	1320
650	1354
650	1322
650	1329
650	1330
650	1333
650	1334
650	1335
650	1336
650	1337
650	1338
650	1339
650	1340
650	1341
650	1342
650	1343
650	1344
650	1346
650	1351
650	1355
650	1345
651	1313
651	1356
651	1347
651	1325
651	1326
651	1327
651	1324
651	1320
651	1357
651	1322
651	1329
651	1330
651	1333
651	1334
651	1335
651	1336
651	1337
651	1338
651	1339
651	1340
651	1341
651	1342
651	1343
651	1344
651	1346
651	1351
651	1355
651	1345
652	1313
652	1358
652	1347
652	1325
652	1326
652	1327
652	1324
652	1320
652	1359
652	1322
652	1329
652	1330
652	1333
652	1334
652	1335
652	1336
652	1337
652	1338
652	1339
652	1340
652	1341
652	1342
652	1343
652	1344
652	1346
652	1351
652	1355
652	1345
653	1313
653	1360
653	1347
653	1325
653	1326
653	1327
653	1324
653	1320
653	1361
653	1322
653	1329
653	1330
653	1333
653	1334
653	1335
653	1336
653	1337
653	1338
653	1339
653	1340
653	1341
653	1342
653	1343
653	1344
653	1346
653	1351
653	1355
653	1345
654	1313
654	1360
654	1347
654	1325
654	1326
654	1327
654	1324
654	1320
654	1362
654	1322
654	1329
654	1330
654	1333
654	1334
654	1335
654	1336
654	1337
654	1338
654	1339
654	1340
654	1341
654	1342
654	1343
654	1344
654	1346
654	1351
654	1355
654	1345
655	1313
655	1360
655	1347
655	1325
655	1326
655	1327
655	1324
655	1320
655	1363
655	1322
655	1329
655	1330
655	1333
655	1334
655	1335
655	1336
655	1337
655	1338
655	1339
655	1340
655	1341
655	1342
655	1343
655	1344
655	1346
655	1351
655	1355
655	1345
656	1313
656	1364
656	1347
656	1325
656	1326
656	1327
656	1324
656	1320
656	1363
656	1322
656	1329
656	1330
656	1333
656	1334
656	1335
656	1336
656	1337
656	1338
656	1339
656	1340
656	1341
656	1342
656	1343
656	1344
656	1346
656	1351
656	1355
656	1345
657	1313
657	1364
657	1347
657	1325
657	1326
657	1327
657	1324
657	1320
657	1365
657	1322
657	1329
657	1330
657	1333
657	1334
657	1335
657	1336
657	1337
657	1338
657	1339
657	1340
657	1341
657	1342
657	1343
657	1344
657	1346
657	1351
657	1355
657	1345
658	1313
658	1366
658	1347
658	1325
658	1326
658	1327
658	1324
658	1320
658	1367
658	1322
658	1329
658	1330
658	1333
658	1334
658	1335
658	1336
658	1337
658	1338
658	1339
658	1340
658	1341
658	1342
658	1343
658	1344
658	1346
658	1351
658	1355
658	1345
659	1313
659	1366
659	1347
659	1325
659	1326
659	1327
659	1324
659	1320
659	1367
659	1322
659	1329
659	1333
659	1334
659	1335
659	1336
659	1337
659	1338
659	1339
659	1340
659	1341
659	1342
659	1343
659	1344
659	1346
659	1351
659	1355
659	1368
659	1345
660	1313
660	1366
660	1347
660	1325
660	1326
660	1327
660	1324
660	1320
660	1367
660	1322
660	1329
660	1333
660	1334
660	1335
660	1336
660	1337
660	1338
660	1339
660	1340
660	1341
660	1342
660	1343
660	1344
660	1346
660	1351
660	1355
660	1369
660	1345
661	1313
661	1366
661	1347
661	1325
661	1326
661	1327
661	1324
661	1320
661	1367
661	1322
661	1329
661	1333
661	1334
661	1335
661	1336
661	1337
661	1338
661	1339
661	1340
661	1341
661	1342
661	1343
661	1344
661	1346
661	1351
661	1355
661	1370
661	1345
662	1313
662	1366
662	1347
662	1325
662	1326
662	1327
662	1324
662	1320
662	1371
662	1322
662	1329
662	1333
662	1334
662	1335
662	1336
662	1337
662	1338
662	1339
662	1340
662	1341
662	1342
662	1343
662	1344
662	1346
662	1351
662	1355
662	1370
662	1345
663	1313
663	1366
663	1347
663	1325
663	1326
663	1327
663	1324
663	1320
663	1371
663	1322
663	1329
663	1333
663	1334
663	1335
663	1336
663	1337
663	1338
663	1339
663	1340
663	1341
663	1342
663	1343
663	1344
663	1346
663	1351
663	1355
663	1372
663	1345
664	1313
664	1366
664	1347
664	1325
664	1326
664	1327
664	1324
664	1320
664	1371
664	1322
664	1329
664	1333
664	1334
664	1335
664	1337
664	1338
664	1339
664	1340
664	1341
664	1342
664	1343
664	1344
664	1346
664	1351
664	1355
664	1372
664	1373
664	1345
665	1313
665	1366
665	1347
665	1325
665	1326
665	1327
665	1324
665	1320
665	1374
665	1322
665	1329
665	1333
665	1334
665	1335
665	1337
665	1338
665	1339
665	1340
665	1341
665	1342
665	1343
665	1344
665	1346
665	1351
665	1355
665	1372
665	1373
665	1345
666	1313
666	1366
666	1347
666	1325
666	1326
666	1327
666	1324
666	1320
666	1375
666	1322
666	1329
666	1333
666	1334
666	1335
666	1337
666	1338
666	1339
666	1340
666	1341
666	1342
666	1343
666	1344
666	1346
666	1351
666	1355
666	1372
666	1373
666	1345
667	1313
667	1366
667	1347
667	1325
667	1326
667	1327
667	1324
667	1320
667	1375
667	1322
667	1329
667	1333
667	1334
667	1335
667	1337
667	1338
667	1339
667	1340
667	1341
667	1342
667	1343
667	1344
667	1346
667	1351
667	1355
667	1373
667	1376
667	1345
668	1313
668	1366
668	1347
668	1325
668	1326
668	1327
668	1324
668	1320
668	1377
668	1322
668	1329
668	1333
668	1334
668	1335
668	1337
668	1338
668	1339
668	1340
668	1341
668	1342
668	1343
668	1344
668	1346
668	1351
668	1355
668	1373
668	1376
668	1345
669	1313
669	1366
669	1347
669	1325
669	1326
669	1327
669	1324
669	1320
669	1378
669	1322
669	1329
669	1333
669	1334
669	1335
669	1337
669	1338
669	1339
669	1340
669	1341
669	1342
669	1343
669	1344
669	1346
669	1351
669	1355
669	1373
669	1376
669	1345
670	1313
670	1366
670	1347
670	1325
670	1326
670	1327
670	1324
670	1320
670	1378
670	1322
670	1329
670	1333
670	1334
670	1335
670	1337
670	1338
670	1339
670	1340
670	1341
670	1342
670	1343
670	1344
670	1346
670	1351
670	1355
670	1373
670	1379
670	1345
671	1313
671	1366
671	1347
671	1325
671	1326
671	1327
671	1324
671	1320
671	1378
671	1322
671	1329
671	1333
671	1334
671	1335
671	1337
671	1338
671	1339
671	1340
671	1341
671	1342
671	1343
671	1344
671	1346
671	1351
671	1355
671	1379
671	1380
671	1345
672	1313
672	1366
672	1347
672	1325
672	1326
672	1327
672	1324
672	1320
672	1381
672	1322
672	1329
672	1333
672	1334
672	1335
672	1337
672	1338
672	1339
672	1340
672	1341
672	1342
672	1343
672	1344
672	1346
672	1351
672	1355
672	1379
672	1380
672	1345
673	1313
673	1366
673	1347
673	1325
673	1326
673	1327
673	1324
673	1320
673	1382
673	1322
673	1329
673	1333
673	1334
673	1335
673	1337
673	1338
673	1339
673	1340
673	1341
673	1342
673	1343
673	1344
673	1346
673	1351
673	1355
673	1379
673	1380
673	1345
674	1313
674	1366
674	1347
674	1325
674	1326
674	1327
674	1324
674	1320
674	1382
674	1322
674	1329
674	1333
674	1334
674	1335
674	1337
674	1338
674	1339
674	1340
674	1341
674	1342
674	1343
674	1344
674	1346
674	1351
674	1355
674	1379
674	1380
674	1383
674	1345
675	1313
675	1366
675	1347
675	1325
675	1326
675	1327
675	1324
675	1320
675	1384
675	1322
675	1329
675	1333
675	1334
675	1335
675	1337
675	1338
675	1339
675	1340
675	1341
675	1342
675	1343
675	1344
675	1346
675	1351
675	1355
675	1379
675	1380
675	1383
675	1345
676	1313
676	1366
676	1347
676	1325
676	1326
676	1327
676	1324
676	1320
676	1384
676	1322
676	1329
676	1333
676	1334
676	1335
676	1337
676	1338
676	1339
676	1340
676	1341
676	1342
676	1343
676	1344
676	1346
676	1351
676	1355
676	1379
676	1383
676	1385
676	1345
677	1313
677	1366
677	1347
677	1325
677	1326
677	1327
677	1324
677	1320
677	1386
677	1322
677	1329
677	1333
677	1334
677	1335
677	1337
677	1338
677	1339
677	1340
677	1341
677	1342
677	1343
677	1344
677	1346
677	1351
677	1355
677	1379
677	1383
677	1385
677	1345
678	1313
678	1366
678	1347
678	1325
678	1326
678	1327
678	1324
678	1320
678	1387
678	1322
678	1329
678	1333
678	1334
678	1335
678	1337
678	1338
678	1339
678	1340
678	1341
678	1342
678	1343
678	1344
678	1346
678	1351
678	1355
678	1379
678	1383
678	1385
678	1345
679	1313
679	1366
679	1347
679	1325
679	1326
679	1327
679	1324
679	1320
679	1388
679	1322
679	1329
679	1333
679	1334
679	1335
679	1337
679	1338
679	1339
679	1340
679	1341
679	1342
679	1343
679	1344
679	1346
679	1351
679	1355
679	1379
679	1383
679	1385
679	1345
680	1313
680	1366
680	1347
680	1325
680	1326
680	1327
680	1324
680	1320
680	1389
680	1322
680	1329
680	1333
680	1334
680	1335
680	1337
680	1338
680	1339
680	1340
680	1341
680	1342
680	1343
680	1344
680	1346
680	1351
680	1355
680	1379
680	1383
680	1385
680	1345
681	1313
681	1366
681	1347
681	1325
681	1326
681	1327
681	1324
681	1320
681	1390
681	1322
681	1329
681	1333
681	1334
681	1335
681	1337
681	1338
681	1339
681	1340
681	1341
681	1342
681	1343
681	1344
681	1346
681	1351
681	1355
681	1379
681	1383
681	1385
681	1345
682	1313
682	1366
682	1347
682	1325
682	1326
682	1327
682	1324
682	1320
682	1390
682	1322
682	1329
682	1333
682	1334
682	1335
682	1337
682	1338
682	1339
682	1340
682	1341
682	1342
682	1343
682	1344
682	1346
682	1351
682	1355
682	1379
682	1385
682	1391
682	1345
683	1313
683	1366
683	1347
683	1325
683	1326
683	1327
683	1324
683	1320
683	1392
683	1322
683	1329
683	1333
683	1334
683	1335
683	1337
683	1338
683	1339
683	1340
683	1341
683	1342
683	1343
683	1344
683	1346
683	1351
683	1355
683	1379
683	1385
683	1391
683	1345
684	1313
684	1366
684	1347
684	1325
684	1326
684	1327
684	1324
684	1320
684	1393
684	1322
684	1329
684	1333
684	1334
684	1335
684	1337
684	1338
684	1339
684	1340
684	1341
684	1342
684	1343
684	1344
684	1346
684	1351
684	1355
684	1379
684	1385
684	1391
684	1345
685	1313
685	1366
685	1347
685	1325
685	1326
685	1327
685	1324
685	1320
685	1393
685	1322
685	1329
685	1333
685	1334
685	1335
685	1337
685	1338
685	1339
685	1340
685	1341
685	1342
685	1343
685	1344
685	1346
685	1351
685	1355
685	1379
685	1385
685	1394
685	1345
686	1313
686	1366
686	1347
686	1325
686	1326
686	1327
686	1324
686	1320
686	1395
686	1322
686	1329
686	1333
686	1334
686	1335
686	1337
686	1338
686	1339
686	1340
686	1341
686	1342
686	1343
686	1344
686	1346
686	1351
686	1355
686	1379
686	1385
686	1394
686	1345
687	1313
687	1366
687	1347
687	1325
687	1326
687	1327
687	1324
687	1320
687	1396
687	1322
687	1329
687	1333
687	1334
687	1335
687	1337
687	1338
687	1339
687	1340
687	1341
687	1342
687	1343
687	1344
687	1346
687	1351
687	1355
687	1379
687	1385
687	1394
687	1345
688	1313
688	1366
688	1347
688	1325
688	1326
688	1327
688	1324
688	1320
688	1397
688	1322
688	1329
688	1333
688	1334
688	1335
688	1337
688	1338
688	1339
688	1340
688	1341
688	1342
688	1343
688	1344
688	1346
688	1351
688	1355
688	1379
688	1385
688	1394
688	1345
689	1313
689	1366
689	1347
689	1325
689	1326
689	1327
689	1324
689	1320
689	1397
689	1322
689	1333
689	1334
689	1335
689	1337
689	1338
689	1339
689	1340
689	1341
689	1342
689	1343
689	1344
689	1346
689	1351
689	1355
689	1379
689	1385
689	1394
689	1398
689	1345
690	1313
690	1366
690	1347
690	1325
690	1326
690	1327
690	1324
690	1320
690	1399
690	1322
690	1333
690	1334
690	1335
690	1337
690	1338
690	1339
690	1340
690	1341
690	1342
690	1343
690	1344
690	1346
690	1351
690	1355
690	1379
690	1385
690	1394
690	1398
690	1345
691	1313
691	1366
691	1347
691	1325
691	1326
691	1327
691	1324
691	1320
691	1399
691	1322
691	1333
691	1334
691	1335
691	1337
691	1338
691	1339
691	1340
691	1341
691	1342
691	1343
691	1344
691	1346
691	1351
691	1355
691	1379
691	1385
691	1394
691	1400
691	1345
692	1313
692	1366
692	1347
692	1325
692	1326
692	1327
692	1324
692	1320
692	1401
692	1322
692	1333
692	1334
692	1335
692	1337
692	1338
692	1339
692	1340
692	1341
692	1342
692	1343
692	1344
692	1346
692	1351
692	1355
692	1379
692	1385
692	1394
692	1400
692	1345
693	1313
693	1366
693	1347
693	1325
693	1326
693	1327
693	1324
693	1320
693	1401
693	1322
693	1333
693	1334
693	1335
693	1337
693	1338
693	1339
693	1340
693	1341
693	1342
693	1343
693	1344
693	1346
693	1351
693	1355
693	1379
693	1385
693	1394
693	1402
693	1345
694	1313
694	1366
694	1347
694	1325
694	1326
694	1327
694	1324
694	1320
694	1403
694	1322
694	1333
694	1334
694	1335
694	1337
694	1338
694	1339
694	1340
694	1341
694	1342
694	1343
694	1344
694	1346
694	1351
694	1355
694	1379
694	1385
694	1394
694	1402
694	1345
695	1313
695	1366
695	1347
695	1325
695	1326
695	1327
695	1324
695	1320
695	1403
695	1322
695	1333
695	1334
695	1335
695	1337
695	1338
695	1339
695	1340
695	1341
695	1342
695	1343
695	1344
695	1346
695	1351
695	1355
695	1379
695	1385
695	1394
695	1404
695	1345
696	1313
696	1366
696	1347
696	1325
696	1326
696	1327
696	1324
696	1320
696	1403
696	1322
696	1333
696	1334
696	1335
696	1337
696	1338
696	1339
696	1340
696	1341
696	1342
696	1343
696	1344
696	1346
696	1351
696	1355
696	1379
696	1385
696	1394
696	1405
696	1345
697	1313
697	1366
697	1347
697	1325
697	1326
697	1327
697	1324
697	1320
697	1403
697	1322
697	1333
697	1334
697	1335
697	1337
697	1338
697	1339
697	1340
697	1341
697	1342
697	1343
697	1344
697	1346
697	1351
697	1355
697	1379
697	1385
697	1394
697	1406
697	1345
698	1313
698	1366
698	1347
698	1325
698	1326
698	1327
698	1324
698	1320
698	1403
698	1322
698	1333
698	1334
698	1335
698	1337
698	1338
698	1339
698	1340
698	1341
698	1342
698	1343
698	1344
698	1346
698	1351
698	1355
698	1379
698	1385
698	1394
698	1407
698	1345
699	1313
699	1408
699	1347
699	1325
699	1326
699	1327
699	1324
699	1320
699	1409
699	1322
699	1333
699	1334
699	1335
699	1337
699	1338
699	1339
699	1340
699	1341
699	1342
699	1343
699	1344
699	1346
699	1351
699	1355
699	1379
699	1385
699	1394
699	1407
699	1345
700	1313
700	1408
700	1347
700	1325
700	1326
700	1327
700	1324
700	1320
700	1409
700	1322
700	1333
700	1334
700	1335
700	1337
700	1338
700	1339
700	1340
700	1341
700	1342
700	1343
700	1344
700	1346
700	1351
700	1355
700	1379
700	1385
700	1394
700	1410
700	1345
701	1313
701	1408
701	1347
701	1325
701	1326
701	1327
701	1324
701	1320
701	1409
701	1322
701	1333
701	1334
701	1335
701	1337
701	1338
701	1339
701	1340
701	1341
701	1342
701	1343
701	1344
701	1346
701	1351
701	1355
701	1379
701	1385
701	1394
701	1411
701	1345
702	1313
702	1408
702	1347
702	1325
702	1326
702	1327
702	1324
702	1320
702	1409
702	1322
702	1333
702	1334
702	1335
702	1337
702	1338
702	1339
702	1340
702	1341
702	1342
702	1343
702	1344
702	1346
702	1351
702	1355
702	1385
702	1394
702	1411
702	1412
702	1345
703	1313
703	1408
703	1347
703	1325
703	1326
703	1327
703	1324
703	1320
703	1409
703	1322
703	1333
703	1334
703	1337
703	1338
703	1339
703	1340
703	1341
703	1342
703	1343
703	1344
703	1346
703	1351
703	1355
703	1385
703	1394
703	1411
703	1412
703	1413
703	1345
704	1313
704	1408
704	1347
704	1325
704	1326
704	1327
704	1324
704	1320
704	1409
704	1322
704	1333
704	1334
704	1337
704	1338
704	1339
704	1340
704	1341
704	1342
704	1343
704	1344
704	1346
704	1351
704	1355
704	1385
704	1394
704	1411
704	1413
704	1414
704	1345
705	1313
705	1408
705	1347
705	1325
705	1326
705	1327
705	1324
705	1320
705	1409
705	1322
705	1333
705	1334
705	1337
705	1338
705	1339
705	1340
705	1341
705	1342
705	1343
705	1344
705	1346
705	1351
705	1355
705	1385
705	1394
705	1411
705	1413
705	1415
705	1345
706	1313
706	1408
706	1347
706	1325
706	1326
706	1327
706	1324
706	1320
706	1409
706	1322
706	1333
706	1334
706	1337
706	1338
706	1339
706	1340
706	1341
706	1342
706	1343
706	1344
706	1346
706	1351
706	1355
706	1385
706	1394
706	1411
706	1413
706	1416
706	1345
707	1313
707	1408
707	1347
707	1325
707	1326
707	1327
707	1324
707	1320
707	1409
707	1322
707	1333
707	1334
707	1337
707	1338
707	1339
707	1340
707	1341
707	1342
707	1343
707	1344
707	1346
707	1351
707	1355
707	1385
707	1394
707	1411
707	1413
707	1417
707	1345
708	1313
708	1408
708	1347
708	1325
708	1326
708	1327
708	1324
708	1320
708	1409
708	1322
708	1333
708	1334
708	1337
708	1338
708	1339
708	1340
708	1341
708	1342
708	1343
708	1344
708	1346
708	1351
708	1355
708	1385
708	1394
708	1411
708	1413
708	1418
708	1345
709	1313
709	1408
709	1347
709	1325
709	1326
709	1327
709	1324
709	1320
709	1409
709	1322
709	1333
709	1334
709	1337
709	1338
709	1339
709	1340
709	1341
709	1342
709	1343
709	1344
709	1346
709	1351
709	1355
709	1385
709	1394
709	1411
709	1413
709	1419
709	1345
710	1313
710	1408
710	1347
710	1325
710	1326
710	1327
710	1324
710	1320
710	1409
710	1322
710	1333
710	1334
710	1337
710	1338
710	1339
710	1340
710	1341
710	1342
710	1343
710	1344
710	1346
710	1351
710	1355
710	1385
710	1394
710	1411
710	1413
710	1420
710	1345
711	1313
711	1408
711	1347
711	1325
711	1326
711	1327
711	1324
711	1320
711	1409
711	1322
711	1333
711	1334
711	1337
711	1338
711	1339
711	1340
711	1341
711	1342
711	1343
711	1344
711	1346
711	1351
711	1355
711	1385
711	1394
711	1411
711	1413
711	1421
711	1345
712	1313
712	1408
712	1347
712	1325
712	1326
712	1327
712	1324
712	1320
712	1409
712	1322
712	1333
712	1334
712	1337
712	1338
712	1339
712	1340
712	1341
712	1342
712	1343
712	1344
712	1346
712	1422
712	1351
712	1355
712	1385
712	1394
712	1411
712	1413
712	1345
713	1313
713	1408
713	1347
713	1325
713	1326
713	1327
713	1324
713	1320
713	1409
713	1322
713	1333
713	1334
713	1337
713	1338
713	1339
713	1340
713	1341
713	1342
713	1343
713	1344
713	1346
713	1351
713	1355
713	1423
713	1385
713	1394
713	1411
713	1413
713	1345
714	1313
714	1408
714	1347
714	1325
714	1326
714	1327
714	1324
714	1320
714	1409
714	1322
714	1333
714	1334
714	1337
714	1338
714	1339
714	1340
714	1341
714	1342
714	1343
714	1344
714	1346
714	1351
714	1355
714	1424
714	1385
714	1394
714	1411
714	1413
714	1345
715	1313
715	1408
715	1347
715	1325
715	1326
715	1327
715	1324
715	1320
715	1409
715	1322
715	1333
715	1334
715	1337
715	1338
715	1339
715	1340
715	1341
715	1342
715	1343
715	1344
715	1346
715	1351
715	1355
715	1425
715	1385
715	1394
715	1411
715	1413
715	1345
716	1313
716	1408
716	1347
716	1325
716	1326
716	1327
716	1324
716	1320
716	1409
716	1322
716	1333
716	1334
716	1337
716	1338
716	1339
716	1340
716	1341
716	1342
716	1343
716	1344
716	1346
716	1351
716	1355
716	1426
716	1385
716	1394
716	1411
716	1413
716	1345
717	1313
717	1408
717	1347
717	1325
717	1326
717	1327
717	1324
717	1320
717	1409
717	1322
717	1333
717	1334
717	1337
717	1338
717	1339
717	1340
717	1341
717	1342
717	1343
717	1344
717	1346
717	1351
717	1355
717	1427
717	1385
717	1394
717	1411
717	1413
717	1345
718	1313
718	1408
718	1347
718	1325
718	1326
718	1327
718	1324
718	1320
718	1409
718	1322
718	1333
718	1334
718	1337
718	1338
718	1339
718	1340
718	1341
718	1342
718	1343
718	1344
718	1346
718	1351
718	1355
718	1428
718	1385
718	1394
718	1411
718	1413
718	1345
719	1313
719	1408
719	1347
719	1325
719	1326
719	1327
719	1324
719	1320
719	1409
719	1322
719	1333
719	1334
719	1337
719	1338
719	1339
719	1340
719	1341
719	1342
719	1343
719	1344
719	1346
719	1351
719	1355
719	1429
719	1385
719	1394
719	1411
719	1413
719	1345
720	1313
720	1408
720	1347
720	1325
720	1326
720	1327
720	1324
720	1320
720	1409
720	1322
720	1333
720	1334
720	1337
720	1338
720	1339
720	1340
720	1341
720	1342
720	1343
720	1344
720	1346
720	1351
720	1355
720	1430
720	1385
720	1394
720	1411
720	1413
720	1345
721	1313
721	1408
721	1347
721	1325
721	1326
721	1327
721	1324
721	1320
721	1409
721	1322
721	1333
721	1334
721	1337
721	1338
721	1339
721	1340
721	1341
721	1342
721	1343
721	1344
721	1346
721	1351
721	1355
721	1385
721	1431
721	1394
721	1411
721	1413
721	1345
722	1313
722	1408
722	1347
722	1325
722	1326
722	1327
722	1324
722	1320
722	1409
722	1322
722	1333
722	1334
722	1337
722	1338
722	1339
722	1340
722	1341
722	1342
722	1343
722	1344
722	1346
722	1351
722	1355
722	1385
722	1394
722	1432
722	1411
722	1413
722	1345
723	1313
723	1408
723	1347
723	1325
723	1326
723	1327
723	1324
723	1320
723	1409
723	1322
723	1333
723	1334
723	1337
723	1338
723	1339
723	1340
723	1341
723	1342
723	1343
723	1344
723	1346
723	1351
723	1355
723	1385
723	1394
723	1433
723	1411
723	1413
723	1345
724	1313
724	1408
724	1347
724	1325
724	1326
724	1327
724	1324
724	1320
724	1409
724	1322
724	1333
724	1334
724	1337
724	1338
724	1339
724	1340
724	1341
724	1342
724	1343
724	1344
724	1346
724	1351
724	1355
724	1385
724	1394
724	1434
724	1411
724	1413
724	1345
725	1313
725	1408
725	1347
725	1325
725	1326
725	1327
725	1324
725	1320
725	1409
725	1322
725	1333
725	1334
725	1337
725	1338
725	1339
725	1340
725	1341
725	1342
725	1343
725	1344
725	1346
725	1351
725	1355
725	1385
725	1394
725	1435
725	1411
725	1413
725	1345
726	1313
726	1408
726	1347
726	1325
726	1326
726	1327
726	1324
726	1320
726	1409
726	1322
726	1333
726	1334
726	1337
726	1338
726	1339
726	1340
726	1341
726	1342
726	1343
726	1344
726	1346
726	1351
726	1355
726	1385
726	1394
726	1436
726	1411
726	1413
726	1345
727	1313
727	1408
727	1347
727	1325
727	1326
727	1327
727	1324
727	1320
727	1409
727	1322
727	1333
727	1334
727	1337
727	1338
727	1339
727	1340
727	1341
727	1342
727	1343
727	1344
727	1346
727	1351
727	1355
727	1385
727	1394
727	1437
727	1411
727	1413
727	1345
728	1313
728	1408
728	1347
728	1325
728	1326
728	1327
728	1324
728	1320
728	1409
728	1322
728	1333
728	1334
728	1337
728	1338
728	1339
728	1340
728	1341
728	1342
728	1343
728	1344
728	1346
728	1351
728	1355
728	1385
728	1394
728	1438
728	1411
728	1413
728	1345
729	1313
729	1408
729	1347
729	1325
729	1326
729	1327
729	1324
729	1320
729	1409
729	1322
729	1333
729	1334
729	1337
729	1338
729	1339
729	1340
729	1341
729	1342
729	1343
729	1344
729	1346
729	1351
729	1355
729	1385
729	1394
729	1439
729	1411
729	1413
729	1345
730	1313
730	1408
730	1347
730	1325
730	1326
730	1327
730	1324
730	1320
730	1409
730	1322
730	1333
730	1334
730	1337
730	1338
730	1339
730	1340
730	1341
730	1342
730	1343
730	1344
730	1346
730	1351
730	1355
730	1385
730	1394
730	1411
730	1440
730	1413
730	1345
731	1313
731	1408
731	1347
731	1325
731	1326
731	1327
731	1324
731	1320
731	1409
731	1322
731	1333
731	1334
731	1337
731	1338
731	1339
731	1340
731	1341
731	1342
731	1343
731	1344
731	1346
731	1351
731	1355
731	1385
731	1394
731	1411
731	1413
731	1441
731	1345
732	1313
732	1408
732	1347
732	1325
732	1326
732	1327
732	1324
732	1320
732	1409
732	1322
732	1333
732	1334
732	1337
732	1338
732	1339
732	1340
732	1341
732	1342
732	1343
732	1344
732	1346
732	1351
732	1355
732	1385
732	1394
732	1411
732	1413
732	1442
732	1345
733	1313
733	1408
733	1347
733	1325
733	1326
733	1327
733	1324
733	1320
733	1409
733	1322
733	1333
733	1334
733	1337
733	1338
733	1339
733	1340
733	1341
733	1342
733	1343
733	1344
733	1346
733	1351
733	1355
733	1385
733	1394
733	1411
733	1413
733	1443
733	1345
734	1313
734	1408
734	1347
734	1325
734	1326
734	1327
734	1324
734	1320
734	1409
734	1322
734	1333
734	1334
734	1337
734	1338
734	1339
734	1340
734	1341
734	1342
734	1343
734	1344
734	1346
734	1351
734	1355
734	1385
734	1394
734	1411
734	1413
734	1444
734	1345
735	1313
735	1408
735	1347
735	1325
735	1326
735	1327
735	1324
735	1320
735	1409
735	1322
735	1333
735	1334
735	1337
735	1338
735	1339
735	1340
735	1341
735	1342
735	1343
735	1344
735	1346
735	1351
735	1355
735	1385
735	1394
735	1411
735	1413
735	1445
735	1345
736	1313
736	1408
736	1347
736	1325
736	1326
736	1327
736	1324
736	1320
736	1409
736	1322
736	1333
736	1334
736	1337
736	1338
736	1339
736	1340
736	1341
736	1342
736	1343
736	1344
736	1346
736	1351
736	1355
736	1385
736	1394
736	1411
736	1413
736	1446
736	1345
737	1313
737	1408
737	1347
737	1325
737	1326
737	1327
737	1324
737	1320
737	1409
737	1322
737	1333
737	1334
737	1337
737	1338
737	1339
737	1340
737	1341
737	1342
737	1343
737	1344
737	1346
737	1351
737	1355
737	1385
737	1394
737	1411
737	1413
737	1447
737	1345
738	1313
738	1408
738	1347
738	1325
738	1326
738	1327
738	1324
738	1320
738	1409
738	1322
738	1333
738	1334
738	1337
738	1338
738	1339
738	1340
738	1341
738	1342
738	1343
738	1344
738	1346
738	1351
738	1355
738	1385
738	1394
738	1411
738	1413
738	1448
738	1345
739	1313
739	1408
739	1347
739	1325
739	1326
739	1327
739	1324
739	1320
739	1409
739	1322
739	1333
739	1334
739	1337
739	1338
739	1339
739	1340
739	1341
739	1342
739	1343
739	1344
739	1346
739	1351
739	1355
739	1385
739	1394
739	1411
739	1413
739	1449
739	1345
740	1313
740	1408
740	1347
740	1325
740	1326
740	1327
740	1324
740	1320
740	1409
740	1322
740	1333
740	1334
740	1337
740	1338
740	1339
740	1340
740	1341
740	1342
740	1343
740	1344
740	1346
740	1351
740	1355
740	1385
740	1394
740	1411
740	1413
740	1450
740	1345
741	1313
741	1408
741	1347
741	1325
741	1326
741	1327
741	1324
741	1320
741	1409
741	1322
741	1333
741	1334
741	1337
741	1338
741	1339
741	1340
741	1341
741	1342
741	1343
741	1344
741	1346
741	1351
741	1355
741	1385
741	1394
741	1411
741	1413
741	1451
741	1345
742	1313
742	1408
742	1347
742	1325
742	1326
742	1327
742	1324
742	1320
742	1409
742	1322
742	1333
742	1334
742	1337
742	1338
742	1339
742	1340
742	1341
742	1342
742	1343
742	1344
742	1346
742	1351
742	1355
742	1385
742	1394
742	1411
742	1413
742	1452
742	1345
743	1313
743	1408
743	1347
743	1325
743	1326
743	1327
743	1324
743	1320
743	1409
743	1322
743	1333
743	1334
743	1337
743	1338
743	1339
743	1340
743	1341
743	1342
743	1343
743	1344
743	1346
743	1351
743	1355
743	1385
743	1394
743	1411
743	1413
743	1453
743	1345
744	1313
744	1408
744	1347
744	1325
744	1326
744	1327
744	1324
744	1320
744	1409
744	1322
744	1333
744	1334
744	1337
744	1338
744	1339
744	1340
744	1341
744	1342
744	1343
744	1344
744	1346
744	1351
744	1355
744	1385
744	1394
744	1413
744	1453
744	1454
744	1345
745	1313
745	1455
745	1347
745	1325
745	1326
745	1327
745	1324
745	1320
745	1456
745	1322
745	1333
745	1334
745	1337
745	1338
745	1339
745	1340
745	1341
745	1342
745	1343
745	1344
745	1346
745	1351
745	1355
745	1385
745	1394
745	1413
745	1453
745	1454
745	1345
746	1313
746	1457
746	1347
746	1325
746	1326
746	1327
746	1324
746	1320
746	1458
746	1322
746	1333
746	1334
746	1337
746	1338
746	1339
746	1340
746	1341
746	1342
746	1343
746	1344
746	1346
746	1351
746	1355
746	1385
746	1394
746	1413
746	1453
746	1454
746	1345
747	1313
747	1457
747	1347
747	1325
747	1326
747	1327
747	1324
747	1320
747	1458
747	1322
747	1333
747	1334
747	1337
747	1338
747	1339
747	1340
747	1341
747	1342
747	1343
747	1344
747	1346
747	1351
747	1355
747	1385
747	1394
747	1413
747	1454
747	1459
747	1345
748	1313
748	1457
748	1347
748	1325
748	1326
748	1327
748	1324
748	1320
748	1458
748	1322
748	1333
748	1334
748	1337
748	1338
748	1339
748	1340
748	1341
748	1342
748	1343
748	1344
748	1346
748	1351
748	1355
748	1385
748	1394
748	1413
748	1454
748	1460
748	1345
749	1313
749	1457
749	1347
749	1325
749	1326
749	1327
749	1324
749	1320
749	1458
749	1322
749	1333
749	1334
749	1337
749	1338
749	1339
749	1340
749	1341
749	1342
749	1343
749	1344
749	1346
749	1351
749	1355
749	1385
749	1394
749	1413
749	1454
749	1461
749	1345
750	1313
750	1457
750	1347
750	1325
750	1326
750	1327
750	1324
750	1320
750	1458
750	1322
750	1333
750	1334
750	1337
750	1338
750	1339
750	1340
750	1341
750	1342
750	1343
750	1344
750	1346
750	1462
750	1351
750	1355
750	1385
750	1394
750	1413
750	1454
750	1345
751	1313
751	1457
751	1347
751	1325
751	1326
751	1327
751	1324
751	1320
751	1458
751	1322
751	1333
751	1334
751	1337
751	1338
751	1339
751	1340
751	1341
751	1342
751	1343
751	1344
751	1346
751	1351
751	1355
751	1463
751	1385
751	1394
751	1413
751	1454
751	1345
752	1464
752	1465
752	1466
752	1467
752	1468
752	1469
752	1470
752	1471
752	1472
752	1473
753	1464
753	1465
753	1466
753	1474
753	1468
753	1469
753	1475
753	1471
753	1472
753	1473
754	1464
754	1465
754	1466
754	1474
754	1468
754	1469
754	1475
754	1471
754	1472
754	1473
754	1476
755	1464
755	1465
755	1466
755	1474
755	1468
755	1469
755	1475
755	1471
755	1472
755	1473
755	1476
755	1477
756	1464
756	1478
756	1479
756	1474
756	1468
756	1469
756	1475
756	1471
756	1480
756	1473
756	1476
756	1477
756	1481
756	1482
756	1483
756	1484
756	1485
757	1464
757	1478
757	1479
757	1474
757	1468
757	1469
757	1475
757	1471
757	1486
757	1473
757	1476
757	1477
757	1481
757	1482
757	1483
757	1484
757	1485
757	1487
757	1488
758	1464
758	1478
758	1479
758	1474
758	1468
758	1469
758	1475
758	1471
758	1486
758	1473
758	1476
758	1477
758	1481
758	1482
758	1483
758	1484
758	1485
758	1487
758	1488
758	1489
759	1464
759	1478
759	1479
759	1474
759	1468
759	1469
759	1475
759	1471
759	1486
759	1473
759	1476
759	1477
759	1481
759	1482
759	1483
759	1484
759	1485
759	1487
759	1488
759	1490
760	1491
760	1492
760	1493
760	1494
760	1495
760	1496
760	1497
760	1498
760	1499
760	1500
761	1491
761	1492
761	1493
761	1501
761	1495
761	1496
761	1502
761	1498
761	1499
761	1500
762	1491
762	1492
762	1493
762	1501
762	1495
762	1496
762	1502
762	1498
762	1499
762	1500
762	1503
763	1491
763	1492
763	1504
763	1501
763	1495
763	1496
763	1502
763	1498
763	1505
763	1500
763	1503
763	1506
763	1507
763	1508
763	1509
763	1510
763	1511
763	1512
764	1491
764	1492
764	1504
764	1501
764	1495
764	1496
764	1502
764	1498
764	1505
764	1500
764	1503
764	1506
764	1507
764	1508
764	1509
764	1510
764	1511
764	1512
764	1513
765	1491
765	1492
765	1504
765	1501
765	1495
765	1496
765	1502
765	1498
765	1505
765	1500
765	1503
765	1506
765	1507
765	1508
765	1509
765	1510
765	1511
765	1512
765	1513
765	1514
766	1491
766	1492
766	1504
766	1501
766	1495
766	1496
766	1502
766	1498
766	1505
766	1500
766	1503
766	1506
766	1507
766	1508
766	1509
766	1510
766	1511
766	1512
766	1513
766	1514
766	1515
767	1491
767	1492
767	1504
767	1501
767	1495
767	1496
767	1502
767	1498
767	1505
767	1500
767	1503
767	1506
767	1507
767	1508
767	1509
767	1510
767	1511
767	1512
767	1513
767	1514
767	1515
767	1516
768	1491
768	1492
768	1504
768	1501
768	1495
768	1496
768	1502
768	1498
768	1505
768	1500
768	1503
768	1506
768	1507
768	1508
768	1509
768	1510
768	1511
768	1512
768	1513
768	1514
768	1515
768	1516
768	1517
769	1491
769	1492
769	1504
769	1501
769	1495
769	1496
769	1502
769	1498
769	1505
769	1500
769	1503
769	1506
769	1507
769	1508
769	1509
769	1510
769	1511
769	1512
769	1513
769	1514
769	1515
769	1516
769	1517
769	1518
770	1491
770	1492
770	1504
770	1501
770	1495
770	1496
770	1502
770	1498
770	1505
770	1500
770	1503
770	1506
770	1507
770	1508
770	1509
770	1510
770	1511
770	1512
770	1513
770	1514
770	1515
770	1516
770	1517
770	1518
770	1519
771	1520
771	1521
771	1522
771	1523
771	1524
771	1525
771	1526
771	1527
771	1528
771	1529
772	1520
772	1521
772	1522
772	1530
772	1524
772	1525
772	1531
772	1527
772	1528
772	1529
773	1520
773	1521
773	1522
773	1530
773	1524
773	1525
773	1531
773	1527
773	1528
773	1529
773	1532
774	1520
774	1521
774	1522
774	1530
774	1524
774	1525
774	1531
774	1527
774	1528
774	1529
774	1532
774	1533
775	1520
775	1521
775	1522
775	1530
775	1524
775	1525
775	1531
775	1527
775	1528
775	1529
775	1532
775	1534
776	1520
776	1521
776	1522
776	1530
776	1524
776	1525
776	1531
776	1527
776	1528
776	1529
776	1535
776	1532
777	1520
777	1521
777	1522
777	1530
777	1524
777	1525
777	1531
777	1527
777	1528
777	1529
777	1532
777	1536
778	1520
778	1521
778	1522
778	1530
778	1524
778	1525
778	1531
778	1527
778	1528
778	1529
778	1532
778	1537
779	1520
779	1521
779	1522
779	1530
779	1524
779	1525
779	1531
779	1527
779	1528
779	1529
779	1532
779	1538
780	1520
780	1521
780	1522
780	1530
780	1524
780	1525
780	1531
780	1527
780	1528
780	1529
780	1539
780	1532
781	1540
781	1541
781	1542
781	1543
781	1544
781	1545
781	1546
781	1547
781	1548
781	1549
782	1540
782	1541
782	1542
782	1550
782	1544
782	1545
782	1551
782	1547
782	1548
782	1549
783	1540
783	1541
783	1542
783	1550
783	1544
783	1545
783	1551
783	1547
783	1548
783	1549
783	1552
784	1540
784	1541
784	1542
784	1550
784	1544
784	1545
784	1551
784	1547
784	1548
784	1549
784	1552
784	1553
785	1540
785	1541
785	1542
785	1550
785	1544
785	1545
785	1551
785	1547
785	1548
785	1549
785	1552
785	1554
786	1555
786	1556
786	1557
786	1558
786	1559
786	1560
786	1561
786	1562
786	1563
786	1564
787	1555
787	1556
787	1557
787	1565
787	1559
787	1560
787	1566
787	1562
787	1563
787	1564
788	1555
788	1556
788	1557
788	1565
788	1559
788	1560
788	1566
788	1562
788	1563
788	1564
788	1567
789	1555
789	1556
789	1557
789	1565
789	1559
789	1560
789	1566
789	1562
789	1563
789	1564
789	1567
789	1568
790	1555
790	1556
790	1557
790	1565
790	1559
790	1560
790	1566
790	1562
790	1563
790	1564
790	1567
790	1569
791	1570
791	1571
791	1572
791	1573
791	1574
791	1575
791	1576
791	1577
791	1578
791	1579
792	1570
792	1571
792	1572
792	1580
792	1574
792	1575
792	1581
792	1577
792	1578
792	1579
793	1570
793	1571
793	1572
793	1580
793	1574
793	1575
793	1581
793	1577
793	1578
793	1579
793	1582
794	1570
794	1571
794	1572
794	1580
794	1574
794	1575
794	1581
794	1577
794	1578
794	1579
794	1582
794	1583
795	1570
795	1571
795	1572
795	1580
795	1574
795	1575
795	1581
795	1577
795	1578
795	1579
795	1582
795	1583
795	1584
796	1570
796	1585
796	1572
796	1580
796	1574
796	1575
796	1581
796	1577
796	1586
796	1579
796	1582
796	1583
796	1584
797	1570
797	1587
797	1572
797	1580
797	1574
797	1575
797	1581
797	1577
797	1588
797	1579
797	1582
797	1583
797	1584
798	1570
798	1587
798	1572
798	1580
798	1574
798	1575
798	1581
798	1577
798	1588
798	1579
798	1582
798	1583
798	1584
798	1589
799	1570
799	1587
799	1572
799	1580
799	1574
799	1575
799	1581
799	1577
799	1588
799	1579
799	1582
799	1583
799	1584
799	1589
799	1590
800	1570
800	1587
800	1572
800	1580
800	1574
800	1575
800	1581
800	1577
800	1588
800	1579
800	1582
800	1583
800	1584
800	1589
800	1590
800	1591
801	1570
801	1587
801	1592
801	1580
801	1574
801	1575
801	1581
801	1577
801	1593
801	1579
801	1582
801	1583
801	1584
801	1589
801	1590
801	1591
801	1594
801	1595
801	1596
801	1597
801	1598
801	1599
802	1570
802	1587
802	1592
802	1580
802	1574
802	1575
802	1581
802	1577
802	1600
802	1579
802	1582
802	1583
802	1584
802	1589
802	1590
802	1591
802	1594
802	1595
802	1596
802	1597
802	1598
802	1599
802	1601
803	1570
803	1587
803	1592
803	1580
803	1574
803	1575
803	1581
803	1577
803	1600
803	1579
803	1582
803	1583
803	1584
803	1589
803	1590
803	1591
803	1594
803	1595
803	1596
803	1597
803	1598
803	1599
803	1601
803	1602
804	1570
804	1587
804	1592
804	1580
804	1574
804	1575
804	1581
804	1577
804	1600
804	1579
804	1582
804	1583
804	1584
804	1589
804	1590
804	1591
804	1594
804	1595
804	1596
804	1597
804	1598
804	1599
804	1601
804	1602
804	1603
805	1570
805	1587
805	1592
805	1580
805	1574
805	1575
805	1581
805	1577
805	1600
805	1579
805	1582
805	1583
805	1584
805	1589
805	1590
805	1591
805	1594
805	1595
805	1596
805	1597
805	1598
805	1599
805	1601
805	1602
805	1603
805	1604
806	1570
806	1587
806	1592
806	1580
806	1574
806	1575
806	1581
806	1577
806	1600
806	1579
806	1582
806	1584
806	1589
806	1590
806	1591
806	1594
806	1595
806	1596
806	1597
806	1598
806	1599
806	1601
806	1602
806	1603
806	1604
806	1605
807	1570
807	1587
807	1592
807	1580
807	1574
807	1575
807	1581
807	1577
807	1600
807	1579
807	1582
807	1584
807	1589
807	1590
807	1591
807	1594
807	1595
807	1596
807	1597
807	1598
807	1599
807	1601
807	1602
807	1603
807	1604
807	1606
808	1313
808	1457
808	1347
808	1325
808	1326
808	1327
808	1324
808	1320
808	1458
808	1322
808	1333
808	1334
808	1337
808	1338
808	1339
808	1340
808	1341
808	1342
808	1343
808	1344
808	1346
808	1351
808	1355
808	1463
808	1385
808	1394
808	1413
808	1607
808	1345
809	144
809	1298
809	1308
809	1045
809	162
809	170
809	155
809	151
809	1312
809	153
809	156
809	1273
809	1274
809	1275
809	1276
809	1277
809	1278
809	1279
809	1280
809	1295
809	1300
809	1301
809	1302
809	1303
809	1304
809	1310
809	1608
809	1271
809	172
810	144
810	1298
810	1308
810	1045
810	162
810	170
810	155
810	151
810	1312
810	153
810	156
810	1273
810	1274
810	1275
810	1276
810	1277
810	1278
810	1279
810	1280
810	1295
810	1300
810	1301
810	1302
810	1303
810	1304
810	1609
810	1310
810	1271
810	172
811	144
811	1298
811	1308
811	1045
811	162
811	170
811	155
811	151
811	1312
811	153
811	156
811	1273
811	1274
811	1275
811	1276
811	1277
811	1278
811	1279
811	1280
811	1295
811	1300
811	1301
811	1302
811	1303
811	1304
811	1310
811	1610
811	1271
811	172
812	1611
812	1612
812	1613
812	1614
812	1615
812	1616
812	1617
812	1618
812	1619
812	1620
813	1611
813	1612
813	1613
813	1621
813	1615
813	1616
813	1622
813	1618
813	1619
813	1620
814	1611
814	1612
814	1613
814	1621
814	1615
814	1616
814	1622
814	1618
814	1619
814	1620
814	1623
\.


--
-- Data for Name: evaluation_method_configuration; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.evaluation_method_configuration (id, opportunity_id, type) FROM stdin;
1	1	documentary
2	2	documentary
3	3	documentary
\.


--
-- Data for Name: evaluationmethodconfiguration_meta; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.evaluationmethodconfiguration_meta (id, object_id, key, value) FROM stdin;
\.


--
-- Data for Name: event; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.event (id, project_id, name, short_description, long_description, rules, create_timestamp, status, agent_id, is_verified, type, update_timestamp, subsite_id) FROM stdin;
\.


--
-- Data for Name: event_attendance; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.event_attendance (id, user_id, event_occurrence_id, event_id, space_id, type, reccurrence_string, start_timestamp, end_timestamp, create_timestamp) FROM stdin;
\.


--
-- Data for Name: event_meta; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.event_meta (key, object_id, value, id) FROM stdin;
\.


--
-- Data for Name: event_occurrence; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.event_occurrence (id, space_id, event_id, rule, starts_on, ends_on, starts_at, ends_at, frequency, separation, count, until, timezone_name, status) FROM stdin;
\.


--
-- Data for Name: event_occurrence_cancellation; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.event_occurrence_cancellation (id, event_occurrence_id, date) FROM stdin;
\.


--
-- Data for Name: event_occurrence_recurrence; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.event_occurrence_recurrence (id, event_occurrence_id, month, day, week) FROM stdin;
\.


--
-- Data for Name: file; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.file (id, md5, mime_type, name, object_type, object_id, create_timestamp, grp, description, parent_id, path, private) FROM stdin;
2	81005053fd1088e5c30006f027fdfd2f	image/png	blob-9399e7db09a2c32015e5afe28bec2d9e.png	MapasCulturais\\Entities\\Agent	1	2020-07-29 19:36:45	img:avatarSmall	\N	1	agent/1/file/1/blob-9399e7db09a2c32015e5afe28bec2d9e.png	f
3	65b5578b2b0597dc10f73735e8978cd9	image/png	blob-7cad5f421f4a6a4b4b8cedfebdcacc6d.png	MapasCulturais\\Entities\\Agent	1	2020-07-29 19:36:45	img:avatarMedium	\N	1	agent/1/file/1/blob-7cad5f421f4a6a4b4b8cedfebdcacc6d.png	f
4	732f41fbadf70ad1850303d6a7f968b8	image/png	blob-a545baf6ed917bc749a46228bdbe6f5e.png	MapasCulturais\\Entities\\Agent	1	2020-07-29 19:36:45	img:avatarBig	\N	1	agent/1/file/1/blob-a545baf6ed917bc749a46228bdbe6f5e.png	f
1	94726287499c3379957729a002d0c06d	image/png	blob.png	MapasCulturais\\Entities\\Agent	1	2020-07-29 19:36:45	avatar	\N	\N	agent/1/blob.png	f
7	732f41fbadf70ad1850303d6a7f968b8	image/png	blob-d4d318691e173a295d7db616333fba0e.png	MapasCulturais\\Entities\\Agent	1	2020-07-29 22:07:34	img:galleryFull	\N	1	agent/1/file/1/blob-d4d318691e173a295d7db616333fba0e.png	f
17	843a03335a601fd22954d5c0bf74c9a1	image/png	on-1689674626 - 5f3f60fe3f62c - arquivo.png	MapasCulturais\\Entities\\Registration	1689674626	2020-08-21 05:51:58	rfc_1	\N	\N	registration/1689674626/on-1689674626 - 5f3f60fe3f62c - arquivo.png	t
18	f7aeae051e633f8c449a4e57cd3e40b7	application/zip	on-1689674626 - 5f3f6e3d1a56f.zip	MapasCulturais\\Entities\\Registration	1689674626	2020-08-21 06:48:29	zipArchive	\N	\N	registration/1689674626/on-1689674626 - 5f3f6e3d1a56f.zip	t
19	1f6269976630825bc9b264324d51f205	image/jpeg	on-902053773 - 5f460b0458822 - AUTODECLARAÇÃO DE ATUAÇÃO NAS ÁREAS ARTÍSTICAS E CULTURAL.jpg	MapasCulturais\\Entities\\Registration	902053773	2020-08-26 07:11:00	rfc_5	\N	\N	registration/902053773/on-902053773 - 5f460b0458822 - AUTODECLARAÇÃO DE ATUAÇÃO NAS ÁREAS ARTÍSTICAS E CULTURAL.jpg	t
20	cb1881c4db03d41020f92a3343bad808	image/jpeg	on-1715162904 - 5f460ca2ea7cb - AUTODECLARAÇÃO DE ATUAÇÃO NAS ÁREAS ARTÍSTICAS E CULTURAL.jpg	MapasCulturais\\Entities\\Registration	1715162904	2020-08-26 07:17:54	rfc_5	\N	\N	registration/1715162904/on-1715162904 - 5f460ca2ea7cb - AUTODECLARAÇÃO DE ATUAÇÃO NAS ÁREAS ARTÍSTICAS E CULTURAL.jpg	t
21	d5d6a0f4c0b31f72e22b1f4e7e9c0051	image/png	on-1076435879 - 5f47b6d065811 - AUTODECLARAÇÃO DE ATUAÇÃO NAS ÁREAS ARTÍSTICAS E CULTURAL.png	MapasCulturais\\Entities\\Registration	1076435879	2020-08-27 13:36:16	rfc_5	\N	\N	registration/1076435879/on-1076435879 - 5f47b6d065811 - AUTODECLARAÇÃO DE ATUAÇÃO NAS ÁREAS ARTÍSTICAS E CULTURAL.png	t
\.


--
-- Data for Name: geo_division; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.geo_division (id, parent_id, type, cod, name, geom) FROM stdin;
\.


--
-- Data for Name: metadata; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.metadata (object_id, object_type, key, value) FROM stdin;
\.


--
-- Data for Name: metalist; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.metalist (id, object_type, object_id, grp, title, description, value, create_timestamp, "order") FROM stdin;
\.


--
-- Data for Name: notification; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.notification (id, user_id, request_id, message, create_timestamp, action_timestamp, status) FROM stdin;
\.


--
-- Data for Name: notification_meta; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.notification_meta (id, object_id, key, value) FROM stdin;
\.


--
-- Data for Name: opportunity; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.opportunity (id, parent_id, agent_id, type, name, short_description, long_description, registration_from, registration_to, published_registrations, registration_categories, create_timestamp, update_timestamp, status, subsite_id, object_type, object_id) FROM stdin;
1	\N	1	1	Nova Oportunidade	\N	\N	\N	\N	f	[]	2020-07-29 19:23:29	\N	0	\N	MapasCulturais\\Entities\\Agent	1
3	\N	1	1	Nova Oportunidade	texto de introdução	\N	2020-08-13 00:00:00	2020-08-27 23:59:00	f	""	2020-08-21 03:19:02	2020-08-25 00:32:43	1	\N	MapasCulturais\\Entities\\Project	1
2	\N	1	1	Lei Aldir Blanc - Inciso I	teste	\N	2020-08-09 00:00:00	2020-11-15 23:59:00	f	""	2020-08-15 22:09:17	2020-08-26 04:53:02	1	\N	MapasCulturais\\Entities\\Project	1
\.


--
-- Data for Name: opportunity_meta; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.opportunity_meta (id, object_id, key, value) FROM stdin;
1	2	useAgentRelationColetivo	dontUse
2	2	registrationLimitPerOwner	1
3	2	registrationCategDescription	Selecione uma categoria
4	2	registrationCategTitle	Categoria
5	2	useAgentRelationInstituicao	dontUse
6	2	registrationSeals	null
7	2	registrationLimit	0
8	2	projectName	0
9	3	useAgentRelationInstituicao	dontUse
11	3	registrationLimit	0
13	3	registrationCategTitle	Categoria
14	3	registrationCategDescription	Selecione uma categoria
15	3	projectName	0
12	3	registrationLimitPerOwner	1
10	3	useAgentRelationColetivo	dontUse
17	3	registrationSeals	null
16	3	useSpaceRelationIntituicao	dontUse
\.


--
-- Data for Name: pcache; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.pcache (id, user_id, action, create_timestamp, object_type, object_id) FROM stdin;
4439	3	@control	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4440	3	create	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4441	3	view	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4442	3	modify	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4443	3	createSpaceRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4444	3	removeSpaceRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4445	3	viewPrivateData	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4446	3	remove	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4447	3	viewPrivateFiles	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4448	3	changeOwner	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4449	3	createAgentRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4450	3	createAgentRelationWithControl	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4451	3	removeAgentRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4452	3	removeAgentRelationWithControl	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4453	3	createSealRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4454	3	removeSealRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1593864955
4455	2	@control	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4456	2	create	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4457	2	view	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4458	2	modify	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4459	2	createSpaceRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4460	2	removeSpaceRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4461	2	viewPrivateData	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4462	2	remove	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4463	2	viewPrivateFiles	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4464	2	changeOwner	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4465	2	createAgentRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4466	2	createAgentRelationWithControl	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4467	2	removeAgentRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4468	2	removeAgentRelationWithControl	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4469	2	createSealRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4470	2	removeSealRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	763896078
4471	4	@control	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4472	4	create	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4473	4	view	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4474	4	modify	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4475	4	createSpaceRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4476	4	removeSpaceRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4477	4	viewPrivateData	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4478	4	remove	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4479	4	viewPrivateFiles	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4480	4	changeOwner	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4481	4	createAgentRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4482	4	createAgentRelationWithControl	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4483	4	removeAgentRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4484	4	removeAgentRelationWithControl	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4485	4	createSealRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4486	4	removeSealRelation	2020-08-25 00:32:49	MapasCulturais\\Entities\\Registration	1967657373
4365	2	@control	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	2
4366	2	create	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	2
4367	2	view	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	2
4368	2	modify	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	2
4369	2	viewPrivateFiles	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	2
4370	2	viewPrivateData	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	2
4371	2	createAgentRelation	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	2
4372	2	createAgentRelationWithControl	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	2
461	3	@control	2020-08-20 23:29:15	MapasCulturais\\Entities\\Agent	3
4373	2	removeAgentRelation	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	2
4374	2	removeAgentRelationWithControl	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	2
2395	4	@control	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2396	4	create	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2397	4	remove	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2398	4	archive	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2399	4	view	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2400	4	modify	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2401	4	viewPrivateFiles	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2402	4	viewPrivateData	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2403	4	createAgentRelation	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2404	4	createAgentRelationWithControl	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2405	4	removeAgentRelation	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2406	4	removeAgentRelationWithControl	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2407	4	createSealRelation	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
2408	4	removeSealRelation	2020-08-24 06:43:52	MapasCulturais\\Entities\\Agent	5
5325	7	viewPrivateFiles	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5326	7	changeOwner	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5327	7	createAgentRelation	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5328	7	createAgentRelationWithControl	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5329	7	removeAgentRelation	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5330	7	removeAgentRelationWithControl	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5331	7	createSealRelation	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5332	7	removeSealRelation	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5357	8	@control	2020-08-26 07:23:09	MapasCulturais\\Entities\\Agent	42
5358	8	create	2020-08-26 07:23:09	MapasCulturais\\Entities\\Agent	42
5359	8	view	2020-08-26 07:23:09	MapasCulturais\\Entities\\Agent	42
5360	8	modify	2020-08-26 07:23:09	MapasCulturais\\Entities\\Agent	42
5361	8	viewPrivateFiles	2020-08-26 07:23:09	MapasCulturais\\Entities\\Agent	42
5362	8	viewPrivateData	2020-08-26 07:23:09	MapasCulturais\\Entities\\Agent	42
5363	8	createAgentRelation	2020-08-26 07:23:09	MapasCulturais\\Entities\\Agent	42
5364	8	createAgentRelationWithControl	2020-08-26 07:23:09	MapasCulturais\\Entities\\Agent	42
5365	8	removeAgentRelation	2020-08-26 07:23:09	MapasCulturais\\Entities\\Agent	42
5366	8	removeAgentRelationWithControl	2020-08-26 07:23:09	MapasCulturais\\Entities\\Agent	42
5367	8	createSealRelation	2020-08-26 07:23:09	MapasCulturais\\Entities\\Agent	42
5368	8	removeSealRelation	2020-08-26 07:23:09	MapasCulturais\\Entities\\Agent	42
5369	8	@control	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5370	8	create	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5371	8	view	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5372	8	modify	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5373	8	createSpaceRelation	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5374	8	removeSpaceRelation	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5375	8	viewPrivateData	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5376	8	remove	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5377	8	viewPrivateFiles	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5378	8	changeOwner	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5379	8	createAgentRelation	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5380	8	createAgentRelationWithControl	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5381	8	removeAgentRelation	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5382	8	removeAgentRelationWithControl	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5383	8	createSealRelation	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5384	8	removeSealRelation	2020-08-26 07:23:09	MapasCulturais\\Entities\\Registration	905535019
5413	10	@control	2020-08-26 07:44:47	MapasCulturais\\Entities\\Agent	44
5414	10	create	2020-08-26 07:44:47	MapasCulturais\\Entities\\Agent	44
5415	10	view	2020-08-26 07:44:47	MapasCulturais\\Entities\\Agent	44
5416	10	modify	2020-08-26 07:44:47	MapasCulturais\\Entities\\Agent	44
462	3	create	2020-08-20 23:29:15	MapasCulturais\\Entities\\Agent	3
463	3	view	2020-08-20 23:29:15	MapasCulturais\\Entities\\Agent	3
464	3	modify	2020-08-20 23:29:15	MapasCulturais\\Entities\\Agent	3
465	3	viewPrivateFiles	2020-08-20 23:29:15	MapasCulturais\\Entities\\Agent	3
466	3	viewPrivateData	2020-08-20 23:29:15	MapasCulturais\\Entities\\Agent	3
467	3	createAgentRelation	2020-08-20 23:29:15	MapasCulturais\\Entities\\Agent	3
468	3	createAgentRelationWithControl	2020-08-20 23:29:15	MapasCulturais\\Entities\\Agent	3
469	3	removeAgentRelation	2020-08-20 23:29:15	MapasCulturais\\Entities\\Agent	3
470	3	removeAgentRelationWithControl	2020-08-20 23:29:15	MapasCulturais\\Entities\\Agent	3
5417	10	viewPrivateFiles	2020-08-26 07:44:47	MapasCulturais\\Entities\\Agent	44
5418	10	viewPrivateData	2020-08-26 07:44:47	MapasCulturais\\Entities\\Agent	44
5419	10	createAgentRelation	2020-08-26 07:44:47	MapasCulturais\\Entities\\Agent	44
5420	10	createAgentRelationWithControl	2020-08-26 07:44:47	MapasCulturais\\Entities\\Agent	44
5421	10	removeAgentRelation	2020-08-26 07:44:47	MapasCulturais\\Entities\\Agent	44
5422	10	removeAgentRelationWithControl	2020-08-26 07:44:47	MapasCulturais\\Entities\\Agent	44
5423	10	createSealRelation	2020-08-26 07:44:47	MapasCulturais\\Entities\\Agent	44
5424	10	removeSealRelation	2020-08-26 07:44:47	MapasCulturais\\Entities\\Agent	44
5453	11	@control	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5454	11	create	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5455	11	view	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5456	11	modify	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5457	11	createSpaceRelation	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5458	11	removeSpaceRelation	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5459	11	viewPrivateData	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5460	11	remove	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
471	3	createSealRelation	2020-08-20 23:29:15	MapasCulturais\\Entities\\Agent	3
472	3	removeSealRelation	2020-08-20 23:29:15	MapasCulturais\\Entities\\Agent	3
4693	5	@control	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4694	5	create	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4695	5	view	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4696	5	modify	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4697	5	createSpaceRelation	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
5229	5	@control	2020-08-26 06:44:33	MapasCulturais\\Entities\\Agent	39
5230	5	create	2020-08-26 06:44:33	MapasCulturais\\Entities\\Agent	39
5231	5	view	2020-08-26 06:44:33	MapasCulturais\\Entities\\Agent	39
5232	5	modify	2020-08-26 06:44:33	MapasCulturais\\Entities\\Agent	39
5233	5	viewPrivateFiles	2020-08-26 06:44:33	MapasCulturais\\Entities\\Agent	39
5234	5	viewPrivateData	2020-08-26 06:44:33	MapasCulturais\\Entities\\Agent	39
5235	5	createAgentRelation	2020-08-26 06:44:33	MapasCulturais\\Entities\\Agent	39
5236	5	createAgentRelationWithControl	2020-08-26 06:44:33	MapasCulturais\\Entities\\Agent	39
5237	5	removeAgentRelation	2020-08-26 06:44:33	MapasCulturais\\Entities\\Agent	39
5238	5	removeAgentRelationWithControl	2020-08-26 06:44:33	MapasCulturais\\Entities\\Agent	39
5239	5	createSealRelation	2020-08-26 06:44:33	MapasCulturais\\Entities\\Agent	39
5240	5	removeSealRelation	2020-08-26 06:44:33	MapasCulturais\\Entities\\Agent	39
5293	6	@control	2020-08-26 07:09:49	MapasCulturais\\Entities\\Agent	40
5294	6	create	2020-08-26 07:09:49	MapasCulturais\\Entities\\Agent	40
5295	6	view	2020-08-26 07:09:49	MapasCulturais\\Entities\\Agent	40
5296	6	modify	2020-08-26 07:09:49	MapasCulturais\\Entities\\Agent	40
5297	6	viewPrivateFiles	2020-08-26 07:09:49	MapasCulturais\\Entities\\Agent	40
5298	6	viewPrivateData	2020-08-26 07:09:49	MapasCulturais\\Entities\\Agent	40
5299	6	createAgentRelation	2020-08-26 07:09:49	MapasCulturais\\Entities\\Agent	40
5300	6	createAgentRelationWithControl	2020-08-26 07:09:49	MapasCulturais\\Entities\\Agent	40
5301	6	removeAgentRelation	2020-08-26 07:09:49	MapasCulturais\\Entities\\Agent	40
5302	6	removeAgentRelationWithControl	2020-08-26 07:09:49	MapasCulturais\\Entities\\Agent	40
5303	6	createSealRelation	2020-08-26 07:09:49	MapasCulturais\\Entities\\Agent	40
5304	6	removeSealRelation	2020-08-26 07:09:49	MapasCulturais\\Entities\\Agent	40
5385	9	@control	2020-08-26 07:43:01	MapasCulturais\\Entities\\Agent	43
5386	9	create	2020-08-26 07:43:01	MapasCulturais\\Entities\\Agent	43
5387	9	view	2020-08-26 07:43:01	MapasCulturais\\Entities\\Agent	43
5388	9	modify	2020-08-26 07:43:01	MapasCulturais\\Entities\\Agent	43
5389	9	viewPrivateFiles	2020-08-26 07:43:01	MapasCulturais\\Entities\\Agent	43
5390	9	viewPrivateData	2020-08-26 07:43:01	MapasCulturais\\Entities\\Agent	43
5391	9	createAgentRelation	2020-08-26 07:43:01	MapasCulturais\\Entities\\Agent	43
5392	9	createAgentRelationWithControl	2020-08-26 07:43:01	MapasCulturais\\Entities\\Agent	43
5393	9	removeAgentRelation	2020-08-26 07:43:01	MapasCulturais\\Entities\\Agent	43
5394	9	removeAgentRelationWithControl	2020-08-26 07:43:01	MapasCulturais\\Entities\\Agent	43
5395	9	createSealRelation	2020-08-26 07:43:01	MapasCulturais\\Entities\\Agent	43
5396	9	removeSealRelation	2020-08-26 07:43:01	MapasCulturais\\Entities\\Agent	43
5425	10	@control	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5426	10	create	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5427	10	view	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5428	10	modify	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5429	10	createSpaceRelation	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5430	10	removeSpaceRelation	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5431	10	viewPrivateData	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5432	10	remove	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5433	10	viewPrivateFiles	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5434	10	changeOwner	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5435	10	createAgentRelation	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5436	10	createAgentRelationWithControl	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5437	10	removeAgentRelation	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5438	10	removeAgentRelationWithControl	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5439	10	createSealRelation	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5440	10	removeSealRelation	2020-08-26 07:45:00	MapasCulturais\\Entities\\Registration	413170950
5461	11	viewPrivateFiles	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5462	11	changeOwner	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5463	11	createAgentRelation	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5464	11	createAgentRelationWithControl	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5465	11	removeAgentRelation	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5466	11	removeAgentRelationWithControl	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5467	11	createSealRelation	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
5468	11	removeSealRelation	2020-08-26 07:47:53	MapasCulturais\\Entities\\Registration	1066273876
4698	5	removeSpaceRelation	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4699	5	viewPrivateData	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4700	5	remove	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4701	5	viewPrivateFiles	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4702	5	changeOwner	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4703	5	createAgentRelation	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4704	5	createAgentRelationWithControl	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4705	5	removeAgentRelation	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4706	5	removeAgentRelationWithControl	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4707	5	createSealRelation	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4708	5	removeSealRelation	2020-08-25 21:45:26	MapasCulturais\\Entities\\Registration	1970483263
4375	2	createSealRelation	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	2
4376	2	removeSealRelation	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	2
4377	2	@control	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4378	2	create	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4379	2	remove	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4380	2	archive	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4381	2	view	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4382	2	modify	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4383	2	viewPrivateFiles	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4384	2	viewPrivateData	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4385	2	createAgentRelation	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4386	2	createAgentRelationWithControl	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4387	2	removeAgentRelation	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4388	2	removeAgentRelationWithControl	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4389	2	createSealRelation	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4390	2	removeSealRelation	2020-08-24 21:56:20	MapasCulturais\\Entities\\Agent	38
4643	4	@control	2020-08-25 21:42:30	MapasCulturais\\Entities\\Agent	4
4644	4	create	2020-08-25 21:42:30	MapasCulturais\\Entities\\Agent	4
4645	4	view	2020-08-25 21:42:30	MapasCulturais\\Entities\\Agent	4
4646	4	modify	2020-08-25 21:42:30	MapasCulturais\\Entities\\Agent	4
4647	4	viewPrivateFiles	2020-08-25 21:42:30	MapasCulturais\\Entities\\Agent	4
4648	4	viewPrivateData	2020-08-25 21:42:30	MapasCulturais\\Entities\\Agent	4
4649	4	createAgentRelation	2020-08-25 21:42:30	MapasCulturais\\Entities\\Agent	4
4650	4	createAgentRelationWithControl	2020-08-25 21:42:30	MapasCulturais\\Entities\\Agent	4
4651	4	removeAgentRelation	2020-08-25 21:42:30	MapasCulturais\\Entities\\Agent	4
4652	4	removeAgentRelationWithControl	2020-08-25 21:42:30	MapasCulturais\\Entities\\Agent	4
4653	4	createSealRelation	2020-08-25 21:42:30	MapasCulturais\\Entities\\Agent	4
4654	4	removeSealRelation	2020-08-25 21:42:30	MapasCulturais\\Entities\\Agent	4
4655	4	@control	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4656	4	view	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4657	4	create	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4658	4	modify	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4659	4	remove	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4660	4	viewPrivateFiles	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4661	4	changeOwner	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4662	4	viewPrivateData	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4663	4	createAgentRelation	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4664	4	createAgentRelationWithControl	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4665	4	removeAgentRelation	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4666	4	removeAgentRelationWithControl	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4667	4	createSealRelation	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
4668	4	removeSealRelation	2020-08-25 21:42:30	MapasCulturais\\Entities\\Space	1
5253	6	@control	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5254	6	create	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5255	6	view	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5256	6	modify	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5257	6	createSpaceRelation	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5258	6	removeSpaceRelation	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5259	6	viewPrivateData	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5260	6	remove	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5261	6	viewPrivateFiles	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5262	6	changeOwner	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5263	6	createAgentRelation	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5264	6	createAgentRelationWithControl	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5265	6	removeAgentRelation	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5266	6	removeAgentRelationWithControl	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5267	6	createSealRelation	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5268	6	removeSealRelation	2020-08-26 07:07:07	MapasCulturais\\Entities\\Registration	902053773
5345	7	@control	2020-08-26 07:16:48	MapasCulturais\\Entities\\Agent	41
5346	7	create	2020-08-26 07:16:48	MapasCulturais\\Entities\\Agent	41
5347	7	view	2020-08-26 07:16:48	MapasCulturais\\Entities\\Agent	41
5348	7	modify	2020-08-26 07:16:48	MapasCulturais\\Entities\\Agent	41
5349	7	viewPrivateFiles	2020-08-26 07:16:48	MapasCulturais\\Entities\\Agent	41
5350	7	viewPrivateData	2020-08-26 07:16:48	MapasCulturais\\Entities\\Agent	41
5351	7	createAgentRelation	2020-08-26 07:16:48	MapasCulturais\\Entities\\Agent	41
5352	7	createAgentRelationWithControl	2020-08-26 07:16:48	MapasCulturais\\Entities\\Agent	41
5353	7	removeAgentRelation	2020-08-26 07:16:48	MapasCulturais\\Entities\\Agent	41
5354	7	removeAgentRelationWithControl	2020-08-26 07:16:48	MapasCulturais\\Entities\\Agent	41
5355	7	createSealRelation	2020-08-26 07:16:48	MapasCulturais\\Entities\\Agent	41
5356	7	removeSealRelation	2020-08-26 07:16:48	MapasCulturais\\Entities\\Agent	41
5397	9	@control	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5398	9	create	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5399	9	view	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5400	9	modify	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5401	9	createSpaceRelation	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5137	2	@control	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5138	2	create	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5139	2	view	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5140	2	modify	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5141	2	createSpaceRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5142	2	removeSpaceRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5143	2	viewPrivateData	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5144	2	remove	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5145	2	viewPrivateFiles	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5146	2	changeOwner	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5147	2	createAgentRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5148	2	createAgentRelationWithControl	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5149	2	removeAgentRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5150	2	removeAgentRelationWithControl	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5151	2	createSealRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5152	2	removeSealRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	735327624
5153	2	@control	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5154	2	create	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5155	2	view	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5156	2	modify	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5157	2	createSpaceRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5158	2	removeSpaceRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5159	2	viewPrivateData	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5160	2	remove	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5161	2	viewPrivateFiles	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5162	2	changeOwner	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5402	9	removeSpaceRelation	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5403	9	viewPrivateData	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5404	9	remove	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5405	9	viewPrivateFiles	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5406	9	changeOwner	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5407	9	createAgentRelation	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5408	9	createAgentRelationWithControl	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5409	9	removeAgentRelation	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5410	9	removeAgentRelationWithControl	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5411	9	createSealRelation	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5412	9	removeSealRelation	2020-08-26 07:43:14	MapasCulturais\\Entities\\Registration	1750691250
5163	2	createAgentRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5164	2	createAgentRelationWithControl	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5165	2	removeAgentRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5166	2	removeAgentRelationWithControl	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5167	2	createSealRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5168	2	removeSealRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1926833684
5169	2	@control	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5170	2	create	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5171	2	view	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5172	2	modify	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5173	2	createSpaceRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5174	2	removeSpaceRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5175	2	viewPrivateData	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5176	2	remove	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5177	2	viewPrivateFiles	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5178	2	changeOwner	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5179	2	createAgentRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5180	2	createAgentRelationWithControl	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5181	2	removeAgentRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5182	2	removeAgentRelationWithControl	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5183	2	createSealRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5184	2	removeSealRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	971249312
5185	4	@control	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5186	4	create	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5187	4	view	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5188	4	modify	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5189	4	createSpaceRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5190	4	removeSpaceRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5191	4	viewPrivateData	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5192	4	remove	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5193	4	viewPrivateFiles	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5194	4	changeOwner	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5195	4	createAgentRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5196	4	createAgentRelationWithControl	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5197	4	removeAgentRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5198	4	removeAgentRelationWithControl	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5199	4	createSealRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5200	4	removeSealRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	1020199467
5201	3	@control	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5202	3	create	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5203	3	view	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5204	3	modify	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5205	3	createSpaceRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5206	3	removeSpaceRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5207	3	viewPrivateData	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5208	3	remove	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5209	3	viewPrivateFiles	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5210	3	changeOwner	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5211	3	createAgentRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5212	3	createAgentRelationWithControl	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5213	3	removeAgentRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5214	3	removeAgentRelationWithControl	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5215	3	createSealRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5216	3	removeSealRelation	2020-08-26 04:53:03	MapasCulturais\\Entities\\Registration	792482838
5317	7	@control	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5318	7	create	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5319	7	view	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5320	7	modify	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5321	7	createSpaceRelation	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5322	7	removeSpaceRelation	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5323	7	viewPrivateData	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5324	7	remove	2020-08-26 07:15:25	MapasCulturais\\Entities\\Registration	1715162904
5481	11	@control	2020-08-26 07:49:16	MapasCulturais\\Entities\\Agent	45
5482	11	create	2020-08-26 07:49:16	MapasCulturais\\Entities\\Agent	45
5483	11	view	2020-08-26 07:49:16	MapasCulturais\\Entities\\Agent	45
5484	11	modify	2020-08-26 07:49:16	MapasCulturais\\Entities\\Agent	45
5485	11	viewPrivateFiles	2020-08-26 07:49:16	MapasCulturais\\Entities\\Agent	45
5486	11	viewPrivateData	2020-08-26 07:49:16	MapasCulturais\\Entities\\Agent	45
5487	11	createAgentRelation	2020-08-26 07:49:16	MapasCulturais\\Entities\\Agent	45
5488	11	createAgentRelationWithControl	2020-08-26 07:49:16	MapasCulturais\\Entities\\Agent	45
5489	11	removeAgentRelation	2020-08-26 07:49:16	MapasCulturais\\Entities\\Agent	45
5490	11	removeAgentRelationWithControl	2020-08-26 07:49:16	MapasCulturais\\Entities\\Agent	45
5491	11	createSealRelation	2020-08-26 07:49:16	MapasCulturais\\Entities\\Agent	45
5492	11	removeSealRelation	2020-08-26 07:49:16	MapasCulturais\\Entities\\Agent	45
5493	12	@control	2020-08-27 13:26:00	MapasCulturais\\Entities\\Agent	46
5494	12	create	2020-08-27 13:26:00	MapasCulturais\\Entities\\Agent	46
5495	12	view	2020-08-27 13:26:00	MapasCulturais\\Entities\\Agent	46
5496	12	modify	2020-08-27 13:26:00	MapasCulturais\\Entities\\Agent	46
5497	12	viewPrivateFiles	2020-08-27 13:26:00	MapasCulturais\\Entities\\Agent	46
5498	12	viewPrivateData	2020-08-27 13:26:00	MapasCulturais\\Entities\\Agent	46
5499	12	createAgentRelation	2020-08-27 13:26:00	MapasCulturais\\Entities\\Agent	46
5500	12	createAgentRelationWithControl	2020-08-27 13:26:00	MapasCulturais\\Entities\\Agent	46
5501	12	removeAgentRelation	2020-08-27 13:26:00	MapasCulturais\\Entities\\Agent	46
5502	12	removeAgentRelationWithControl	2020-08-27 13:26:00	MapasCulturais\\Entities\\Agent	46
5503	12	createSealRelation	2020-08-27 13:26:00	MapasCulturais\\Entities\\Agent	46
5504	12	removeSealRelation	2020-08-27 13:26:00	MapasCulturais\\Entities\\Agent	46
5505	12	@control	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5506	12	create	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5507	12	view	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5508	12	modify	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5509	12	createSpaceRelation	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5510	12	removeSpaceRelation	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5511	12	viewPrivateData	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5512	12	remove	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5513	12	viewPrivateFiles	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5514	12	changeOwner	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5515	12	createAgentRelation	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5516	12	createAgentRelationWithControl	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5517	12	removeAgentRelation	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5518	12	removeAgentRelationWithControl	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5519	12	createSealRelation	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
5520	12	removeSealRelation	2020-08-27 13:26:00	MapasCulturais\\Entities\\Registration	1076435879
\.


--
-- Data for Name: permission_cache_pending; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.permission_cache_pending (id, object_id, object_type) FROM stdin;
\.


--
-- Data for Name: procuration; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.procuration (token, usr_id, attorney_user_id, action, create_timestamp, valid_until_timestamp) FROM stdin;
\.


--
-- Data for Name: project; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.project (id, name, short_description, long_description, create_timestamp, status, agent_id, is_verified, type, parent_id, registration_from, registration_to, update_timestamp, subsite_id) FROM stdin;
1	Lei Aldir Blanc	Grana fácil fácil	\N	2020-08-15 22:08:44	1	1	f	9	\N	\N	\N	\N	\N
\.


--
-- Data for Name: project_event; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.project_event (id, event_id, project_id, type, status) FROM stdin;
\.


--
-- Data for Name: project_meta; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.project_meta (object_id, key, value, id) FROM stdin;
\.


--
-- Data for Name: registration; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.registration (id, opportunity_id, category, agent_id, create_timestamp, sent_timestamp, status, agents_data, subsite_id, consolidated_result, number, valuers_exceptions_list, space_data) FROM stdin;
735327624	2	\N	2	2020-08-18 03:31:30	\N	0	[]	\N	0	on-735327624	{"include": [], "exclude": []}	{}
413170950	3	\N	44	2020-08-26 07:44:55	\N	0	[]	\N	0	on-413170950	{"include": [], "exclude": []}	{}
1926833684	2	\N	2	2020-08-17 19:58:01	\N	0	[]	\N	0	on-1926833684	{"include": [], "exclude": []}	{}
1689674626	3		1	2020-08-21 03:24:00	2020-08-21 06:48:29	1	{"owner":{"id":1,"name":"Rafa","nomeCompleto":"Rafael Chaves","documento":"050.913.009-70","dataDeNascimento":"2020-08-07","genero":"Homem Trans.","raca":"","location":{"latitude":"0","longitude":"0"},"endereco":null,"En_CEP":"01232-12","En_Nome_Logradouro":"","En_Num":"35","En_Complemento":"apto 91A","En_Bairro":"Bila Madalena","En_Municipio":"S\\u00e3o Paulo","En_Estado":null,"telefone1":"(11) 9332-2123","telefone2":"(11) 1234-1233","telefonePublico":null,"emailPrivado":"rafael@hacklab.com.br","emailPublico":null,"site":null,"googleplus":null,"facebook":null,"twitter":null}}	\N	0	on-1689674626	{"include": [], "exclude": []}	{}
971249312	2	\N	2	2020-08-15 22:20:53	\N	0	[]	\N	0	on-971249312	{"include": [], "exclude": []}	{}
1020199467	2	\N	4	2020-08-21 07:01:37	\N	0	[]	\N	0	on-1020199467	{"include": [], "exclude": []}	{}
1593864955	3		3	2020-08-21 06:51:16	\N	0	[]	\N	0	on-1593864955	{"include": [], "exclude": []}	{}
1066273876	3	\N	45	2020-08-26 07:47:49	\N	0	[]	\N	0	on-1066273876	{"include": [], "exclude": []}	{}
763896078	3		2	2020-08-21 20:09:04	\N	0	[]	\N	0	on-763896078	{"include": [], "exclude": []}	{}
792482838	2	\N	3	2020-08-20 23:28:25	\N	0	[]	\N	0	on-792482838	{"include": [], "exclude": []}	{}
1731020007	2	\N	4	2020-08-19 20:11:06	\N	0	[]	\N	0	on-1731020007	{"include": [], "exclude": []}	{}
1970483263	3	\N	39	2020-08-25 21:45:23	\N	0	[]	\N	0	on-1970483263	{"include": [], "exclude": []}	{}
1967657373	3		4	2020-08-21 18:38:17	\N	0	[]	\N	0	on-1967657373	{"include": [], "exclude": []}	{}
1076435879	3	\N	46	2020-08-27 13:25:54	\N	0	[]	\N	0	on-1076435879	{"include": [], "exclude": []}	{}
905535019	3	\N	42	2020-08-26 07:23:04	\N	0	[]	\N	0	on-905535019	{"include": [], "exclude": []}	{}
1750691250	3	\N	43	2020-08-26 07:43:01	\N	0	[]	\N	0	on-1750691250	{"include": [], "exclude": []}	{}
902053773	3	\N	40	2020-08-26 07:07:04	\N	0	[]	\N	0	on-902053773	{"include": [], "exclude": []}	{}
1715162904	3	\N	41	2020-08-26 07:15:24	\N	0	[]	\N	0	on-1715162904	{"include": [], "exclude": []}	{}
\.


--
-- Data for Name: registration_evaluation; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.registration_evaluation (id, registration_id, user_id, result, evaluation_data, status) FROM stdin;
\.


--
-- Data for Name: registration_field_configuration; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.registration_field_configuration (id, opportunity_id, title, description, categories, required, field_type, field_options, max_size, display_order, config) FROM stdin;
10	2	DATA DE NASCIMENTO:	Dia/Mês/Ano. Preencha o dia com dois dígitos, o mês com dois dígitos, e o ano com quatro dígitos.	a:0:{}	t	agent-owner-field	a:1:{i:0;s:0:"";}	0	7	a:1:{s:10:"agentField";s:16:"dataDeNascimento";}
12	2	TELEFONE 2 - FIXO OU CELULAR	Preencha os números do seu telefone para contato e DDD, sem o uso de ponto ou hífen.	a:0:{}	f	agent-owner-field	a:1:{i:0;s:0:"";}	0	9	a:1:{s:10:"agentField";s:9:"telefone2";}
26	2	MULHER PROVEDORA DE FAMÍLIA MONOPARENTAL:	Assinale se for mulher solo e chefe de família com, no mínimo, 01 (um/uma) dependente menor de 18 (dezoito) anos. Família monoparental com mulher provedora trata-se de um grupo familiar chefiado por mulher sem cônjuge ou companheiro, com pelo menos uma pessoa menor de dezoito anos de idade.	a:0:{}	t	select	a:2:{i:0;s:3:"SIM";i:1;s:4:"NÃO";}	0	22	\N
1	1	Dados Pessoais		a:0:{}	f	section	a:0:{}		1	\N
2	1	CPF	informe o CPF	a:0:{}	t	cpf	a:0:{}		2	\N
3	1	data de nascimento	asdasd	a:0:{}	f	date	a:0:{}		3	\N
4	1	Outra Seção	descrição da seção	a:0:{}	f	section	a:0:{}		4	\N
28	2	FUNÇÃO DE ATUAÇÃO CULTURAL:	Assinale sua função conforme atuação.\n**acrescentar campo na entidade agentes do padrão	a:0:{}	t	checkboxes	a:5:{i:0;s:47:"Artista, Artesão(ã), Brincante ou Criador(a).";i:1;s:28:"Consultor(a) ou Curador(a). ";i:2;s:25:"Produtor(a) ou Gestor(a).";i:3;s:12:"Técnico(a).";i:4;s:6:"Outros";}	0	25	\N
18	2	ENDEREÇO:	Preencha seu endereço completo. Para agentes culturais que sejam itinerantes, preencher com o endereço atual.	a:0:{}	t	textarea	a:0:{}	0	14	\N
11	2	TELEFONE 1 - FIXO OU CELULAR	Preencha os números do seu telefone para contato e DDD, sem o uso de ponto ou hífen.	a:0:{}	t	agent-owner-field	a:1:{i:0;s:0:"";}	0	8	a:1:{s:10:"agentField";s:9:"telefone1";}
19	2	COMPLEMENTO DE ENDEREÇO:	Preencha o complemento do seu endereço.\n**descrever melhor esse capo segunda a solução que seja definida pelo sistema.	a:0:{}	f	text	a:0:{}	0	15	\N
20	2	BAIRRO:	Preencha o bairro do seu endereço.	a:0:{}	t	textarea	a:0:{}	0	16	\N
5	2	Dados Cadastrais Usuais		a:0:{}	f	section	a:0:{}	0	2	\N
24	2	RAÇA/COR:	Assinale como se autodeclara em raça/cor.	a:0:{}	t	agent-owner-field	a:6:{s:0:"";s:13:"Não Informar";s:6:"Branca";s:6:"Branca";s:5:"Preta";s:5:"Preta";s:7:"Amarela";s:7:"Amarela";s:5:"Parda";s:5:"Parda";s:9:"Indígena";s:9:"Indígena";}	0	20	a:1:{s:10:"agentField";s:4:"raca";}
227	2	email TESTE		a:0:{}	t	email	a:0:{}	0	1	a:0:{}
15	2	SE SIM no campo anterior NÚMERO DO CPF DOS RESIDENTES:	Informe o número do CPF ou número de série da Certidão de Nascimento, e selecione o grau de parentesco das pessoas que moram com você. Preencha apenas os números, sem o uso de ponto ou hífen, separando com barra se for mais de um CPF.  ***A resolver com uma solução em campos de preenchimento que agregue o nível de parentesco para quem não tem CPF****	a:0:{}	f	cpf	a:0:{}	0	23	\N
27	2	SEGMENTOS CULTURAIS DE ATUAÇÃO PRINCIPAL:	Assinale os segmentos culturais em que prioritariamente atua.	a:0:{}	t	checkboxes	a:16:{i:0;s:23:"Patrimônio Cultural.  ";i:1;s:16:"Artes Circenses.";i:2;s:16:"Artes da Dança.";i:3;s:16:"Artes do Teatro.";i:4;s:14:"Artes Visuais.";i:5;s:11:"Artesanato.";i:6;s:12:"Audiovisual.";i:7;s:16:"Cultura Popular.";i:8;s:7:"Design.";i:9;s:11:"Fotografia.";i:10;s:12:"Gastronomia.";i:11;s:11:"Literatura.";i:12;s:5:"Moda.";i:13;s:8:"Música.";i:14;s:7:"Ópera.";i:15;s:24:"Outro segmento cultural.";}	0	24	\N
23	2	COMUNIDADE TRADICIONAL:	Assinale se pertence a alguma comunidade tradicional ou não.	a:0:{}	t	select	a:9:{i:0;s:11:"Indígenas.";i:1;s:12:"Quilombolas.";i:2;s:12:"Ciganos(as).";i:3;s:24:"Comunidades Ribeirinhas.";i:4;s:19:"Comunidades Rurais.";i:5;s:26:"Pescadores(as) Artesanais.";i:6;s:18:"Povos de Terreiro.";i:7;s:29:"Outra comunidade tradicional.";i:8;s:39:"Não pertenço a comunidade tradicional";}	0	19	\N
9	2	NOME DA MÃE:	Coloque o nome da sua mãe conforme consta no RG ou em outro documento oficial de identificação. Ou informar como “não consta no documento de identificação”.	a:0:{}	t	text	a:0:{}	0	6	\N
25	2	PESSOA COM DEFICIÊNCIA:	Assinale conforme sua deficiência ou se não é deficiente.	a:0:{}	t	select	a:6:{i:0;s:8:"Física.";i:1;s:9:"Auditiva.";i:2;s:7:"Visual.";i:3;s:12:"Intelectual.";i:4;s:10:"Múltipla.";i:5;s:20:"Não sou deficiente.";}	0	21	\N
13	2	E-MAIL:	Preencha o seu endereço eletrônico.	a:0:{}	f	agent-owner-field	a:1:{i:0;s:0:"";}	0	10	a:1:{s:10:"agentField";s:12:"emailPrivado";}
7	2	NOME COMPLETO:	Coloque seu nome conforme consta no CPF ou em outro documento oficial de identificação.	a:0:{}	t	agent-owner-field	a:1:{i:0;s:0:"";}	0	4	a:1:{s:10:"agentField";s:16:"shortDescription";}
8	2	NOME SOCIAL	Caso queira ser identificado(a) pelo nome social, preencha esse campo. Nome social é o nome pelo qual pessoas, de qualquer gênero, preferem ser chamados(as) cotidianamente - em contraste com o nome oficialmente registrado.	a:0:{}	f	agent-owner-field	a:1:{i:0;s:0:"";}	0	5	a:1:{s:10:"agentField";s:12:"nomeCompleto";}
16	2	Outros	**referente à naturalidade | da implentação de campo com opção outros	a:0:{}	f	textarea	a:0:{}	0	12	\N
21	2	MUNICíPIO:	Selecione o seu munícipio.	a:0:{}	t	select	a:184:{i:0;s:7:"ABAIARA";i:1;s:7:"ACARAPE";i:2;s:7:"ACARAÚ";i:3;s:8:"ACOPIARA";i:4;s:6:"AIUABA";i:5;s:11:"ALCÂNTARAS";i:6;s:9:"ALTANEIRA";i:7;s:10:"ALTO SANTO";i:8;s:8:"AMONTADA";i:9;s:17:"ANTONINA DO NORTE";i:10;s:9:"APUIARÉS";i:11;s:7:"AQUIRAZ";i:12;s:7:"ARACATI";i:13;s:9:"ARACOIABA";i:14;s:9:"ARARENDÁ";i:15;s:7:"ARARIPE";i:16;s:7:"ARATUBA";i:17;s:8:"ARNEIROZ";i:18;s:7:"ASSARÉ";i:19;s:6:"AURORA";i:20;s:6:"BAIXIO";i:21;s:9:"BANABUIÚ";i:22;s:8:"BARBALHA";i:23;s:8:"BARREIRA";i:24;s:5:"BARRO";i:25;s:11:"BARROQUINHA";i:26;s:9:"BATURITÉ";i:27;s:8:"BEBERIBE";i:28;s:9:"BELA CRUZ";i:29;s:10:"BOA VIAGEM";i:30;s:11:"BREJO SANTO";i:31;s:7:"CAMOCIM";i:32;s:12:"CAMPOS SALES";i:33;s:8:"CANINDÉ";i:34;s:10:"CAPISTRANO";i:35;s:8:"CARIDADE";i:36;s:7:"CARIRÉ";i:37;s:10:"CARIRIAÇU";i:38;s:7:"CARIÚS";i:39;s:9:"CARNAUBAL";i:40;s:8:"CASCAVEL";i:41;s:8:"CATARINA";i:42;s:7:"CATUNDA";i:43;s:7:"CAUCAIA";i:44;s:5:"CEDRO";i:45;s:6:"CHAVAL";i:46;s:6:"CHORÓ";i:47;s:10:"CHOROZINHO";i:48;s:7:"COREAÚ";i:49;s:8:"CRATEÚS";i:50;s:5:"CRATO";i:51;s:7:"CROATÁ";i:52;s:4:"CRUZ";i:53;s:21:"DEP. IRAPUAN PINHEIRO";i:54;s:6:"ERERÊ";i:55;s:8:"EUSÉBIO";i:56;s:12:"FARIAS BRITO";i:57;s:9:"FORQUILHA";i:58;s:9:"FORTALEZA";i:59;s:6:"FORTIM";i:60;s:12:"FRECHEIRINHA";i:61;s:15:"GENERAL SAMPAIO";i:62;s:6:"GRAÇA";i:63;s:6:"GRANJA";i:64;s:9:"GRANJEIRO";i:65;s:9:"GROAÍRAS";i:66;s:8:"GUAIÚBA";i:67;s:19:"GUARACIABA DO NORTE";i:68;s:12:"GUARAMIRANGA";i:69;s:12:"HIDROLÂNDIA";i:70;s:9:"HORIZONTE";i:71;s:9:"IBARETAMA";i:72;s:8:"IBIAPINA";i:73;s:11:"IBICUITINGA";i:74;s:7:"ICAPUÍ";i:75;s:3:"ICO";i:76;s:6:"IGUATU";i:77;s:14:"INDEPENDÊNCIA";i:78;s:10:"IPAPORANGA";i:79;s:9:"IPAUMIRIM";i:80;s:3:"IPU";i:81;s:8:"IPUEIRAS";i:82;s:7:"IRACEMA";i:83;s:9:"IRAUÇUBA";i:84;s:9:"ITAIÇABA";i:85;s:9:"ITAITINGA";i:86;s:8:"ITAPAJÉ";i:87;s:9:"ITAPIPOCA";i:88;s:9:"ITAPIÚNA";i:89;s:7:"ITAREMA";i:90;s:7:"ITATIRA";i:91;s:11:"JAGUARETAMA";i:92;s:11:"JAGUARIBARA";i:93;s:9:"JAGUARIBE";i:94;s:10:"JAGUARUANA";i:95;s:6:"JARDIM";i:96;s:5:"JATÍ";i:97;s:22:"JIJOCA DE JERICOACOARA";i:98;s:17:"JUAZEIRO DO NORTE";i:99;s:6:"JUCÁS";i:100;s:20:"LAVRAS DA MANGABEIRA";i:101;s:17:"LIMOEIRO DO NORTE";i:102;s:8:"MADALENA";i:103;s:10:"MARACANAÚ";i:104;s:10:"MARANGUAPE";i:105;s:5:"MARCO";i:106;s:12:"MARTINÓPOLE";i:107;s:8:"MASSAPÊ";i:108;s:7:"MAURITI";i:109;s:7:"MERUOCA";i:110;s:8:"MILAGRES";i:111;s:6:"MILHÃ";i:112;s:8:"MIRAÍMA";i:113;s:13:"MISSÃO VELHA";i:114;s:8:"MOMBAÇA";i:115;s:16:"MONSENHOR TABOSA";i:116;s:11:"MORADA NOVA";i:117;s:8:"MORAÚJO";i:118;s:9:"MORRINHOS";i:119;s:7:"MUCAMBO";i:120;s:7:"MULUNGU";i:121;s:11:"NOVA OLINDA";i:122;s:11:"NOVA RUSSAS";i:123;s:12:"NOVO ORIENTE";i:124;s:5:"OCARA";i:125;s:5:"ORÓS";i:126;s:7:"PACAJUS";i:127;s:8:"PACATUBA";i:128;s:6:"PACOTI";i:129;s:7:"PACUJÁ";i:130;s:7:"PALHANO";i:131;s:9:"PALMÁCIA";i:132;s:8:"PARACURU";i:133;s:9:"PARAIPABA";i:134;s:7:"PARAMBU";i:135;s:8:"PARAMOTI";i:136;s:12:"PEDRA BRANCA";i:137;s:9:"PENAFORTE";i:138;s:10:"PENTECOSTE";i:139;s:7:"PEREIRO";i:140;s:11:"PINDORETAMA";i:141;s:15:"PIQUET CARNEIRO";i:142;s:14:"PIRES FERREIRA";i:143;s:7:"PORANGA";i:144;s:9:"PORTEIRAS";i:145;s:7:"POTENGI";i:146;s:10:"POTIRETAMA";i:147;s:16:"QUITERIANÓPOLIS";i:148;s:8:"QUIXADÁ";i:149;s:8:"QUIXELÔ";i:150;s:12:"QUIXERAMOBIM";i:151;s:8:"QUIXERÉ";i:152;s:10:"REDENÇÃO";i:153;s:9:"RERIUTABA";i:154;s:6:"RUSSAS";i:155;s:8:"SABOEIRO";i:156;s:7:"SALITRE";i:157;s:18:"SANTANA DO ACARAÚ";i:158;s:14:"SANTA QUITERIA";i:159;s:17:"SANTANA DO CARIRI";i:160;s:13:"SÃO BENEDITO";i:161;s:25:"SÃO GONÇALO DO AMARANTE";i:162;s:23:"SÃO JOÃO DO JAGUARIBE";i:163;s:18:"SÃO LUÍS DO CURU";i:164;s:14:"SENADOR POMPEU";i:165;s:11:"SENADOR SÁ";i:166;s:6:"SOBRAL";i:167;s:11:"SOLONÓPOLE";i:168;s:18:"TABULEIRO DO NORTE";i:169;s:8:"TAMBORIL";i:170;s:8:"TARRAFAS";i:171;s:5:"TAUÁ";i:172;s:10:"TEJUÇUOCA";i:173;s:8:"TIANGUÁ";i:174;s:6:"TRAIRI";i:175;s:6:"TURURU";i:176;s:7:"UBAJARA";i:177;s:5:"UMARI";i:178;s:6:"UMIRIM";i:179;s:11:"URUBURETAMA";i:180;s:6:"URUOCA";i:181;s:7:"VARJOTA";i:182;s:14:"VÁRZEA ALEGRE";i:183;s:17:"VIÇOSA DO CEARÁ";}	0	17	\N
17	2	CEP:	Preencha apenas os números, sem o uso de ponto ou hífen. Para agentes culturais que sejam itinerantes, preencher o CEP do endereço atual.\n\n**preenchimento automático?	a:0:{}	t	number	a:0:{}	0	13	\N
6	2	NÚMERO DO CPF:	Preencha apenas os números, sem o uso de ponto ou hífen.	a:0:{}	t	agent-owner-field	a:1:{i:0;s:0:"";}	0	3	a:1:{s:10:"agentField";s:9:"documento";}
22	2	GÊNERO:	Selecione conforme sua identidade de gênero. Para mais informações acerca de gênero e sua diversidade, clique aqui. http://www.cultura.pe.gov.br/wp-content/uploads/2020/07/GA%CC%83%C2%AAnero-e-sua-diversidade-_-MAPA-CULTURAL-DE-PERNAMBUCO.pdf	a:0:{}	t	agent-owner-field	a:8:{s:0:"";s:13:"Não Informar";s:17:"Mulher Transexual";s:17:"Mulher Transexual";s:6:"Mulher";s:6:"Mulher";s:16:"Homem Transexual";s:16:"Homem Transexual";s:5:"Homem";s:5:"Homem";s:13:"Não Binário";s:13:"Não Binário";s:8:"Travesti";s:8:"Travesti";s:6:"Outras";s:6:"Outras";}	0	18	a:1:{s:10:"agentField";s:6:"genero";}
29	2	BREVE HISTÓRICO DE ATUAÇÃO:	*** reconhecimento de link? desdobrar campo?\nEscreva de forma resumida seu histórico na área da cultura e as funções que desempenha, além de suas principais experiências. Em caso de relato oral, insira links com o breve histórico de atuação, preferencialmente do Youtube ou Vimeo (se privado, deve disponibilizar a chave de acesso).	a:0:{}	t	textarea	a:0:{}	500	26	\N
30	2	***Multiplos links - COMPROVAÇÕES	(Insira links, preferencialmente do Youtube ou Vimeo, ou de sites de portfólio, para demonstrar suas experiências, obras e afins. Ou ainda, anexe o relato oral do seu breve histórico de atuação. Se privado, deve disponibilizar a chave de acesso.)	a:0:{}	f	url	a:0:{}	0	27	\N
31	2	SITUAÇÃO DE TRABALHO	Assinale conforme sua situação de trabalho.\nCONFORME INCISO II DO ART. 6º DA LEI.	a:0:{}	t	select	a:5:{i:0;s:63:"Trabalho, estou empregado(a) com carteira de trabalho assinada.";i:1;s:55:"Trabalho, mas não tenho carteira de trabalho assinada.";i:2;s:95:"Trabalho por conta própria, não tenho carteira de trabalho assinada nem outra formalização.";i:3;s:64:"Já trabalhei com carteira assinada, mas não estou trabalhando.";i:4;s:16:"Nunca trabalhei.";}	0	28	\N
40	2	DECLARAÇÕES	CONFORME EXIGÊNCIAS DO ART. 6º DA LEI.	a:0:{}	f	section	a:0:{}	0	36	\N
32	2	DADOS DA CONTA BANCÁRIA		a:0:{}	f	section	a:0:{}	0	29	\N
33	2	TIPO DE CONTA BANCÁRIA	Assinale o tipo de conta bancária.	a:0:{}	t	select	a:3:{i:0;s:15:"Conta corrente.";i:1;s:16:"Conta poupança.";i:2;s:28:"Não possui conta bancária.";}	0	30	\N
34	2	BANCO:	Selecione o nome do seu Banco.	a:0:{}	t	select	a:8:{i:0;s:15:"Banco do Brasil";i:1;s:8:"Banestes";i:2;s:8:"Banrisul";i:3;s:8:"Citibank";i:4;s:4:"HSBC";i:5;s:9:"Santander";i:6;s:6:"Sicoob";i:7;s:7:"Sicredi";}	0	31	\N
35	2	Número de agência:		a:0:{}	t	number	a:0:{}	0	32	\N
36	2	Número de conta:		a:0:{}	t	number	a:0:{}	0	33	\N
37	2	Número de operação (se houver):		a:0:{}	f	text	a:0:{}	0	34	\N
38	2	INFORMAÇÕES COMPLEMENTARES:	Descreva mais informações, caso julgue necessário.\n**Referente a todo formulário ou aos dados bancearios	a:0:{}	f	textarea	a:0:{}	0	35	\N
39	2	DECLARO ATUAÇÃO NO SETOR CULTURAL E FONTE DE RENDA, CONFORME LEI Nº 14.017, DE 29 DE JUNHO DE 2020, QUE DISPÕE SOBRE AÇÕES EMERGENCIAIS DESTINADAS AO SETOR CULTURAL A SEREM ADOTADAS DURANTE O ESTADO DE CALAMIDADE PÚBLICA.		a:0:{}	t	checkbox	a:0:{}	0	37	s:0:"";
41	2	DECLARO QUE ATUO SOCIAL OU PROFISSIONALMENTE NAS ÁREAS ARTÍSTICA E CULTURAL NOS 24 (VINTE E QUATRO) MESES IMEDIATAMENTE ANTERIORES À 29 DE JUNHO DE 2020, CONFORME INCISO I DO ART. 6º DA LEI Nº 14.017.		a:0:{}	t	checkbox	a:0:{}	0	38	s:0:"";
42	2	DECLARO QUE NÃO SOU TITULAR DE BENEFÍCIO PREVIDENCIÁRIO OU ASSISTENCIAL DO GOVERNO FEDERAL, EXCETO DO PROGRAMA BOLSA FAMÍLIA, CONFORME INCISO III DO ART. 6º DA LEI Nº 14.017.		a:0:{}	t	select	a:2:{i:0;s:3:"SIM";i:1;s:4:"NÃO";}	0	39	\N
43	2	DECLARO QUE NÃO ESTOU RECEBENDO BENEFÍCIO DO SEGURO DESEMPREGO OU PROGRAMA DE TRANSFERÊNCIA DE RENDA FEDERAL, CONFORME INCISO III DO ART. 6º DA LEI Nº 14.017.		a:0:{}	t	select	a:2:{i:0;s:3:"SIM";i:1;s:4:"NÃO";}	0	40	\N
44	2	DECLARO RENDA FAMILIAR PER CAPITA DE ATÉ MEIO SALÁRIO MÍNIMO OU RENDA FAMILIAR TOTAL DE ATÉ TRÊS SALÁRIOS MÍNIMOS, CONFORME INCISO IV DO ART. 6º DA LEI Nº 14.017.		a:0:{}	t	select	a:2:{i:0;s:3:"SIM";i:1;s:4:"NÃO";}	0	41	\N
45	2	DECLARO QUE OBTIVE RENDIMENTO MÉDIO DE  01/01/2019 A 29/02/2020 DE ATÉ 2 (DOIS) SALÁRIOS MÍNIMOS, CONFORME INCISO IV DO ART. 6º DA LEI Nº 14.017.		a:0:{}	t	select	a:2:{i:0;s:3:"SIM";i:1;s:4:"NÃO";}	0	42	\N
46	2	DECLARO QUE NO ANO DE 2018, NÃO RECEBI RENDIMENTOS ACIMA DE R$ 28.559,70 (VINTE E OITO MIL, QUINHENTOS E CINQUENTA E NOVE REAIS E SETENTA CENTAVOS), CONFORME INCISO V DO ART. 6º DA LEI Nº 14.017.		a:0:{}	t	select	a:2:{i:0;s:3:"SIM";i:1;s:4:"NÃO";}	0	43	\N
47	2	DECLARO NÃO SER BENEFICIÁRIO(A) DO AUXÍLIO EMERGENCIAL PREVISTO NA LEI Nº 13.982, DE 2 DE ABRIL DE 2020, E EM CONFORMIDADE COM O INCISO VII DO ART. 6º DA LEI Nº 14.017.		a:0:{}	t	select	a:2:{i:0;s:3:"SIM";i:1;s:4:"NÃO";}	0	44	\N
14	2	NATURALIDADE OU NACIONALIDADE:	Coloque o nome do Estado brasileiro que você nasceu e que consta no RG ou em outro documento oficial de identificação. Caso estrangeiro(a) não naturalizado(a) brasileiro(a), indique o país que você nasceu.	a:0:{}	t	select	a:28:{i:0;s:9:"Acre (AC)";i:1;s:12:"Alagoas (AL)";i:2;s:11:"Amapá (AP)";i:3;s:13:"Amazonas (AM)";i:4;s:10:"Bahia (BA)";i:5;s:11:"Ceará (CE)";i:6;s:21:"Distrito Federal (DF)";i:7;s:20:"Espírito Santo (ES)";i:8;s:11:"Goiás (GO)";i:9;s:14:"Maranhão (MA)";i:10;s:16:"Mato Grosso (MT)";i:11;s:23:"Mato Grosso do Sul (MS)";i:12;s:17:"Minas Gerais (MG)";i:13;s:10:"Pará (PA)";i:14;s:13:"Paraíba (PB)";i:15;s:12:"Paraná (PR)";i:16;s:15:"Pernambuco (PE)";i:17;s:11:"Piauí (PI)";i:18;s:19:"Rio de Janeiro (RJ)";i:19;s:24:"Rio Grande do Norte (RN)";i:20;s:22:"Rio Grande do Sul (RS)";i:21;s:14:"Rondônia (RO)";i:22;s:12:"Roraima (RR)";i:23;s:19:"Santa Catarina (SC)";i:24;s:15:"São Paulo (SP)";i:25;s:12:"Sergipe (SE)";i:26;s:14:"Tocantins (TO)";i:27;s:15:"Outros: Qual?**";}	0	11	\N
201	3	TELEFONE 1 - FIXO OU CELULAR	Preencha os números do seu telefone para contato e DDD, sem o uso de ponto ou hífen.	a:0:{}	t	agent-owner-field	a:1:{i:0;s:0:"";}	0	7	a:1:{s:11:"entityField";s:9:"telefone1";}
202	3	NOME COMPLETO:	Coloque seu nome conforme consta no CPF ou em outro documento oficial de identificação.	a:0:{}	t	agent-owner-field	a:1:{i:0;s:0:"";}	0	3	a:1:{s:11:"entityField";s:12:"nomeCompleto";}
226	3	ENDEREÇO	Preencha seu endereço completo. Para agentes culturais que sejam itinerantes, preencher com o endereço atual.	a:0:{}	t	agent-owner-field	a:1:{i:0;s:0:"";}	0	11	a:1:{s:11:"entityField";s:9:"@location";}
197	3	Dados Cadastrais Usuais		a:0:{}	f	section	a:0:{}	0	1	a:0:{}
198	3	NÚMERO DO CPF:	Preencha apenas os números, sem o uso de ponto ou hífen.	a:0:{}	t	agent-owner-field	a:1:{i:0;s:0:"";}	0	2	a:1:{s:11:"entityField";s:9:"documento";}
199	3	NOME SOCIAL	Caso queira ser identificado(a) pelo nome social, preencha esse campo. Nome social é o nome pelo qual pessoas, de qualquer gênero, preferem ser chamados(as) cotidianamente - em contraste com o nome oficialmente registrado.	a:0:{}	t	agent-owner-field	a:1:{i:0;s:0:"";}	0	4	a:1:{s:11:"entityField";s:4:"name";}
200	3	NOME DA MÃE:	Coloque o nome da sua mãe conforme consta no RG ou em outro documento oficial de identificação. Ou informar como “não consta no documento de identificação”.	a:0:{}	t	text	a:0:{}	0	5	a:1:{i:0;s:0:"";}
203	3	SEGMENTOS CULTURAIS DE ATUAÇÃO PRINCIPAL:	Assinale os segmentos culturais em que prioritariamente atua.	a:0:{}	t	checkboxes	a:16:{i:0;s:23:"Patrimônio Cultural.  ";i:1;s:16:"Artes Circenses.";i:2;s:16:"Artes da Dança.";i:3;s:16:"Artes do Teatro.";i:4;s:14:"Artes Visuais.";i:5;s:11:"Artesanato.";i:6;s:12:"Audiovisual.";i:7;s:16:"Cultura Popular.";i:8;s:7:"Design.";i:9;s:11:"Fotografia.";i:10;s:12:"Gastronomia.";i:11;s:11:"Literatura.";i:12;s:5:"Moda.";i:13;s:8:"Música.";i:14;s:7:"Ópera.";i:15;s:24:"Outro segmento cultural.";}	0	19	a:1:{i:0;s:0:"";}
204	3	FUNÇÃO DE ATUAÇÃO CULTURAL:	Assinale sua função conforme atuação.\n**acrescentar campo na entidade agentes do padrão	a:0:{}	t	checkboxes	a:5:{i:0;s:47:"Artista, Artesão(ã), Brincante ou Criador(a).";i:1;s:28:"Consultor(a) ou Curador(a). ";i:2;s:25:"Produtor(a) ou Gestor(a).";i:3;s:12:"Técnico(a).";i:4;s:6:"Outros";}	0	20	a:1:{i:0;s:0:"";}
205	3	BREVE HISTÓRICO DE ATUAÇÃO:	Escreva de forma resumida seu histórico na área da cultura e as funções que desempenha, além de suas principais experiências. Em caso de relato oral, insira links com o breve histórico de atuação, preferencialmente do Youtube ou Vimeo (se privado, deve disponibilizar a chave de acesso).	a:0:{}	t	textarea	a:0:{}	300	21	a:1:{i:0;s:0:"";}
206	3	RAÇA/COR:	Assinale como se autodeclara em raça/cor.	a:0:{}	t	agent-owner-field	a:6:{s:0:"";s:13:"Não Informar";s:6:"Branca";s:6:"Branca";s:5:"Preta";s:5:"Preta";s:7:"Amarela";s:7:"Amarela";s:5:"Parda";s:5:"Parda";s:9:"Indígena";s:9:"Indígena";}	0	14	a:1:{s:11:"entityField";s:4:"raca";}
207	3	COMUNIDADE TRADICIONAL:	Assinale se pertence a alguma comunidade tradicional ou não.	a:0:{}	t	select	a:9:{i:0;s:11:"Indígenas.";i:1;s:12:"Quilombolas.";i:2;s:12:"Ciganos(as).";i:3;s:24:"Comunidades Ribeirinhas.";i:4;s:19:"Comunidades Rurais.";i:5;s:26:"Pescadores(as) Artesanais.";i:6;s:18:"Povos de Terreiro.";i:7;s:29:"Outra comunidade tradicional.";i:8;s:39:"Não pertenço a comunidade tradicional";}	0	13	a:1:{i:0;s:0:"";}
208	3	DATA DE NASCIMENTO:	Dia/Mês/Ano. Preencha o dia com dois dígitos, o mês com dois dígitos, e o ano com quatro dígitos.	a:0:{}	t	agent-owner-field	a:1:{i:0;s:0:"";}	0	6	a:1:{s:11:"entityField";s:16:"dataDeNascimento";}
209	3	TELEFONE 2 - FIXO OU CELULAR	Preencha os números do seu telefone para contato e DDD, sem o uso de ponto ou hífen.	a:0:{}	f	agent-owner-field	a:1:{i:0;s:0:"";}	0	8	a:1:{s:11:"entityField";s:9:"telefone2";}
210	3	E-MAIL:	Preencha o seu endereço eletrônico.	a:0:{}	f	agent-owner-field	a:1:{i:0;s:0:"";}	0	9	a:1:{s:11:"entityField";s:12:"emailPrivado";}
211	3	***IF INFORME O CPF DO OUTRO MEMBRO	Caso tenho selecionado sim na opção anterior especifique o CPF do outro membro da mesma unidade familiar que recebe a renda emergencial	a:0:{}	f	cpf	a:0:{}	0	17	a:1:{i:0;s:0:"";}
212	3	PESSOA COM DEFICIÊNCIA:	Assinale conforme sua deficiência ou se não é deficiente.	a:0:{}	t	select	a:6:{i:0;s:8:"Física.";i:1;s:9:"Auditiva.";i:2;s:7:"Visual.";i:3;s:12:"Intelectual.";i:4;s:10:"Múltipla.";i:5;s:20:"Não sou deficiente.";}	0	15	a:0:{}
213	3	DOIS MEMBROS DA MESMA UNIDADE FAMILIAR?	Existe um outro membro da mesma unidade familiar que recebe a renda emergencial?	a:0:{}	t	select	a:2:{i:0;s:3:"SIM";i:1;s:4:"NÃO";}	0	16	a:1:{i:0;s:0:"";}
214	3	Número de agência:		a:0:{}	t	number	a:0:{}	0	27	a:0:{}
215	3	Número de conta:		a:0:{}	t	number	a:0:{}	0	28	a:0:{}
216	3	Número de operação (se houver):		a:0:{}	f	text	a:0:{}	0	29	a:0:{}
217	3	DADOS DA CONTA BANCÁRIA		a:0:{}	f	section	a:0:{}	0	24	a:0:{}
218	3	TIPO DE CONTA BANCÁRIA	Assinale o tipo de conta bancária.	a:0:{}	t	select	a:3:{i:0;s:15:"Conta corrente.";i:1;s:16:"Conta poupança.";i:2;s:28:"Não possui conta bancária.";}	0	25	a:0:{}
219	3	BANCO:	Selecione o nome do seu Banco.	a:0:{}	t	select	a:8:{i:0;s:15:"Banco do Brasil";i:1;s:8:"Banestes";i:2;s:8:"Banrisul";i:3;s:8:"Citibank";i:4;s:4:"HSBC";i:5;s:9:"Santander";i:6;s:6:"Sicoob";i:7;s:7:"Sicredi";}	0	26	a:0:{}
220	3	INFORMAÇÕES COMPLEMENTARES:	Descreva mais informações, caso julgue necessário.\n**Referente a todo formulário ou aos dados bancearios	a:0:{}	f	textarea	a:0:{}	0	30	a:0:{}
221	3	texto		a:0:{}	f	checkbox	a:0:{}	0	46	a:1:{s:11:"entityField";s:9:"@location";}
222	3	GÊNERO:	Selecione conforme sua identidade de gênero.\n\nMulher Cis.\nWisard/hint de Mulher Cis: Identidade de gênero coincide com sexo atribuído no nascimento.\nHomem Cis.\nWisard/hint de Homem Cis: Identidade de gênero coincide com sexo atribuído no nascimento.\nMulher Trans/Travesti.\nWisard/hint de Mulher Trans/Travesti: Identidade de gênero difere em diversos graus do sexo\natribuído no nascimento.\nHomem Trans.\nWisard/hint de Homem Trans: Identidade de gênero difere em diversos graus do sexo atribuído\nno nascimento.\nNão-Binárie/Outra variabilidade.\nWisard/hint de Não-Binárie/Outra variabilidade: Espectro de identidade contrário ao masculino ou feminino fundamentado no sexo atribuído no nascimento. Incluem-se nesse item outras variabilidades de gênero, a exemplo de queer/questionando, intersexo, agênero, andrógine, fluido, e mais.\nNão declarada.	a:0:{}	t	agent-owner-field	a:8:{s:0:"";s:13:"Não Informar";s:17:"Mulher Transexual";s:17:"Mulher Transexual";s:6:"Mulher";s:6:"Mulher";s:16:"Homem Transexual";s:16:"Homem Transexual";s:5:"Homem";s:5:"Homem";s:13:"Não Binário";s:13:"Não Binário";s:8:"Travesti";s:8:"Travesti";s:6:"Outras";s:6:"Outras";}	0	12	a:1:{s:11:"entityField";s:6:"genero";}
223	3	MULHER PROVEDORA DE FAMÍLIA MONOPARENTAL:	Assinale se for mulher solo e chefe de família com, no mínimo, 01 (um/uma) dependente menor de 18 (dezoito) anos. Família monoparental com mulher provedora trata-se de um grupo familiar chefiado por mulher sem cônjuge ou companheiro(a), com pelo menos uma pessoa menor de dezoito anos de idade.	a:0:{}	t	select	a:2:{i:0;s:3:"SIM";i:1;s:4:"NÃO";}	0	18	a:0:{}
224	3	***Multiplos links - COMPROVAÇÕES	(Insira links, preferencialmente do Youtube ou Vimeo, ou de sites de portfólio, para demonstrar suas experiências, obras e afins. Ou ainda, anexe o relato oral do seu breve histórico de atuação. Se privado, deve disponibilizar a chave de acesso.)	a:0:{}	f	url	a:0:{}	0	22	a:0:{}
225	3	ORIGEM:	Selecione o Estado brasileiro que você nasceu e que consta no RG ou em outro documento oficial de identificação, ou ainda se é estrangeiro(a) não naturalizado(a) brasileiro(a).	a:0:{}	t	select	a:28:{i:0;s:9:"Acre (AC)";i:1;s:12:"Alagoas (AL)";i:2;s:11:"Amapá (AP)";i:3;s:13:"Amazonas (AM)";i:4;s:10:"Bahia (BA)";i:5;s:11:"Ceará (CE)";i:6;s:21:"Distrito Federal (DF)";i:7;s:20:"Espírito Santo (ES)";i:8;s:11:"Goiás (GO)";i:9;s:14:"Maranhão (MA)";i:10;s:16:"Mato Grosso (MT)";i:11;s:23:"Mato Grosso do Sul (MS)";i:12;s:17:"Minas Gerais (MG)";i:13;s:10:"Pará (PA)";i:14;s:13:"Paraíba (PB)";i:15;s:12:"Paraná (PR)";i:16;s:15:"Pernambuco (PE)";i:17;s:11:"Piauí (PI)";i:18;s:19:"Rio de Janeiro (RJ)";i:19;s:24:"Rio Grande do Norte (RN)";i:20;s:22:"Rio Grande do Sul (RS)";i:21;s:14:"Rondônia (RO)";i:22;s:12:"Roraima (RR)";i:23;s:19:"Santa Catarina (SC)";i:24;s:15:"São Paulo (SP)";i:25;s:12:"Sergipe (SE)";i:26;s:14:"Tocantins (TO)";i:27;s:50:"Estrangeiro(a) não naturalizado(a) brasileiro(a).";}	0	10	a:1:{i:0;s:0:"";}
\.


--
-- Data for Name: registration_file_configuration; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.registration_file_configuration (id, opportunity_id, title, description, required, categories, display_order) FROM stdin;
5	3	AUTODECLARAÇÃO DE ATUAÇÃO NAS ÁREAS ARTÍSTICAS E CULTURAL	Envie o documento de autodeclaração preenchido com os dados do requerente e atividades realizadas. O documento deve estar assinado e ser enviado preferencialmente no formato pdf. Trata-se do Anexo II (http://www.planalto.gov.br/ccivil_03/_Ato2019-2022/2020/Decreto/Anexo/ANDEC10464-ANEXOII.pdf) do Decreto 10.464, de 17 de agosto de 2020.	t	a:0:{}	23
\.


--
-- Data for Name: registration_meta; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.registration_meta (object_id, key, value, id) FROM stdin;
1926833684	termos_aceitos	1	1
735327624	termos_aceitos	1	2
735327624	field_31	Trabalho por conta própria, não tenho carteira de trabalho assinada nem outra formalização.	77
735327624	field_50	11.111.111/1111-11	10
1689674626	field_65	""	72
1689674626	field_61	11	69
1731020007	field_10	"2020-08-07"	40
1689674626	field_63	Verdade	73
1689674626	field_64	"050.913.009-70"	71
735327624	field_8	"Rafael Chaves"	6
735327624	field_6	"050.913.009-70"	9
735327624	field_9	Iara Maria Chaves	8
735327624	field_11	"11 12321231"	13
735327624	field_12	""	14
735327624	field_10	"2020-08-26"	3
735327624	field_7	"Rafael Freitas"	7
735327624	field_23	Comunidades Ribeirinhas.	16
735327624	field_27	["Artes do Teatro.","Audiovisual.","Cultura Popular.","Gastronomia."]	4
1926833684	field_6	"323.232.312-31"	17
1926833684	field_11	""	20
1926833684	field_12	""	21
1926833684	field_13	""	22
1926833684	field_27	[""]	25
1926833684	field_28	[""]	26
1593864955	field_69	""	79
1926833684	field_24	"Ind\\u00edgena."	24
1926833684	field_8	"Rafael Chaves Freitas"	19
1926833684	field_10	"2020-08-26"	27
1926833684	field_22	"Mulher Trans\\/Travesti."	23
1926833684	field_7	"Rafael Freitas"	18
1593864955	field_67	{"En_CEP":"12332-12","En_Nome_Logradouro":"","En_Num":"","En_Complemento":"","En_Bairro":"","En_Municipio":""}	80
735327624	field_24	"Ind\\u00edgena."	12
1593864955	field_68	"RAaaasd"	78
735327624	field_13	"rafael@hacklab.com.br"	15
1731020007	termos_aceitos	1	28
1731020007	field_8	"Rafael Chaves"	31
1731020007	field_9	Iara Maria	39
792482838	termos_aceitos	1	49
1731020007	field_13	"rafael@hacklab.com.br"	34
1731020007	field_22	"Homem Trans."	35
1731020007	field_23	Ciganos(as).	41
1967657373	field_73	\N	99
1731020007	field_25	Intelectual.	42
1731020007	field_26	NÃO	43
1731020007	field_14	Rondônia (RO)	44
1731020007	field_27	["Cultura Popular.","Literatura.","\\u00d3pera."]	37
1731020007	field_28	["Consultor(a) ou Curador(a). ","Produtor(a) ou Gestor(a).","T\\u00e9cnico(a)."]	38
1731020007	field_31	Trabalho, mas não tenho carteira de trabalho assinada.	45
1731020007	field_34	Banco do Brasil	46
1731020007	field_11	"(11) 9332-2123"	32
792482838	field_12	""	54
792482838	field_13	""	55
1731020007	field_51	cpf: CPF do Dependente	47
1731020007	field_16	OUTROSSSS	48
792482838	field_22	""	56
792482838	field_24	""	57
1731020007	field_12	"(11) 1234-1233"	33
792482838	field_27	[""]	58
792482838	field_28	[""]	59
1020199467	termos_aceitos	1	81
735327624	field_14	Rio Grande do Norte (RN)	75
735327624	field_28	["","Produtor(a) ou Gestor(a).","Outros","Artista, Artes\\u00e3o(\\u00e3), Brincante ou Criador(a)."]	5
792482838	field_8	"Rafael Chaves"	52
792482838	field_9	Iara Maria Chaves	60
792482838	field_10	"1981-09-30"	61
792482838	field_11	"(11) 964655828"	53
792482838	field_6	"123.321.123-12"	50
735327624	field_22	"N\\u00e3o-Bin\\u00e1rie\\/Outra variabilidade."	11
1967657373	termos_aceitos	1	103
792482838	field_7	"asd asd asd "	51
1689674626	field_58	rafael@hacklab.com.br	62
1689674626	field_56	https://hacklab.com.br	63
735327624	field_16	uhum!!	76
1689674626	field_59	Rafael Freitas	66
1020199467	field_11	""	86
1689674626	field_67	{"En_CEP":"01232-12","En_Nome_Logradouro":"","En_Num":"35","En_Complemento":"apto 91A","En_Bairro":"Bila Madalena","En_Municipio":"S\\u00e3o Paulo"}	74
1020199467	field_12	""	87
1689674626	field_57	2020-08-6	67
1689674626	field_62	["Op\\u00e7\\u00e3o n\\u00famero 3","Op\\u00e7\\u00e3o n\\u00famero 1"]	65
1689674626	field_60	asd	68
1020199467	field_13	""	88
1020199467	field_22	""	89
1020199467	field_24	""	90
1689674626	field_55	050.913.009-70	64
1689674626	field_54	32.123.321/2311-23	70
1020199467	field_27	[]	91
1020199467	field_28	[]	92
1020199467	field_10	"2020-08-13"	85
763896078	field_69	"Homem Transexual"	94
1020199467	field_9	Iara Chaves	93
763896078	field_70	"Branca"	96
1020199467	field_8	"Rafael Chaves asd asd"	84
1020199467	field_7	"Rafael Freitas"	83
763896078	field_75	"Cooletivo"	104
1731020007	field_6	"050.913.009-70"	29
1731020007	field_7	"asd asd asd asd"	30
1020199467	field_6	"050.913.009-90"	82
1731020007	field_24	""	36
1731020007	field_39	true	97
1731020007	field_41	true	98
1967657373	field_69	\N	100
1967657373	field_68	\N	101
1967657373	field_70	\N	102
763896078	field_68	"hacklab\\/ servi\\u00e7os de tecnologia"	95
763896078	field_78	{"En_CEP":"0120"}	107
763896078	field_73	{"endereco":"","En_CEP":"01220-010","En_Nome_Logradouro":"Rua Rego Freitas","En_Num":"","En_Complemento":"","En_Bairro":"Rep\\u00fablica","En_Municipio":"S\\u00e3o Paulo","En_Estado":"SP","location":{"latitude":"0","longitude":"0"},"publicLocation":"true"}	106
792482838	field_17		108
1970483263	field_205	Breve histórico	138
1970483263	field_215	1123	137
902053773	field_200	Raíssa Arruda Medeiros	143
1967657373	field_199	"Rafa Chaves"	113
1967657373	field_202	"Rafael Chaves Freitas"	110
1967657373	field_206	"Branca"	116
902053773	termos_aceitos	1	139
902053773	field_202	"Rud\\u00e1 Freitas Medeiros"	141
902053773	field_208	"2013-07-18"	144
902053773	field_209	""	146
902053773	field_225	São Paulo (SP)	148
902053773	field_222	"N\\u00e3o Informar"	150
902053773	field_206	"Branca"	152
902053773	field_213	NÃO	154
902053773	field_203	["Fotografia.","Gastronomia.","Literatura."]	156
902053773	field_205	Não dá para escrever brevemente o histórico de atuação	158
902053773	field_219	Banco do Brasil	160
902053773	field_215	159417	162
1715162904	termos_aceitos	1	164
763896078	field_74	{"endereco":"","En_CEP":"60714-730","En_Nome_Logradouro":"Rua Campo Maior","En_Num":"530","En_Complemento":"apto D4","En_Bairro":"Dend\\u00ea","En_Municipio":"Fortaleza","En_Estado":"CE","location":{"latitude":"0","longitude":"0"},"publicLocation":"true"}	105
1715162904	field_225	Rio Grande do Sul (RS)	172
1715162904	field_222	"Mulher"	174
1715162904	field_213	NÃO	178
1715162904	field_223	NÃO	180
1715162904	field_204	["Artista, Artes\\u00e3o(\\u00e3), Brincante ou Criador(a).","Consultor(a) ou Curador(a). "]	182
1715162904	field_218	Conta corrente.	184
1715162904	field_214	123231	186
1715162904	field_220	informações, caso julgue necessário. **Referente a todo formul	188
1715162904	field_202	"Rafael Freitas"	166
1715162904	field_208	"2020-08-12"	168
1715162904	field_209	"123123123"	170
1715162904	field_206	"Amarela"	176
1715162904	field_216	não já	190
905535019	field_198	"1"	192
1750691250	field_198	"111.1"	194
413170950	field_198	"050.913.009-70"	196
1066273876	termos_aceitos	1	198
1066273876	field_202	"rafael freitas"	200
1066273876	field_200	Nome da mãe	202
1066273876	field_209	"32312312323123"	204
1066273876	field_225	Pará (PA)	206
1066273876	field_222	"Homem"	208
1066273876	field_206	"Parda"	210
1066273876	field_213	NÃO	212
1066273876	field_223	NÃO	214
1066273876	field_204	["Artista, Artes\\u00e3o(\\u00e3), Brincante ou Criador(a).","Produtor(a) ou Gestor(a)."]	216
1066273876	field_218	Conta corrente.	218
1066273876	field_214	123123	220
1066273876	field_216	asd asda	222
1066273876	field_208	"2020-08-13"	224
1076435879	field_205	aaaaa	226
1967657373	field_203	["[]"]	114
1967657373	field_204	["[]"]	115
1715162904	field_219	Banestes	185
1715162904	field_215	111233	187
1715162904	field_198	"050.913.009-70"	165
1967657373	field_222	"\\"\\""	120
1967657373	field_201	""	109
1967657373	field_226	{"endereco":"","En_CEP":"","En_Nome_Logradouro":"","En_Num":"","En_Complemento":"","En_Bairro":"","En_Municipio":"","En_Estado":"","location":{"latitude":"-27.6039300012","longitude":"-48.5411803391"},"publicLocation":"false"}	111
1967657373	field_208	"2020-08-19"	117
1967657373	field_209	""	118
1967657373	field_210	""	119
1970483263	termos_aceitos	1	121
1970483263	field_204	[]	128
1970483263	field_206	"Preta"	129
1970483263	field_226	{"endereco":"Rua Rego Freitas, 530, apto D4, Rep\\u00fablica, 01220-010, S\\u00e3o Paulo, SP","En_CEP":"01220-010","En_Nome_Logradouro":"Rua Rego Freitas","En_Num":"530","En_Complemento":"apto D4","En_Bairro":"Rep\\u00fablica","En_Municipio":"S\\u00e3o Paulo","En_Estado":"SP","location":{"latitude":"-23.5465762","longitude":"-46.6467484"},"publicLocation":"true"}	124
1970483263	field_208	"2020-01-27"	130
1970483263	field_225	Santa Catarina (SC)	134
1715162904	field_199	"Sardinha"	189
1970483263	field_222	"ASDASDASD"	133
1715162904	field_201	"123123123"	169
1715162904	field_210	"rafafafa@asdasda.cm"	171
905535019	termos_aceitos	1	191
1970483263	field_200	será?	135
1750691250	termos_aceitos	1	193
413170950	termos_aceitos	1	195
413170950	field_202	"1233"	197
1066273876	field_199	"rafael chaves"	201
1970483263	field_210	""	132
1066273876	field_201	"11232323123"	203
1066273876	field_210	"raaasfas@asdasd.com"	205
1066273876	field_226	{"endereco":"","En_CEP":"01220-010","En_Nome_Logradouro":"Rua Rego Freitas","En_Num":"530","En_Complemento":"d4","En_Bairro":"Rep\\u00fablica","En_Municipio":"S\\u00e3o Paulo","En_Estado":"SP","location":{"latitude":"0","longitude":"0"},"publicLocation":"false"}	207
1066273876	field_207	Comunidades Rurais.	209
1066273876	field_212	Visual.	211
1066273876	field_211	050.913.009-70	213
1066273876	field_203	["Artes da Dan\\u00e7a.","Audiovisual.","Literatura.","Moda."]	215
1066273876	field_205	asda sda sd a	217
1066273876	field_219	Banco do Brasil	219
1066273876	field_215	123123123	221
1066273876	field_220	ad asd asd asd asd asd	223
1970483263	field_214	12	136
1066273876	field_198	"050.913.009-70"	199
1970483263	field_199	"Rafael"	126
1970483263	field_202	"Rafael"	123
1970483263	field_201	"11999999999"	122
1970483263	field_203	["Artes do Teatro.","Fotografia."]	127
1970483263	field_198	"050.913.009-70"	125
902053773	field_199	"Rud\\u00e1"	142
902053773	field_201	"11 964655828"	145
902053773	field_210	"ruda@teste.com"	147
1970483263	field_209	"1"	131
1967657373	field_198	"050.913.009-70"	112
902053773	field_226	{"endereco":"","En_CEP":"05453-060","En_Nome_Logradouro":"Pra\\u00e7a Japuba","En_Num":"35","En_Complemento":"apto 91A","En_Bairro":"Vila Madalena","En_Municipio":"S\\u00e3o Paulo","En_Estado":"SP","location":{"latitude":"0","longitude":"0"},"publicLocation":"false"}	149
902053773	field_207	Não pertenço a comunidade tradicional	151
902053773	field_212	Não sou deficiente.	153
902053773	field_223	NÃO	155
902053773	field_204	["Outros"]	157
902053773	field_218	Conta corrente.	159
902053773	field_214	14532	161
902053773	field_220	e agora josé??	163
1076435879	termos_aceitos	1	225
902053773	field_198	"050.913.009-70"	140
1715162904	field_200	Não se sabe	167
1715162904	field_226	{"endereco":"","En_CEP":"05453-060","En_Nome_Logradouro":"Pra\\u00e7a Japuba","En_Num":"35","En_Complemento":"apto 91a","En_Bairro":"Vila Madalena","En_Municipio":"S\\u00e3o Paulo","En_Estado":"SP","location":{"latitude":"0","longitude":"0"},"publicLocation":"false"}	173
1715162904	field_207	Comunidades Ribeirinhas.	175
1715162904	field_212	Intelectual.	177
1715162904	field_211	050.913.009-70	179
1715162904	field_203	["Cultura Popular.","Design.","Artes da Dan\\u00e7a."]	181
1715162904	field_205	forma resumida seu histórico na área da cultura e as funções que desempenha, além de suas principais experiências. Em caso de relato oral, insira links com o breve histórico de atuação, preferencialmente do Youtube ou Vimeo (se privado, deve disponibilizar a chave de	183
\.


--
-- Data for Name: request; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.request (id, request_uid, requester_user_id, origin_type, origin_id, destination_type, destination_id, metadata, type, create_timestamp, action_timestamp, status) FROM stdin;
\.


--
-- Data for Name: role; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.role (id, usr_id, name, subsite_id) FROM stdin;
2	1	saasSuperAdmin	\N
\.


--
-- Data for Name: seal; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.seal (id, agent_id, name, short_description, long_description, valid_period, create_timestamp, status, certificate_text, update_timestamp, subsite_id) FROM stdin;
1	1	Selo Mapas	Descrição curta Selo Mapas	Descrição longa Selo Mapas	0	2019-03-07 23:54:04	1	\N	2019-03-07 00:00:00	\N
\.


--
-- Data for Name: seal_meta; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.seal_meta (id, object_id, key, value) FROM stdin;
\.


--
-- Data for Name: seal_relation; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.seal_relation (id, seal_id, object_id, create_timestamp, status, object_type, agent_id, owner_id, validate_date, renovation_request) FROM stdin;
1	1	1	2020-07-29 19:34:48	1	MapasCulturais\\Entities\\Agent	1	1	2020-07-29	\N
\.


--
-- Data for Name: space; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.space (id, parent_id, location, _geo_location, name, short_description, long_description, create_timestamp, status, type, agent_id, is_verified, public, update_timestamp, subsite_id) FROM stdin;
1	\N	(-48.5069237149847936,-27.588867650000001)	0101000020E610000098B654E0E24048C0216CC207C0963BC0	Museu Sei La	o museu sei lá o quê	\N	2020-08-24 06:44:56	1	61	4	f	f	2020-08-24 07:13:00	\N
\.


--
-- Data for Name: space_meta; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.space_meta (object_id, key, value, id) FROM stdin;
1	En_Bairro		4
1	En_CEP		1
1	En_Complemento		8
1	endereco		7
1	En_Estado		6
1	En_Municipio		5
1	En_Nome_Logradouro		2
1	En_Num		3
\.


--
-- Data for Name: space_relation; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.space_relation (id, space_id, object_id, create_timestamp, status, object_type) FROM stdin;
1	1	1967657373	2020-08-24 06:45:06	1	MapasCulturais\\Entities\\Registration
\.


--
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) FROM stdin;
\.


--
-- Data for Name: subsite; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.subsite (id, name, create_timestamp, status, agent_id, url, namespace, alias_url, verified_seals) FROM stdin;
\.


--
-- Data for Name: subsite_meta; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.subsite_meta (object_id, key, value, id) FROM stdin;
\.


--
-- Data for Name: term; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.term (id, taxonomy, term, description) FROM stdin;
1	area	Arquitetura-Urbanismo	
2	area	Arte de Rua	
3	area	Arquivo	
4	area	Dança	
37	area	Cultura Popular	
38	area	Comunicação	
\.


--
-- Data for Name: term_relation; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.term_relation (term_id, object_type, object_id, id) FROM stdin;
1	MapasCulturais\\Entities\\Agent	1	1
1	MapasCulturais\\Entities\\Agent	2	2
2	MapasCulturais\\Entities\\Agent	2	3
1	MapasCulturais\\Entities\\Agent	4	4
3	MapasCulturais\\Entities\\Agent	4	5
4	MapasCulturais\\Entities\\Agent	5	6
37	MapasCulturais\\Entities\\Space	1	39
38	MapasCulturais\\Entities\\Agent	38	40
1	MapasCulturais\\Entities\\Agent	39	41
\.


--
-- Data for Name: user_app; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.user_app (public_key, private_key, user_id, name, status, create_timestamp, subsite_id) FROM stdin;
\.


--
-- Data for Name: user_meta; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.user_meta (object_id, key, value, id) FROM stdin;
1	localAuthenticationPassword	$2y$10$iIXeqhX.4fEAAVZPsbtRde7CFw1ChduCi8NsnXGnJc6TlelY6gf3e	2
1	aldirblanc_tipo_usuario	solicitante	4
1	loginAttemp	0	3
2	aldirblanc_tipo_usuario	solicitante	6
3	aldirblanc_tipo_usuario	solicitante	8
4	aldirblanc_tipo_usuario	solicitante	10
2	deleteAccountToken	2519b46ef26b8a698bf457dea86012e2bb3acc14	5
3	deleteAccountToken	080600d4dc3eba5d807097eada9eb1034351206a	7
5	aldirblanc_tipo_usuario	solicitante	12
1	deleteAccountToken	6b75d8a02b26e384155eb6818c7cffe60ba59eb9	1
6	deleteAccountToken	106c6feeab506b4472ef725776ecf762825dd071	13
6	aldirblanc_tipo_usuario	solicitante	14
7	deleteAccountToken	349903cc49181a8aa73a04e765516959091a1d20	15
7	aldirblanc_tipo_usuario	solicitante	16
8	deleteAccountToken	ac7a412ab43a01305e9cac38c966ec1f99cf6472	17
8	aldirblanc_tipo_usuario	solicitante	18
9	deleteAccountToken	c82709482d540a1fe86996e63eb3c70b59bda54e	19
9	aldirblanc_tipo_usuario	solicitante	20
10	deleteAccountToken	c3ec00d15bb550658203e03372f9411cb0e16580	21
10	aldirblanc_tipo_usuario	solicitante	22
11	deleteAccountToken	58dc0db607167bddeb3a8c35adaafb1fde5b32b9	23
11	aldirblanc_tipo_usuario	solicitante	24
4	deleteAccountToken	3eaf1620cdb859dc55d8ad5e6169478776b1d229	9
5	deleteAccountToken	2e005d33fdee241ebb2a03668845adf590f887d9	11
12	deleteAccountToken	4197ac38d92a5857bc75567530f8992bdfcdb3b9	25
12	aldirblanc_tipo_usuario	solicitante	26
\.


--
-- Data for Name: usr; Type: TABLE DATA; Schema: public; Owner: mapas
--

COPY public.usr (id, auth_provider, auth_uid, email, last_login_timestamp, create_timestamp, status, profile_id) FROM stdin;
2	0	fake-5f385c65ee7d0	rafael@hacklab.com.br	2020-08-24 18:03:30	2020-08-15 22:06:29	1	2
3	0	fake-5f3f070a6e9d5	teste1@teste.com	2020-08-25 13:18:15	2020-08-20 23:28:10	1	3
1	1	1	Admin@local	2020-08-26 04:48:40	2019-03-07 00:00:00	1	1
6	0	fake-5f460a124febd	ruda@teste.com	2020-08-26 07:06:58	2020-08-26 07:06:58	1	40
7	0	fake-5f460bfe6d94d	sardinha@teste.com	2020-08-26 07:15:10	2020-08-26 07:15:10	1	41
8	0	fake-5f460dd503c6d	praga@teste.com	2020-08-26 07:23:01	2020-08-26 07:23:01	1	42
9	0	fake-5f461281ecd96	asdasd@asdasd	2020-08-26 07:42:58	2020-08-26 07:42:57	1	43
10	0	fake-5f4612ee148a8	rba@hacklab.com.br	2020-08-26 07:44:46	2020-08-26 07:44:46	1	44
11	0	fake-5f4613a1acc1e	raasd@asdasdasdasd.com	2020-08-26 07:47:46	2020-08-26 07:47:45	1	45
4	0	fake-5f3f714c2897a	rafachaves@teste.com	2020-08-26 22:35:37	2020-08-21 07:01:32	1	4
5	0	fake-5f4585dca8ad9	sardinha@teste.com	2020-08-27 13:20:14	2020-08-25 21:42:52	1	39
12	0	fake-5f47b45dc34ee	teste@teste.com	2020-08-27 13:25:50	2020-08-27 13:25:49	1	46
\.


--
-- Data for Name: geocode_settings; Type: TABLE DATA; Schema: tiger; Owner: mapas
--

COPY tiger.geocode_settings (name, setting, unit, category, short_desc) FROM stdin;
\.


--
-- Data for Name: pagc_gaz; Type: TABLE DATA; Schema: tiger; Owner: mapas
--

COPY tiger.pagc_gaz (id, seq, word, stdword, token, is_custom) FROM stdin;
\.


--
-- Data for Name: pagc_lex; Type: TABLE DATA; Schema: tiger; Owner: mapas
--

COPY tiger.pagc_lex (id, seq, word, stdword, token, is_custom) FROM stdin;
\.


--
-- Data for Name: pagc_rules; Type: TABLE DATA; Schema: tiger; Owner: mapas
--

COPY tiger.pagc_rules (id, rule, is_custom) FROM stdin;
\.


--
-- Data for Name: topology; Type: TABLE DATA; Schema: topology; Owner: mapas
--

COPY topology.topology (id, name, srid, "precision", hasz) FROM stdin;
\.


--
-- Data for Name: layer; Type: TABLE DATA; Schema: topology; Owner: mapas
--

COPY topology.layer (topology_id, layer_id, schema_name, table_name, feature_column, feature_type, level, child_id) FROM stdin;
\.


--
-- Name: _mesoregiao_gid_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public._mesoregiao_gid_seq', 1, false);


--
-- Name: _microregiao_gid_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public._microregiao_gid_seq', 1, false);


--
-- Name: _municipios_gid_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public._municipios_gid_seq', 1, false);


--
-- Name: agent_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.agent_id_seq', 46, true);


--
-- Name: agent_meta_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.agent_meta_id_seq', 131, true);


--
-- Name: agent_relation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.agent_relation_id_seq', 35, true);


--
-- Name: entity_revision_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.entity_revision_id_seq', 814, true);


--
-- Name: evaluation_method_configuration_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.evaluation_method_configuration_id_seq', 3, true);


--
-- Name: evaluationmethodconfiguration_meta_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.evaluationmethodconfiguration_meta_id_seq', 1, false);


--
-- Name: event_attendance_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.event_attendance_id_seq', 1, false);


--
-- Name: event_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.event_id_seq', 1, false);


--
-- Name: event_meta_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.event_meta_id_seq', 1, false);


--
-- Name: event_occurrence_cancellation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.event_occurrence_cancellation_id_seq', 1, false);


--
-- Name: event_occurrence_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.event_occurrence_id_seq', 1, false);


--
-- Name: event_occurrence_recurrence_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.event_occurrence_recurrence_id_seq', 1, false);


--
-- Name: file_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.file_id_seq', 21, true);


--
-- Name: geo_division_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.geo_division_id_seq', 1, false);


--
-- Name: metalist_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.metalist_id_seq', 1, false);


--
-- Name: notification_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.notification_id_seq', 1, false);


--
-- Name: notification_meta_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.notification_meta_id_seq', 1, false);


--
-- Name: occurrence_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.occurrence_id_seq', 100000, false);


--
-- Name: opportunity_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.opportunity_id_seq', 3, true);


--
-- Name: opportunity_meta_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.opportunity_meta_id_seq', 17, true);


--
-- Name: pcache_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.pcache_id_seq', 5520, true);


--
-- Name: permission_cache_pending_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.permission_cache_pending_seq', 368, true);


--
-- Name: project_event_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.project_event_id_seq', 1, false);


--
-- Name: project_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.project_id_seq', 1, true);


--
-- Name: project_meta_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.project_meta_id_seq', 1, false);


--
-- Name: pseudo_random_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.pseudo_random_id_seq', 23, true);


--
-- Name: registration_evaluation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.registration_evaluation_id_seq', 1, false);


--
-- Name: registration_field_configuration_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.registration_field_configuration_id_seq', 227, true);


--
-- Name: registration_file_configuration_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.registration_file_configuration_id_seq', 5, true);


--
-- Name: registration_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.registration_id_seq', 1, false);


--
-- Name: registration_meta_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.registration_meta_id_seq', 226, true);


--
-- Name: request_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.request_id_seq', 1, true);


--
-- Name: revision_data_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.revision_data_id_seq', 1623, true);


--
-- Name: role_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.role_id_seq', 2, true);


--
-- Name: seal_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.seal_id_seq', 1, false);


--
-- Name: seal_meta_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.seal_meta_id_seq', 1, false);


--
-- Name: seal_relation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.seal_relation_id_seq', 1, true);


--
-- Name: space_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.space_id_seq', 1, true);


--
-- Name: space_meta_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.space_meta_id_seq', 8, true);


--
-- Name: space_relation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.space_relation_id_seq', 1, true);


--
-- Name: subsite_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.subsite_id_seq', 1, false);


--
-- Name: subsite_meta_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.subsite_meta_id_seq', 1, false);


--
-- Name: term_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.term_id_seq', 38, true);


--
-- Name: term_relation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.term_relation_id_seq', 41, true);


--
-- Name: user_meta_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.user_meta_id_seq', 26, true);


--
-- Name: usr_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mapas
--

SELECT pg_catalog.setval('public.usr_id_seq', 12, true);


--
-- Name: _mesoregiao _mesoregiao_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public._mesoregiao
    ADD CONSTRAINT _mesoregiao_pkey PRIMARY KEY (gid);


--
-- Name: _microregiao _microregiao_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public._microregiao
    ADD CONSTRAINT _microregiao_pkey PRIMARY KEY (gid);


--
-- Name: _municipios _municipios_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public._municipios
    ADD CONSTRAINT _municipios_pkey PRIMARY KEY (gid);


--
-- Name: agent_meta agent_meta_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.agent_meta
    ADD CONSTRAINT agent_meta_pk PRIMARY KEY (id);


--
-- Name: agent agent_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.agent
    ADD CONSTRAINT agent_pk PRIMARY KEY (id);


--
-- Name: agent_relation agent_relation_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.agent_relation
    ADD CONSTRAINT agent_relation_pkey PRIMARY KEY (id);


--
-- Name: db_update db_update_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.db_update
    ADD CONSTRAINT db_update_pk PRIMARY KEY (name);


--
-- Name: entity_revision_data entity_revision_data_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.entity_revision_data
    ADD CONSTRAINT entity_revision_data_pkey PRIMARY KEY (id);


--
-- Name: entity_revision entity_revision_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.entity_revision
    ADD CONSTRAINT entity_revision_pkey PRIMARY KEY (id);


--
-- Name: entity_revision_revision_data entity_revision_revision_data_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.entity_revision_revision_data
    ADD CONSTRAINT entity_revision_revision_data_pkey PRIMARY KEY (revision_id, revision_data_id);


--
-- Name: evaluation_method_configuration evaluation_method_configuration_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.evaluation_method_configuration
    ADD CONSTRAINT evaluation_method_configuration_pkey PRIMARY KEY (id);


--
-- Name: evaluationmethodconfiguration_meta evaluationmethodconfiguration_meta_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.evaluationmethodconfiguration_meta
    ADD CONSTRAINT evaluationmethodconfiguration_meta_pkey PRIMARY KEY (id);


--
-- Name: event_attendance event_attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_attendance
    ADD CONSTRAINT event_attendance_pkey PRIMARY KEY (id);


--
-- Name: event_meta event_meta_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_meta
    ADD CONSTRAINT event_meta_pk PRIMARY KEY (id);


--
-- Name: event_occurrence_cancellation event_occurrence_cancellation_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_occurrence_cancellation
    ADD CONSTRAINT event_occurrence_cancellation_pkey PRIMARY KEY (id);


--
-- Name: event_occurrence event_occurrence_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_occurrence
    ADD CONSTRAINT event_occurrence_pkey PRIMARY KEY (id);


--
-- Name: event_occurrence_recurrence event_occurrence_recurrence_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_occurrence_recurrence
    ADD CONSTRAINT event_occurrence_recurrence_pkey PRIMARY KEY (id);


--
-- Name: event event_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_pk PRIMARY KEY (id);


--
-- Name: file file_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.file
    ADD CONSTRAINT file_pk PRIMARY KEY (id);


--
-- Name: geo_division geo_divisions_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.geo_division
    ADD CONSTRAINT geo_divisions_pkey PRIMARY KEY (id);


--
-- Name: metadata metadata_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.metadata
    ADD CONSTRAINT metadata_pk PRIMARY KEY (object_id, object_type, key);


--
-- Name: metalist metalist_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.metalist
    ADD CONSTRAINT metalist_pk PRIMARY KEY (id);


--
-- Name: notification_meta notification_meta_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.notification_meta
    ADD CONSTRAINT notification_meta_pkey PRIMARY KEY (id);


--
-- Name: notification notification_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_pk PRIMARY KEY (id);


--
-- Name: opportunity_meta opportunity_meta_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.opportunity_meta
    ADD CONSTRAINT opportunity_meta_pkey PRIMARY KEY (id);


--
-- Name: opportunity opportunity_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.opportunity
    ADD CONSTRAINT opportunity_pkey PRIMARY KEY (id);


--
-- Name: pcache pcache_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.pcache
    ADD CONSTRAINT pcache_pkey PRIMARY KEY (id);


--
-- Name: permission_cache_pending permission_cache_pending_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.permission_cache_pending
    ADD CONSTRAINT permission_cache_pending_pkey PRIMARY KEY (id);


--
-- Name: procuration procuration_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.procuration
    ADD CONSTRAINT procuration_pkey PRIMARY KEY (token);


--
-- Name: project_event project_event_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.project_event
    ADD CONSTRAINT project_event_pk PRIMARY KEY (id);


--
-- Name: project_meta project_meta_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.project_meta
    ADD CONSTRAINT project_meta_pk PRIMARY KEY (id);


--
-- Name: project project_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT project_pk PRIMARY KEY (id);


--
-- Name: registration_evaluation registration_evaluation_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.registration_evaluation
    ADD CONSTRAINT registration_evaluation_pkey PRIMARY KEY (id);


--
-- Name: registration_field_configuration registration_field_configuration_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.registration_field_configuration
    ADD CONSTRAINT registration_field_configuration_pkey PRIMARY KEY (id);


--
-- Name: registration_file_configuration registration_file_configuration_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.registration_file_configuration
    ADD CONSTRAINT registration_file_configuration_pkey PRIMARY KEY (id);


--
-- Name: registration_meta registration_meta_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.registration_meta
    ADD CONSTRAINT registration_meta_pk PRIMARY KEY (id);


--
-- Name: registration registration_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.registration
    ADD CONSTRAINT registration_pkey PRIMARY KEY (id);


--
-- Name: request request_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.request
    ADD CONSTRAINT request_pk PRIMARY KEY (id);


--
-- Name: role role_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.role
    ADD CONSTRAINT role_pk PRIMARY KEY (id);


--
-- Name: subsite saas_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.subsite
    ADD CONSTRAINT saas_pkey PRIMARY KEY (id);


--
-- Name: seal_meta seal_meta_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.seal_meta
    ADD CONSTRAINT seal_meta_pkey PRIMARY KEY (id);


--
-- Name: seal seal_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.seal
    ADD CONSTRAINT seal_pkey PRIMARY KEY (id);


--
-- Name: seal_relation seal_relation_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.seal_relation
    ADD CONSTRAINT seal_relation_pkey PRIMARY KEY (id);


--
-- Name: space_meta space_meta_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.space_meta
    ADD CONSTRAINT space_meta_pk PRIMARY KEY (id);


--
-- Name: space space_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.space
    ADD CONSTRAINT space_pk PRIMARY KEY (id);


--
-- Name: space_relation space_relation_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.space_relation
    ADD CONSTRAINT space_relation_pkey PRIMARY KEY (id);


--
-- Name: subsite_meta subsite_meta_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.subsite_meta
    ADD CONSTRAINT subsite_meta_pkey PRIMARY KEY (id);


--
-- Name: term term_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.term
    ADD CONSTRAINT term_pk PRIMARY KEY (id);


--
-- Name: term_relation term_relation_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.term_relation
    ADD CONSTRAINT term_relation_pk PRIMARY KEY (id);


--
-- Name: user_app user_app_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.user_app
    ADD CONSTRAINT user_app_pk PRIMARY KEY (public_key);


--
-- Name: user_meta user_meta_pkey; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.user_meta
    ADD CONSTRAINT user_meta_pkey PRIMARY KEY (id);


--
-- Name: usr usr_pk; Type: CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.usr
    ADD CONSTRAINT usr_pk PRIMARY KEY (id);


--
-- Name: agent_meta_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX agent_meta_key_idx ON public.agent_meta USING btree (key);


--
-- Name: agent_meta_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX agent_meta_owner_idx ON public.agent_meta USING btree (object_id);


--
-- Name: agent_meta_owner_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX agent_meta_owner_key_idx ON public.agent_meta USING btree (object_id, key);


--
-- Name: agent_relation_all; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX agent_relation_all ON public.agent_relation USING btree (agent_id, object_type, object_id);


--
-- Name: alias_url_index; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX alias_url_index ON public.subsite USING btree (alias_url);


--
-- Name: evaluationmethodconfiguration_meta_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX evaluationmethodconfiguration_meta_owner_idx ON public.evaluationmethodconfiguration_meta USING btree (object_id);


--
-- Name: evaluationmethodconfiguration_meta_owner_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX evaluationmethodconfiguration_meta_owner_key_idx ON public.evaluationmethodconfiguration_meta USING btree (object_id, key);


--
-- Name: event_attendance_type_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX event_attendance_type_idx ON public.event_attendance USING btree (type);


--
-- Name: event_meta_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX event_meta_key_idx ON public.event_meta USING btree (key);


--
-- Name: event_meta_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX event_meta_owner_idx ON public.event_meta USING btree (object_id);


--
-- Name: event_meta_owner_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX event_meta_owner_key_idx ON public.event_meta USING btree (object_id, key);


--
-- Name: event_occurrence_status_index; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX event_occurrence_status_index ON public.event_occurrence USING btree (status);


--
-- Name: file_group_index; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX file_group_index ON public.file USING btree (grp);


--
-- Name: file_owner_grp_index; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX file_owner_grp_index ON public.file USING btree (object_type, object_id, grp);


--
-- Name: file_owner_index; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX file_owner_index ON public.file USING btree (object_type, object_id);


--
-- Name: geo_divisions_geom_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX geo_divisions_geom_idx ON public.geo_division USING gist (geom);


--
-- Name: idx_1a0e9a30232d562b; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_1a0e9a30232d562b ON public.space_relation USING btree (object_id);


--
-- Name: idx_1a0e9a3023575340; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_1a0e9a3023575340 ON public.space_relation USING btree (space_id);


--
-- Name: idx_209c792e9a34590f; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_209c792e9a34590f ON public.registration_file_configuration USING btree (opportunity_id);


--
-- Name: idx_22781144c79c849a; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_22781144c79c849a ON public.user_app USING btree (subsite_id);


--
-- Name: idx_268b9c9dc79c849a; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_268b9c9dc79c849a ON public.agent USING btree (subsite_id);


--
-- Name: idx_2972c13ac79c849a; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_2972c13ac79c849a ON public.space USING btree (subsite_id);


--
-- Name: idx_2e186c5c833d8f43; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_2e186c5c833d8f43 ON public.registration_evaluation USING btree (registration_id);


--
-- Name: idx_2e186c5ca76ed395; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_2e186c5ca76ed395 ON public.registration_evaluation USING btree (user_id);


--
-- Name: idx_2e30ae30c79c849a; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_2e30ae30c79c849a ON public.seal USING btree (subsite_id);


--
-- Name: idx_2fb3d0eec79c849a; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_2fb3d0eec79c849a ON public.project USING btree (subsite_id);


--
-- Name: idx_350dd4be140e9f00; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_350dd4be140e9f00 ON public.event_attendance USING btree (event_occurrence_id);


--
-- Name: idx_350dd4be23575340; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_350dd4be23575340 ON public.event_attendance USING btree (space_id);


--
-- Name: idx_350dd4be71f7e88b; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_350dd4be71f7e88b ON public.event_attendance USING btree (event_id);


--
-- Name: idx_350dd4bea76ed395; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_350dd4bea76ed395 ON public.event_attendance USING btree (user_id);


--
-- Name: idx_3bae0aa7c79c849a; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_3bae0aa7c79c849a ON public.event USING btree (subsite_id);


--
-- Name: idx_3d853098232d562b; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_3d853098232d562b ON public.pcache USING btree (object_id);


--
-- Name: idx_3d853098a76ed395; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_3d853098a76ed395 ON public.pcache USING btree (user_id);


--
-- Name: idx_57698a6ac79c849a; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_57698a6ac79c849a ON public.role USING btree (subsite_id);


--
-- Name: idx_60c85cb1166d1f9c; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_60c85cb1166d1f9c ON public.registration_field_configuration USING btree (opportunity_id);


--
-- Name: idx_60c85cb19a34590f; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_60c85cb19a34590f ON public.registration_field_configuration USING btree (opportunity_id);


--
-- Name: idx_62a8a7a73414710b; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_62a8a7a73414710b ON public.registration USING btree (agent_id);


--
-- Name: idx_62a8a7a79a34590f; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_62a8a7a79a34590f ON public.registration USING btree (opportunity_id);


--
-- Name: idx_62a8a7a7c79c849a; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX idx_62a8a7a7c79c849a ON public.registration USING btree (subsite_id);


--
-- Name: notification_meta_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX notification_meta_key_idx ON public.notification_meta USING btree (key);


--
-- Name: notification_meta_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX notification_meta_owner_idx ON public.notification_meta USING btree (object_id);


--
-- Name: notification_meta_owner_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX notification_meta_owner_key_idx ON public.notification_meta USING btree (object_id, key);


--
-- Name: opportunity_entity_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX opportunity_entity_idx ON public.opportunity USING btree (object_type, object_id);


--
-- Name: opportunity_meta_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX opportunity_meta_owner_idx ON public.opportunity_meta USING btree (object_id);


--
-- Name: opportunity_meta_owner_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX opportunity_meta_owner_key_idx ON public.opportunity_meta USING btree (object_id, key);


--
-- Name: opportunity_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX opportunity_owner_idx ON public.opportunity USING btree (agent_id);


--
-- Name: opportunity_parent_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX opportunity_parent_idx ON public.opportunity USING btree (parent_id);


--
-- Name: owner_index; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX owner_index ON public.term_relation USING btree (object_type, object_id);


--
-- Name: pcache_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX pcache_owner_idx ON public.pcache USING btree (object_type, object_id);


--
-- Name: pcache_permission_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX pcache_permission_idx ON public.pcache USING btree (object_type, object_id, action);


--
-- Name: pcache_permission_user_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX pcache_permission_user_idx ON public.pcache USING btree (object_type, object_id, action, user_id);


--
-- Name: procuration_attorney_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX procuration_attorney_idx ON public.procuration USING btree (attorney_user_id);


--
-- Name: procuration_usr_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX procuration_usr_idx ON public.procuration USING btree (usr_id);


--
-- Name: project_meta_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX project_meta_key_idx ON public.project_meta USING btree (key);


--
-- Name: project_meta_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX project_meta_owner_idx ON public.project_meta USING btree (object_id);


--
-- Name: project_meta_owner_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX project_meta_owner_key_idx ON public.project_meta USING btree (object_id, key);


--
-- Name: registration_meta_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX registration_meta_owner_idx ON public.registration_meta USING btree (object_id);


--
-- Name: registration_meta_owner_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX registration_meta_owner_key_idx ON public.registration_meta USING btree (object_id, key);


--
-- Name: request_uid; Type: INDEX; Schema: public; Owner: mapas
--

CREATE UNIQUE INDEX request_uid ON public.request USING btree (request_uid);


--
-- Name: requester_user_index; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX requester_user_index ON public.request USING btree (requester_user_id, origin_type, origin_id);


--
-- Name: seal_meta_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX seal_meta_key_idx ON public.seal_meta USING btree (key);


--
-- Name: seal_meta_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX seal_meta_owner_idx ON public.seal_meta USING btree (object_id);


--
-- Name: seal_meta_owner_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX seal_meta_owner_key_idx ON public.seal_meta USING btree (object_id, key);


--
-- Name: space_location; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX space_location ON public.space USING gist (_geo_location);


--
-- Name: space_meta_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX space_meta_key_idx ON public.space_meta USING btree (key);


--
-- Name: space_meta_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX space_meta_owner_idx ON public.space_meta USING btree (object_id);


--
-- Name: space_meta_owner_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX space_meta_owner_key_idx ON public.space_meta USING btree (object_id, key);


--
-- Name: space_type; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX space_type ON public.space USING btree (type);


--
-- Name: subsite_meta_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX subsite_meta_key_idx ON public.subsite_meta USING btree (key);


--
-- Name: subsite_meta_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX subsite_meta_owner_idx ON public.subsite_meta USING btree (object_id);


--
-- Name: subsite_meta_owner_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX subsite_meta_owner_key_idx ON public.subsite_meta USING btree (object_id, key);


--
-- Name: taxonomy_term_unique; Type: INDEX; Schema: public; Owner: mapas
--

CREATE UNIQUE INDEX taxonomy_term_unique ON public.term USING btree (taxonomy, term);


--
-- Name: uniq_330cb54c9a34590f; Type: INDEX; Schema: public; Owner: mapas
--

CREATE UNIQUE INDEX uniq_330cb54c9a34590f ON public.evaluation_method_configuration USING btree (opportunity_id);


--
-- Name: url_index; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX url_index ON public.subsite USING btree (url);


--
-- Name: user_meta_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX user_meta_key_idx ON public.user_meta USING btree (key);


--
-- Name: user_meta_owner_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX user_meta_owner_idx ON public.user_meta USING btree (object_id);


--
-- Name: user_meta_owner_key_idx; Type: INDEX; Schema: public; Owner: mapas
--

CREATE INDEX user_meta_owner_key_idx ON public.user_meta USING btree (object_id, key);


--
-- Name: agent agent_agent_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.agent
    ADD CONSTRAINT agent_agent_fk FOREIGN KEY (parent_id) REFERENCES public.agent(id);


--
-- Name: agent_relation agent_relation_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.agent_relation
    ADD CONSTRAINT agent_relation_fk FOREIGN KEY (agent_id) REFERENCES public.agent(id);


--
-- Name: entity_revision entity_revision_usr_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.entity_revision
    ADD CONSTRAINT entity_revision_usr_fk FOREIGN KEY (user_id) REFERENCES public.usr(id);


--
-- Name: event event_agent_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_agent_fk FOREIGN KEY (agent_id) REFERENCES public.agent(id);


--
-- Name: event_occurrence event_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_occurrence
    ADD CONSTRAINT event_fk FOREIGN KEY (event_id) REFERENCES public.event(id);


--
-- Name: event_occurrence_cancellation event_occurrence_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_occurrence_cancellation
    ADD CONSTRAINT event_occurrence_fk FOREIGN KEY (event_occurrence_id) REFERENCES public.event_occurrence(id) ON DELETE CASCADE;


--
-- Name: event_occurrence_recurrence event_occurrence_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_occurrence_recurrence
    ADD CONSTRAINT event_occurrence_fk FOREIGN KEY (event_occurrence_id) REFERENCES public.event_occurrence(id) ON DELETE CASCADE;


--
-- Name: project_event event_project_event_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.project_event
    ADD CONSTRAINT event_project_event_fk FOREIGN KEY (event_id) REFERENCES public.event(id);


--
-- Name: file file_file_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.file
    ADD CONSTRAINT file_file_fk FOREIGN KEY (parent_id) REFERENCES public.file(id);


--
-- Name: registration_meta fk_18cc03e9232d562b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.registration_meta
    ADD CONSTRAINT fk_18cc03e9232d562b FOREIGN KEY (object_id) REFERENCES public.registration(id) ON DELETE CASCADE;


--
-- Name: space_relation fk_1a0e9a30232d562b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.space_relation
    ADD CONSTRAINT fk_1a0e9a30232d562b FOREIGN KEY (object_id) REFERENCES public.registration(id);


--
-- Name: space_relation fk_1a0e9a3023575340; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.space_relation
    ADD CONSTRAINT fk_1a0e9a3023575340 FOREIGN KEY (space_id) REFERENCES public.space(id);


--
-- Name: registration_file_configuration fk_209c792e9a34590f; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.registration_file_configuration
    ADD CONSTRAINT fk_209c792e9a34590f FOREIGN KEY (opportunity_id) REFERENCES public.opportunity(id);


--
-- Name: user_app fk_22781144c79c849a; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.user_app
    ADD CONSTRAINT fk_22781144c79c849a FOREIGN KEY (subsite_id) REFERENCES public.subsite(id);


--
-- Name: agent fk_268b9c9dc79c849a; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.agent
    ADD CONSTRAINT fk_268b9c9dc79c849a FOREIGN KEY (subsite_id) REFERENCES public.subsite(id);


--
-- Name: space fk_2972c13ac79c849a; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.space
    ADD CONSTRAINT fk_2972c13ac79c849a FOREIGN KEY (subsite_id) REFERENCES public.subsite(id);


--
-- Name: opportunity_meta fk_2bb06d08232d562b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.opportunity_meta
    ADD CONSTRAINT fk_2bb06d08232d562b FOREIGN KEY (object_id) REFERENCES public.opportunity(id) ON DELETE CASCADE;


--
-- Name: registration_evaluation fk_2e186c5c833d8f43; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.registration_evaluation
    ADD CONSTRAINT fk_2e186c5c833d8f43 FOREIGN KEY (registration_id) REFERENCES public.registration(id) ON DELETE CASCADE;


--
-- Name: registration_evaluation fk_2e186c5ca76ed395; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.registration_evaluation
    ADD CONSTRAINT fk_2e186c5ca76ed395 FOREIGN KEY (user_id) REFERENCES public.usr(id) ON DELETE CASCADE;


--
-- Name: seal fk_2e30ae30c79c849a; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.seal
    ADD CONSTRAINT fk_2e30ae30c79c849a FOREIGN KEY (subsite_id) REFERENCES public.subsite(id);


--
-- Name: evaluation_method_configuration fk_330cb54c9a34590f; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.evaluation_method_configuration
    ADD CONSTRAINT fk_330cb54c9a34590f FOREIGN KEY (opportunity_id) REFERENCES public.opportunity(id);


--
-- Name: event_attendance fk_350dd4be140e9f00; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_attendance
    ADD CONSTRAINT fk_350dd4be140e9f00 FOREIGN KEY (event_occurrence_id) REFERENCES public.event_occurrence(id) ON DELETE CASCADE;


--
-- Name: event_attendance fk_350dd4be23575340; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_attendance
    ADD CONSTRAINT fk_350dd4be23575340 FOREIGN KEY (space_id) REFERENCES public.space(id) ON DELETE CASCADE;


--
-- Name: event_attendance fk_350dd4be71f7e88b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_attendance
    ADD CONSTRAINT fk_350dd4be71f7e88b FOREIGN KEY (event_id) REFERENCES public.event(id) ON DELETE CASCADE;


--
-- Name: event_attendance fk_350dd4bea76ed395; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_attendance
    ADD CONSTRAINT fk_350dd4bea76ed395 FOREIGN KEY (user_id) REFERENCES public.usr(id) ON DELETE CASCADE;


--
-- Name: event fk_3bae0aa7c79c849a; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event
    ADD CONSTRAINT fk_3bae0aa7c79c849a FOREIGN KEY (subsite_id) REFERENCES public.subsite(id);


--
-- Name: pcache fk_3d853098a76ed395; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.pcache
    ADD CONSTRAINT fk_3d853098a76ed395 FOREIGN KEY (user_id) REFERENCES public.usr(id);


--
-- Name: role fk_57698a6ac69d3fb; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.role
    ADD CONSTRAINT fk_57698a6ac69d3fb FOREIGN KEY (usr_id) REFERENCES public.usr(id);


--
-- Name: role fk_57698a6ac79c849a; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.role
    ADD CONSTRAINT fk_57698a6ac79c849a FOREIGN KEY (subsite_id) REFERENCES public.subsite(id);


--
-- Name: registration_field_configuration fk_60c85cb19a34590f; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.registration_field_configuration
    ADD CONSTRAINT fk_60c85cb19a34590f FOREIGN KEY (opportunity_id) REFERENCES public.opportunity(id);


--
-- Name: registration fk_62a8a7a73414710b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.registration
    ADD CONSTRAINT fk_62a8a7a73414710b FOREIGN KEY (agent_id) REFERENCES public.agent(id);


--
-- Name: registration fk_62a8a7a79a34590f; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.registration
    ADD CONSTRAINT fk_62a8a7a79a34590f FOREIGN KEY (opportunity_id) REFERENCES public.opportunity(id);


--
-- Name: notification_meta fk_6fce5f0f232d562b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.notification_meta
    ADD CONSTRAINT fk_6fce5f0f232d562b FOREIGN KEY (object_id) REFERENCES public.notification(id) ON DELETE CASCADE;


--
-- Name: subsite_meta fk_780702f5232d562b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.subsite_meta
    ADD CONSTRAINT fk_780702f5232d562b FOREIGN KEY (object_id) REFERENCES public.subsite(id) ON DELETE CASCADE;


--
-- Name: agent_meta fk_7a69aed6232d562b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.agent_meta
    ADD CONSTRAINT fk_7a69aed6232d562b FOREIGN KEY (object_id) REFERENCES public.agent(id) ON DELETE CASCADE;


--
-- Name: opportunity fk_8389c3d73414710b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.opportunity
    ADD CONSTRAINT fk_8389c3d73414710b FOREIGN KEY (agent_id) REFERENCES public.agent(id);


--
-- Name: seal_meta fk_a92e5e22232d562b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.seal_meta
    ADD CONSTRAINT fk_a92e5e22232d562b FOREIGN KEY (object_id) REFERENCES public.seal(id) ON DELETE CASCADE;


--
-- Name: user_meta fk_ad7358fc232d562b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.user_meta
    ADD CONSTRAINT fk_ad7358fc232d562b FOREIGN KEY (object_id) REFERENCES public.usr(id) ON DELETE CASCADE;


--
-- Name: space_meta fk_bc846ebf232d562b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.space_meta
    ADD CONSTRAINT fk_bc846ebf232d562b FOREIGN KEY (object_id) REFERENCES public.space(id) ON DELETE CASCADE;


--
-- Name: event_meta fk_c839589e232d562b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_meta
    ADD CONSTRAINT fk_c839589e232d562b FOREIGN KEY (object_id) REFERENCES public.event(id) ON DELETE CASCADE;


--
-- Name: procuration fk_d7bae7f3aeb2ed7; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.procuration
    ADD CONSTRAINT fk_d7bae7f3aeb2ed7 FOREIGN KEY (attorney_user_id) REFERENCES public.usr(id);


--
-- Name: procuration fk_d7bae7fc69d3fb; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.procuration
    ADD CONSTRAINT fk_d7bae7fc69d3fb FOREIGN KEY (usr_id) REFERENCES public.usr(id);


--
-- Name: evaluationmethodconfiguration_meta fk_d7edf8b2232d562b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.evaluationmethodconfiguration_meta
    ADD CONSTRAINT fk_d7edf8b2232d562b FOREIGN KEY (object_id) REFERENCES public.evaluation_method_configuration(id) ON DELETE CASCADE;


--
-- Name: project_meta fk_ee63dc2d232d562b; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.project_meta
    ADD CONSTRAINT fk_ee63dc2d232d562b FOREIGN KEY (object_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: notification notification_request_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_request_fk FOREIGN KEY (request_id) REFERENCES public.request(id);


--
-- Name: notification notification_user_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_user_fk FOREIGN KEY (user_id) REFERENCES public.usr(id);


--
-- Name: opportunity opportunity_parent_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.opportunity
    ADD CONSTRAINT opportunity_parent_fk FOREIGN KEY (parent_id) REFERENCES public.opportunity(id);


--
-- Name: project project_agent_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT project_agent_fk FOREIGN KEY (agent_id) REFERENCES public.agent(id);


--
-- Name: event project_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event
    ADD CONSTRAINT project_fk FOREIGN KEY (project_id) REFERENCES public.project(id);


--
-- Name: project_event project_project_event_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.project_event
    ADD CONSTRAINT project_project_event_fk FOREIGN KEY (project_id) REFERENCES public.project(id);


--
-- Name: project project_project_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT project_project_fk FOREIGN KEY (parent_id) REFERENCES public.project(id);


--
-- Name: request requester_user_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.request
    ADD CONSTRAINT requester_user_fk FOREIGN KEY (requester_user_id) REFERENCES public.usr(id);


--
-- Name: entity_revision_revision_data revision_data_entity_revision_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.entity_revision_revision_data
    ADD CONSTRAINT revision_data_entity_revision_fk FOREIGN KEY (revision_id) REFERENCES public.entity_revision(id);


--
-- Name: entity_revision_revision_data revision_data_revision_data_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.entity_revision_revision_data
    ADD CONSTRAINT revision_data_revision_data_fk FOREIGN KEY (revision_data_id) REFERENCES public.entity_revision_data(id);


--
-- Name: subsite_meta saas_saas_meta_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.subsite_meta
    ADD CONSTRAINT saas_saas_meta_fk FOREIGN KEY (object_id) REFERENCES public.subsite(id);


--
-- Name: seal seal_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.seal
    ADD CONSTRAINT seal_fk FOREIGN KEY (agent_id) REFERENCES public.agent(id);


--
-- Name: seal_relation seal_relation_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.seal_relation
    ADD CONSTRAINT seal_relation_fk FOREIGN KEY (seal_id) REFERENCES public.seal(id);


--
-- Name: space space_agent_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.space
    ADD CONSTRAINT space_agent_fk FOREIGN KEY (agent_id) REFERENCES public.agent(id);


--
-- Name: event_occurrence space_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.event_occurrence
    ADD CONSTRAINT space_fk FOREIGN KEY (space_id) REFERENCES public.space(id);


--
-- Name: space space_space_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.space
    ADD CONSTRAINT space_space_fk FOREIGN KEY (parent_id) REFERENCES public.space(id);


--
-- Name: term_relation term_term_relation_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.term_relation
    ADD CONSTRAINT term_term_relation_fk FOREIGN KEY (term_id) REFERENCES public.term(id);


--
-- Name: usr user_profile_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.usr
    ADD CONSTRAINT user_profile_fk FOREIGN KEY (profile_id) REFERENCES public.agent(id);


--
-- Name: agent usr_agent_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.agent
    ADD CONSTRAINT usr_agent_fk FOREIGN KEY (user_id) REFERENCES public.usr(id);


--
-- Name: user_app usr_user_app_fk; Type: FK CONSTRAINT; Schema: public; Owner: mapas
--

ALTER TABLE ONLY public.user_app
    ADD CONSTRAINT usr_user_app_fk FOREIGN KEY (user_id) REFERENCES public.usr(id);


--
-- PostgreSQL database dump complete
--

