create or replace PACKAGE "OPENAI_SIMPLE_API" AS
  TYPE image_url_list_t IS TABLE OF VARCHAR2(4000);
  TYPE image_t IS RECORD(
    mime_type VARCHAR2(4000),
    content   BLOB
  );

  TYPE image_list_t IS TABLE OF image_t;

  PROCEDURE set_credentials(
    p_openai_apikey   IN VARCHAR2
   ,p_openai_org      IN VARCHAR2 DEFAULT NULL
   ,p_openai_url      IN VARCHAR2 DEFAULT NULL
  );

  PROCEDURE set_wallet(
    p_wallet     IN VARCHAR2
   ,p_wallet_pwd IN VARCHAR2
  );

  FUNCTION get_models
  RETURN json_object_t;

  FUNCTION create_chat_completion(
    p_model              IN   VARCHAR2
   ,p_messages           IN   JSON_ARRAY_T
   ,p_temperature        IN   NUMBER        DEFAULT NULL
   ,p_top_p              IN   NUMBER        DEFAULT NULL
   ,p_n                  IN   NUMBER        DEFAULT NULL
   ,p_stop               IN   JSON_ARRAY_T  DEFAULT NULL
   ,p_max_tokens         IN   NUMBER        DEFAULT NULL
   ,p_presence_penalty   IN   NUMBER        DEFAULT NULL
   ,p_frequency_penalty  IN   NUMBER        DEFAULT NULL
   --,p_logit_bias         IN   JSON_OBJECT_T DEFAULT NULL
   ,p_user               IN   VARCHAR2      DEFAULT NULL
   ,p_skip_if_null       IN   VARCHAR2      DEFAULT 'Y'
   ,p_request_j          OUT  JSON_OBJECT_T
   ,p_stream             IN   VARCHAR2      DEFAULT 'N'
   ,p_stream_callback    IN   VARCHAR2      DEFAULT NULL
   ,p_stream_callback_payload IN JSON_ELEMENT_T DEFAULT NULL
  )RETURN JSON_OBJECT_T;

END;
/
-- PACKAGE BODY: OPENAI_SIMPLE_API
-- %Purpose: Implements OpenAI API integration for completions, models, and configuration.
-- %Note: See package spec for public API exposure. Private utility methods are documented here.

CREATE OR REPLACE PACKAGE BODY OPENAI_SIMPLE_API AS

  ------------------------------------------------------------------------------
  -- GLOBALS: Authentication and configuration state
  ------------------------------------------------------------------------------
  g_openai_url      VARCHAR2(1000) := 'https://api.openai.com/v1';
  g_openai_org      VARCHAR2(1000) := '<your_openai_org>';
  g_openai_apikey   VARCHAR2(1000) := '<your_openai_api_key>';
  g_wallet          VARCHAR2(128);
  g_wallet_pwd      VARCHAR2(128);

  ------------------------------------------------------------------------------
  -- PROCEDURE: set_credentials
  -- %Type: Procedure
  -- %Purpose: Sets OpenAI credentials and optional base URL.
  -- %Parameters:
  --   p_openai_apikey - Your OpenAI secret API key
  --   p_openai_org    - Your OpenAI organization ID (optional)
  --   p_openai_url    - Base API URL to override default endpoint (optional)
  ------------------------------------------------------------------------------
  PROCEDURE set_credentials(
    p_openai_apikey   IN VARCHAR2,
    p_openai_org      IN VARCHAR2 DEFAULT NULL,
    p_openai_url      IN VARCHAR2 DEFAULT NULL
  )IS
  BEGIN
    g_openai_apikey := p_openai_apikey;

    IF p_openai_url IS NOT NULL THEN
      g_openai_url := p_openai_url;
    END IF;

    g_openai_org := p_openai_org;
  END set_credentials;

  ------------------------------------------------------------------------------
  -- PROCEDURE: set_wallet
  -- %Type: Procedure
  -- %Purpose: Stores wallet path and password for secure APEX web service calls.
  -- %Parameters:
  --   p_wallet     - Full path to the wallet directory
  --   p_wallet_pwd - Wallet password used to access the secure store
  ------------------------------------------------------------------------------
  PROCEDURE set_wallet(
    p_wallet     IN VARCHAR2,
    p_wallet_pwd IN VARCHAR2
  )IS
  BEGIN
    g_wallet := p_wallet;
    g_wallet_pwd := p_wallet_pwd;
  END set_wallet;

  ------------------------------------------------------------------------------
  -- FUNCTION: make_request
  -- %Type: Private Function
  -- %Purpose: Performs a REST GET request to the OpenAI API using name/value pairs.
  -- %Parameters:
  --   p_rel_url       - Relative path under the OpenAI base URL (e.g., 'models')
  --   p_params        - Optional parameter names (name-value)
  --   p_params_values - Optional parameter values
  --   p_status_code   - Output HTTP status code
  --   p_status_reason - Output reason phrase from the API
  --   p_http_method   - HTTP method to use (defaults to GET)
  -- %Returns: CLOB containing JSON response body
  ------------------------------------------------------------------------------
  FUNCTION make_request(
    p_rel_url           IN  VARCHAR2,
    p_params            IN  apex_application_global.vc_arr2 DEFAULT apex_application_global.c_empty_vc_arr2,
    p_params_values     IN  apex_application_global.vc_arr2 DEFAULT apex_application_global.c_empty_vc_arr2,
    p_status_code       OUT NUMBER,
    p_status_reason     OUT VARCHAR2,
    p_http_method       IN  VARCHAR2 DEFAULT 'GET'
  )RETURN CLOB IS
    l_url             VARCHAR2 (4000);
    l_response_json   CLOB;
  BEGIN
    l_url := g_openai_url;

    IF g_openai_apikey IS NOT NULL THEN
      IF g_openai_org IS NOT NULL THEN
        apex_web_service.set_request_headers(
          p_name_01    => 'Authorization',
          p_value_01   => 'Bearer '||g_openai_apikey,
          p_name_02    => 'OpenAI-Organization',
          p_value_02   => g_openai_org,
          p_name_03    => 'Content-Type',
          p_value_03   => 'application/json'
        );
      ELSE
        apex_web_service.set_request_headers(
          p_name_01    => 'Authorization',
          p_value_01   => 'Bearer '||g_openai_apikey,
          p_name_02    => 'Content-Type',
          p_value_02   => 'application/json'
        );
      END IF;
    ELSE
      apex_web_service.set_request_headers(
        p_name_01    => 'Content-Type',
        p_value_01   => 'application/json'
      );
    END IF; 

    l_url := l_url || '/' || p_rel_url;

    l_response_json := apex_web_service.make_rest_request(
        p_url           => l_url,
        p_http_method   => p_http_method,
        p_parm_name     => p_params,
        p_parm_value    => p_params_values,
        p_wallet_path   => g_wallet,
        p_wallet_pwd    => g_wallet_pwd
    );

    p_status_code := apex_web_service.g_status_code;
    p_status_reason := apex_web_service.g_reason_phrase;

    RETURN l_response_json;
  END make_request;

  ------------------------------------------------------------------------------
  -- FUNCTION: make_request_b
  -- %Type: Private Function
  -- %Purpose: Performs a REST request with a JSON body payload.
  -- %Parameters:
  --   p_rel_url       - Endpoint under OpenAI base URL
  --   p_body          - JSON CLOB payload
  --   p_status_code   - Output HTTP status code
  --   p_status_reason - Output reason phrase
  --   p_http_method   - HTTP verb, default 'GET'
  -- %Returns: JSON response as CLOB
  ------------------------------------------------------------------------------
  FUNCTION make_request_b(
    p_rel_url           IN  VARCHAR2,
    p_body              IN  CLOB,
    p_status_code       OUT NUMBER,
    p_status_reason     OUT VARCHAR2,
    p_http_method       IN  VARCHAR2 DEFAULT 'GET'
  )RETURN CLOB IS
    l_url             VARCHAR2 (4000);
    l_response_json   CLOB;
  BEGIN
    l_url := g_openai_url;

    IF g_openai_apikey IS NOT NULL THEN
      IF g_openai_org IS NOT NULL THEN
        apex_web_service.set_request_headers(
          p_name_01    => 'Authorization',
          p_value_01   => 'Bearer '||g_openai_apikey,
          p_name_02    => 'OpenAI-Organization',
          p_value_02   => g_openai_org,
          p_name_03    => 'Content-Type',
          p_value_03   => 'application/json'
        );
      ELSE
        apex_web_service.set_request_headers(
          p_name_01    => 'Authorization',
          p_value_01   => 'Bearer '||g_openai_apikey,
          p_name_02    => 'Content-Type',
          p_value_02   => 'application/json'
        );
      END IF;
    ELSE
      apex_web_service.set_request_headers(
        p_name_01    => 'Content-Type',
        p_value_01   => 'application/json'
      );
    END IF;

    l_url := l_url || '/' || p_rel_url;

    l_response_json := apex_web_service.make_rest_request(
        p_url           => l_url,
        p_http_method   => p_http_method,
        p_body          => p_body,
        p_wallet_path   => g_wallet,
        p_wallet_pwd    => g_wallet_pwd
    );

    p_status_code := apex_web_service.g_status_code;
    p_status_reason := apex_web_service.g_reason_phrase;

    RETURN l_response_json;
  END make_request_b;

  ------------------------------------------------------------------------------
  -- FUNCTION: get_models
  -- %Type: Public Function
  -- %Purpose: Retrieves the list of available OpenAI models.
  -- %Returns: JSON_OBJECT_T containing model metadata and IDs.
  -- %Example:
  --   DECLARE
  --     l_models JSON_OBJECT_T;
  --   BEGIN
  --     l_models := openai_simple_api.get_models;
  --     DBMS_OUTPUT.PUT_LINE(l_models.to_clob);
  --   END;
  ------------------------------------------------------------------------------
  FUNCTION get_models
  RETURN JSON_OBJECT_T
  IS
    l_models_list     CLOB;
    l_models_list_j   JSON_OBJECT_T;
    l_status_code     NUMBER;
    l_status_reason   VARCHAR2(1000);
  BEGIN
    l_models_list := make_request(
                        p_rel_url       => 'models',
                        p_status_code   => l_status_code,
                        p_status_reason => l_status_reason
                     );

    IF l_status_code < 200 OR l_status_code > 299 THEN
      raise_application_error(-20001, 'Unexpected error occurred while creating completion. '||l_status_code ||' - '||l_status_reason||' '||dbms_lob.substr(l_models_list, 1000, 1));
    END IF;

    l_models_list_j := json_object_t(l_models_list);
    RETURN l_models_list_j;
  END get_models;

  ------------------------------------------------------------------------------
  -- FUNCTION: create_chat_completion
  -- %Type: Public Function
  -- %Purpose: Sends a chat completion request to OpenAI's API using a JSON array of messages and optional parameters.
  -- %Parameters:
  --   p_model     - OpenAI model ID
  --   p_messages  - JSON array of messages
  --   p_temperature, p_top_p, p_n, p_stop, etc. - Optional tuning parameters
  --   p_skip_if_null - If 'Y', skip null parameters in request payload
  --   p_request_j     - OUT: JSON object sent
  --   p_stream, p_stream_callback, p_stream_callback_payload - streaming support
  -- %Returns: JSON_OBJECT_T with OpenAI response
  ------------------------------------------------------------------------------
  FUNCTION create_chat_completion(
    p_model              IN   VARCHAR2,
    p_messages           IN   JSON_ARRAY_T,
    p_temperature        IN   NUMBER        DEFAULT NULL,
    p_top_p              IN   NUMBER        DEFAULT NULL,
    p_n                  IN   NUMBER        DEFAULT NULL,
    p_stop               IN   JSON_ARRAY_T  DEFAULT NULL,
    p_max_tokens         IN   NUMBER        DEFAULT NULL,
    p_presence_penalty   IN   NUMBER        DEFAULT NULL,
    p_frequency_penalty  IN   NUMBER        DEFAULT NULL,
    p_user               IN   VARCHAR2      DEFAULT NULL,
    p_skip_if_null       IN   VARCHAR2      DEFAULT 'Y',
    p_request_j          OUT  JSON_OBJECT_T,
    p_stream             IN   VARCHAR2      DEFAULT 'N',
    p_stream_callback    IN   VARCHAR2      DEFAULT NULL,
    p_stream_callback_payload IN JSON_ELEMENT_T DEFAULT NULL
  ) RETURN JSON_OBJECT_T
  IS
    l_payload    JSON_OBJECT_T := JSON_OBJECT_T();
    l_clob       CLOB;
    l_response   CLOB;
    l_status_code   NUMBER;
    l_status_reason VARCHAR2(400);
  BEGIN
    l_payload.put('model', p_model);
    l_payload.put('messages', p_messages);

    IF p_temperature IS NOT NULL OR p_skip_if_null = 'N' THEN
      l_payload.put('temperature', p_temperature);
    END IF;
    IF p_top_p IS NOT NULL OR p_skip_if_null = 'N' THEN
      l_payload.put('top_p', p_top_p);
    END IF;
    IF p_n IS NOT NULL OR p_skip_if_null = 'N' THEN
      l_payload.put('n', p_n);
    END IF;
    IF p_stop IS NOT NULL OR p_skip_if_null = 'N' THEN
      l_payload.put('stop', p_stop);
    END IF;
    IF p_max_tokens IS NOT NULL OR p_skip_if_null = 'N' THEN
      l_payload.put('max_tokens', p_max_tokens);
    END IF;
    IF p_presence_penalty IS NOT NULL OR p_skip_if_null = 'N' THEN
      l_payload.put('presence_penalty', p_presence_penalty);
    END IF;
    IF p_frequency_penalty IS NOT NULL OR p_skip_if_null = 'N' THEN
      l_payload.put('frequency_penalty', p_frequency_penalty);
    END IF;
    IF p_user IS NOT NULL OR p_skip_if_null = 'N' THEN
      l_payload.put('user', p_user);
    END IF;
    IF p_stream = 'Y' THEN
      l_payload.put('stream', TRUE);
    END IF;

    p_request_j := l_payload;
    l_clob := p_request_j.to_clob();

    l_response := make_request_b(
      p_rel_url       => 'chat/completions',
      p_body          => l_clob,
      p_status_code   => l_status_code,
      p_status_reason => l_status_reason,
      p_http_method   => 'POST'
    );

    IF l_status_code < 200 OR l_status_code > 299 THEN
      raise_application_error(-20001, 'Unexpected error occurred while creating completion. '||l_status_code ||' - '||l_status_reason||' '||dbms_lob.substr(l_response, 1000, 1));
    END IF;

    RETURN JSON_OBJECT_T(l_response);
  END create_chat_completion;

END OPENAI_SIMPLE_API;