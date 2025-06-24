create or replace FUNCTION SB_GET_MD5(p_text CLOB) RETURN VARCHAR2 IS
  l_lines  apex_t_varchar2 := apex_t_varchar2();
  l_offset PLS_INTEGER := 1;
  l_index  PLS_INTEGER := 1;
  l_chunk  VARCHAR2(32767);
  l_step   CONSTANT PLS_INTEGER := 32767;
BEGIN
  -- Loop through the CLOB and break it into 32k VARCHAR2 chunks
  WHILE l_offset <= DBMS_LOB.getlength(p_text) LOOP
    l_chunk := DBMS_LOB.SUBSTR(p_text, l_step, l_offset);
    l_lines.EXTEND;
    l_lines(l_index) := l_chunk;
    l_offset := l_offset + l_step;
    l_index := l_index + 1;
  END LOOP;

  -- Return the hash of the full content
  RETURN APEX_UTIL.GET_HASH(l_lines);
END SB_GET_MD5;
/