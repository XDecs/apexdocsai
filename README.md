# apexdocsai (AI-Powered PL/SQL Documentation Generator)

This project automates the generation of technical documentation for Oracle database objects using OpenAI's API. It is designed to streamline the process of maintaining up-to-date documentation across packages, procedures, functions, and tables by offloading the grunt work to AI.

## 📦 Packages Included

### ✅ `OPENAI_SIMPLE_API`
A lightweight PL/SQL wrapper to securely interact with OpenAI's API via APEX Web Services. It handles authentication, HTTPS wallet configuration, and JSON-based prompt submission.

### ✅ `SB_AI_DOC_GEN_PKG`
The core logic to extract object metadata (using `DBMS_METADATA.GET_DDL`), prepare context-aware prompts, invoke OpenAI completions, and store the generated Markdown into a version-controlled documentation table.

---

## ✨ Features

- Generate Markdown documentation for Oracle packages, procedures, functions, and tables
- Version control to detect and track DDL changes
- Uses OpenAI's GPT models (`gpt-4o` by default)
- Out-of-the-box credential and HTTPS wallet configuration
- Clean separation of concerns: prompt orchestration vs. API communication

---

## 🚀 Getting Started

### 1. Set your OpenAI credentials

```plsql
BEGIN
  OPENAI_SIMPLE_API.set_credentials(
    p_openai_apikey => 'sk-xxx',      -- Your API Key
    p_openai_org    => 'org-xxx'      -- Optional Organization
  );

  OPENAI_SIMPLE_API.set_wallet(
    p_wallet     => 'file:/path/to/your/wallet',
    p_wallet_pwd => 'your_wallet_password'
  );
END;
```

### 2. Generate Documentation for an Object

```plsql
BEGIN
  SB_AI_DOC_GEN_PKG.generate_doc_for_object(
    p_object_type => 'PACKAGE',
    p_object_name => 'MY_PACKAGE'
  );
END;
```

This will:
- Retrieve the current DDL for the object
- Check if it has changed since the last version
- Build a prompt using the default Markdown-based technical template
- Call OpenAI to generate the documentation
- Store the result in `SB_AI_DOC_REGISTRY`

---

## 📘 Tables Created

- `SB_AI_DOC_REGISTRY`: Stores object-level documentation and version history
- `SB_AI_PROMPT_LIBRARY`: Optional table to store custom prompts

---

## 🔧 Supported Object Types

- `PACKAGE`
- `PACKAGE BODY`
- `FUNCTION`
- `PROCEDURE`
- `TABLE`

You can expand support to other objects by modifying `generate_doc_for_object`.

---

## 📎 Sample Output

The documentation returned by OpenAI is stored as Markdown in the `SB_AI_DOC_REGISTRY` table. You can render this Markdown within APEX or export it for use in wikis or GitHub.

---

## 🧪 Testing Tips

Use the following anonymous block to test quickly:

```plsql
BEGIN
  SB_AI_DOC_GEN_PKG.generate_doc_for_object(
    p_object_type => 'TABLE',
    p_object_name => 'EMPLOYEES'
  );
END;
```

Make sure the table or package exists in your current schema.

---

## 📜 License

MIT

---

*Generated on 2025-06-24*
