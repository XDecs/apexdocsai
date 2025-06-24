-- SB_AI_DOC_GEN_PKG
-- %Purpose: Generates documentation for database objects using OpenAI and stores them versioned by checksum.
-- %Note: This specification only includes the public interface. Detailed parameter descriptions and examples are maintained in the package body.
-- %Components:
--   - generate_for_packages
--   - generate_for_procedures
--   - generate_for_functions
--   - generate_for_tables
--   - process_individual_object

CREATE OR REPLACE PACKAGE SB_AI_DOC_GEN_PKG AS
  -- Triggers documentation generation for all packages
  PROCEDURE generate_for_packages(p_prompt CLOB, p_doc_type VARCHAR2);

  -- Triggers documentation generation for all standalone procedures
  PROCEDURE generate_for_procedures(p_prompt CLOB, p_doc_type VARCHAR2);

  -- Triggers documentation generation for all standalone functions
  PROCEDURE generate_for_functions(p_prompt CLOB, p_doc_type VARCHAR2);

  -- Triggers documentation generation for all user-defined tables
  PROCEDURE generate_for_tables(p_prompt CLOB, p_doc_type VARCHAR2);

  -- Generates markdown documentation for a specific database object using OpenAI API and stores the result.
  FUNCTION process_individual_object(p_name VARCHAR2
                                    , p_type VARCHAR2
                                    , p_prompt CLOB
                                    , p_doc_type VARCHAR2) RETURN CLOB;
END;
/
create or replace PACKAGE BODY SB_AI_DOC_GEN_PKG AS

  ------------------------------------------------------------------------------
  -- FUNCTION: format_response
  -- %Type: Function
  -- %Purpose: Extracts and returns the content from the OpenAI API response.
  -- %Parameters:
  --   p_response - CLOB: JSON-formatted response from the OpenAI API.
  -- %Returns: CLOB - Parsed Markdown content from the API.
  ------------------------------------------------------------------------------
  FUNCTION format_response(p_response IN CLOB) RETURN CLOB IS
    l_response CLOB;
    l_values apex_json.t_values;
  BEGIN
    IF JSON_EXISTS(p_response, '$.choices[0].message') THEN
      l_response := json_value(p_response, '$.choices[0].message.content');
    ELSE
      RETURN NULL;
    END IF;
    RETURN l_response;
  END;

  ------------------------------------------------------------------------------
  -- FUNCTION: generate_prompt_suggestion
  -- %Type: Function
  -- %Purpose: Builds a system prompt asking for documentation suited for a specific object type.
  -- %Parameters:
  --   p_type - VARCHAR2: Object type ('PACKAGE', 'FUNCTION', etc.)
  -- %Returns: VARCHAR2 - Natural language prompt string.
  ------------------------------------------------------------------------------
  FUNCTION generate_prompt_suggestion(p_type VARCHAR2) RETURN VARCHAR2 IS
    l_prompt VARCHAR2(4000);
    l_request JSON_OBJECT_T;
    l_raw_response JSON_OBJECT_T;
    l_messages JSON_ARRAY_T;
    l_message_t JSON_OBJECT_T := JSON_OBJECT_T();
    l_prompt_req VARCHAR2(3000) := q'~I need a robust prompt to generate markup documentation. I need this documentation oriented for ~'||INITCAP(p_type)||q'~ users. <additional instructions here>~';
  BEGIN
    l_messages := JSON_ARRAY_T();
    l_message_t.put('role','system');
    l_message_t.put('content',l_prompt_req);
    l_messages.append(l_message_t);

    l_raw_response := openai_simple_api.create_chat_completion(
      p_model        => 'gpt-4o',
      p_messages     => l_messages,
      p_user         => USER,
      p_skip_if_null => 'Y',
      p_request_j    => l_request
    );

    l_prompt := format_response(l_raw_response.to_clob);
    RETURN l_prompt;
  END generate_prompt_suggestion;

  ------------------------------------------------------------------------------
  -- FUNCTION: process_individual_object
  -- %Type: Function
  -- %Purpose: Generates and stores documentation for a single object.
  -- %Parameters:
  --   p_name      - VARCHAR2: Name of the object.
  --   p_type      - VARCHAR2: Type of object (e.g., 'TABLE', 'PACKAGE').
  --   p_prompt    - CLOB    : Prompt content for the documentation.
  --   p_doc_type  - VARCHAR2: Type of documentation to store (e.g., 'Technical').
  -- %Returns: CLOB - The generated Markdown documentation.
  ------------------------------------------------------------------------------
  FUNCTION process_individual_object(p_name VARCHAR2, p_type VARCHAR2, p_prompt CLOB, p_doc_type VARCHAR2) RETURN CLOB IS
    l_ddl             CLOB;
    l_md_output       CLOB;
    l_hash            VARCHAR2(64);
    l_latest_hash     VARCHAR2(64);
    l_version         NUMBER := 1;
    l_messages        JSON_ARRAY_T;
    l_message_t       JSON_OBJECT_T := JSON_OBJECT_T();
    l_request         JSON_OBJECT_T;
    l_raw_response    JSON_OBJECT_T;
  BEGIN
    l_ddl := DBMS_METADATA.GET_DDL(p_type, p_name);
    BEGIN
      l_hash := SB_GET_MD5(l_ddl);
      BEGIN
        SELECT checksum_hash, version_number
        INTO l_latest_hash, l_version
        FROM SB_AI_DOC_REGISTRY
        WHERE object_name = p_name AND object_type = p_type
        ORDER BY version_number DESC
        FETCH FIRST ROW ONLY;
        IF l_latest_hash = l_hash THEN
          DBMS_OUTPUT.PUT_LINE('--- No changes detected, skipping documentation generation ---');
        ELSE
          l_version := l_version + 1;
        END IF;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          l_version := 1;
      END;
    EXCEPTION
      WHEN OTHERS THEN
        l_hash := TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF');
        SELECT NVL(MAX(version_number), 0) + 1 INTO l_version
        FROM SB_AI_DOC_REGISTRY
        WHERE object_name = p_name AND object_type = p_type;
    END;

    l_messages := JSON_ARRAY_T();
    l_message_t.put('role','system');
    l_message_t.put('content',p_prompt||CHR(10) || l_ddl);
    l_messages.append(l_message_t);

    l_raw_response := openai_simple_api.create_chat_completion(
      p_model        => 'gpt-4o',
      p_messages     => l_messages,
      p_user         => USER,
      p_skip_if_null => 'Y',
      p_request_j    => l_request
    );

    l_md_output := format_response(l_raw_response.to_clob);

    INSERT INTO SB_AI_DOC_REGISTRY (
      object_name,
      object_type,
      object_ddl,
      doc_markdown,
      generated_on,
      generated_by,
      checksum_hash,
      version_number,
      status,
      documentation_type
    ) VALUES (
      p_name,
      p_type,
      l_ddl,
      l_md_output,
      SYSTIMESTAMP,
      USER,
      l_hash,
      l_version,
      'ACTIVE',
      p_doc_type
    );

    RETURN l_md_output;
  END process_individual_object;

  ------------------------------------------------------------------------------
  -- PROCEDURE: process_object
  -- %Type: Procedure
  -- %Purpose: Handles DDL retrieval and generation logic, skipping SB_% prefixed objects.
  -- %Parameters:
  --   p_name     - VARCHAR2: Name of the object.
  --   p_type     - VARCHAR2: Object type.
  --   p_prompt   - CLOB    : Prompt content.
  --   p_doc_type - VARCHAR2: Type of documentation.
  ------------------------------------------------------------------------------
  PROCEDURE process_object(p_name VARCHAR2, p_type VARCHAR2, p_prompt CLOB, p_doc_type VARCHAR2) IS
    l_ddl             CLOB;
    l_md_output       CLOB := empty_clob();
    l_hash            VARCHAR2(64);
    l_latest_hash     VARCHAR2(64);
    l_version         NUMBER := 1;
    l_messages        JSON_ARRAY_T;
    l_message_t       JSON_OBJECT_T := JSON_OBJECT_T();
    l_request         JSON_OBJECT_T;
    l_raw_response    JSON_OBJECT_T;
  BEGIN
    IF p_name LIKE 'SB_%' THEN RETURN; END IF;
    l_ddl := DBMS_METADATA.GET_DDL(p_type, p_name);
    BEGIN
      l_hash := SB_GET_MD5(l_ddl);
      BEGIN
        SELECT checksum_hash, version_number
        INTO l_latest_hash, l_version
        FROM SB_AI_DOC_REGISTRY
        WHERE object_name = p_name AND object_type = p_type
        ORDER BY version_number DESC
        FETCH FIRST ROW ONLY;
        IF l_latest_hash = l_hash THEN
          DBMS_OUTPUT.PUT_LINE('--- No changes detected, skipping documentation generation ---');
          RETURN;
        ELSE
          l_version := l_version + 1;
        END IF;
      EXCEPTION WHEN NO_DATA_FOUND THEN l_version := 1;
      END;
    EXCEPTION WHEN OTHERS THEN
      l_hash := TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF');
      SELECT NVL(MAX(version_number), 0) + 1 INTO l_version
      FROM SB_AI_DOC_REGISTRY
      WHERE object_name = p_name AND object_type = p_type;
    END;

    l_messages := JSON_ARRAY_T();
    l_message_t.put('role','system');
    l_message_t.put('content',p_prompt||CHR(10) || l_ddl);
    l_messages.append(l_message_t);
    l_raw_response := openai_simple_api.create_chat_completion(
      p_model => 'gpt-4o',
      p_messages => l_messages,
      p_user => USER,
      p_skip_if_null => 'Y',
      p_request_j => l_request);
    l_md_output := format_response(l_raw_response.to_clob);

    INSERT INTO SB_AI_DOC_REGISTRY (
      object_name, object_type, object_ddl, doc_markdown, generated_on,
      generated_by, checksum_hash, version_number, status, documentation_type
    ) VALUES (
      p_name, p_type, l_ddl, l_md_output, SYSTIMESTAMP, USER, l_hash, l_version,
      'ACTIVE', p_doc_type);
  END process_object;

  ------------------------------------------------------------------------------
  -- PROCEDURE: generate_for_all
  -- %Type: Procedure
  -- %Purpose: Iterates through all supported object types and generates documentation.
  -- %Parameters:
  --   p_prompt   - CLOB: Prompt for the AI.
  --   p_doc_type - VARCHAR2: Documentation type.
  ------------------------------------------------------------------------------
  PROCEDURE generate_for_all(p_prompt CLOB, p_doc_type VARCHAR2) IS
  BEGIN
    FOR rec IN (
      SELECT object_name, object_type
      FROM user_objects
      WHERE object_type IN ('PACKAGE', 'FUNCTION', 'PROCEDURE')
    ) LOOP
      process_object(rec.object_name, rec.object_type, p_prompt, p_doc_type);
    END LOOP;
  END generate_for_all;

  ------------------------------------------------------------------------------
  -- PROCEDURE: generate_for_type
  -- %Type: Procedure
  -- %Purpose: Filters objects by type and generates documentation.
  -- %Parameters:
  --   p_type     - VARCHAR2: Object type to filter.
  --   p_prompt   - CLOB    : Prompt for the AI.
  --   p_doc_type - VARCHAR2: Documentation type.
  ------------------------------------------------------------------------------
  PROCEDURE generate_for_type(p_type VARCHAR2, p_prompt CLOB, p_doc_type VARCHAR2) IS
  BEGIN
    FOR rec IN (
      SELECT object_name FROM user_objects
    ) LOOP
      process_object(rec.object_name, p_type, p_prompt, p_doc_type);
    END LOOP;
  END generate_for_type;

  PROCEDURE generate_for_packages(p_prompt CLOB, p_doc_type VARCHAR2) IS
  BEGIN
    generate_for_type('PACKAGE', p_prompt, p_doc_type);
  END;

  PROCEDURE generate_for_procedures(p_prompt CLOB, p_doc_type VARCHAR2) IS
  BEGIN
    generate_for_type('PROCEDURE', p_prompt, p_doc_type);
  END;

  PROCEDURE generate_for_functions(p_prompt CLOB, p_doc_type VARCHAR2) IS
  BEGIN
    generate_for_type('FUNCTION', p_prompt, p_doc_type);
  END;

  PROCEDURE generate_for_tables(p_prompt CLOB, p_doc_type VARCHAR2) IS
  BEGIN
    FOR rec IN (
      SELECT table_name AS object_name FROM user_tables
    ) LOOP
      process_object(rec.object_name, 'TABLE', p_prompt, p_doc_type);
    END LOOP;
  END;

END SB_AI_DOC_GEN_PKG;
/