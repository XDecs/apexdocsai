create or replace FUNCTION SB_GET_SHA256(p_text CLOB) RETURN VARCHAR2 IS
  l_blob         BLOB;
  l_raw          RAW(32); -- SHA256 = 256 bits = 32 bytes
  l_dest_offset  INTEGER := 1;
  l_src_offset   INTEGER := 1;
  l_ctx          INTEGER := 0;
  l_warning      INTEGER;
BEGIN
  -- Create temporary BLOB
  DBMS_LOB.CREATETEMPORARY(l_blob, TRUE);

  -- Convert CLOB to BLOB using AL32UTF8
  DBMS_LOB.CONVERTTOBLOB(
    dest_lob     => l_blob,
    src_clob     => p_text,
    amount       => DBMS_LOB.LOBMAXSIZE,
    dest_offset  => l_dest_offset,
    src_offset   => l_src_offset,
    blob_csid    => DBMS_LOB.DEFAULT_CSID,
    lang_context => l_ctx,
    warning      => l_warning
  );

  -- Hash the BLOB using SHA-256
  l_raw := DBMS_CRYPTO.HASH(l_blob, DBMS_CRYPTO.HASH_SH256);

  -- Return the hex string representation of the hash
  RETURN RAWTOHEX(l_raw);
END;
/