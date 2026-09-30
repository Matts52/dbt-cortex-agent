# `cortex_skill` materialization

Full reference for uploading Snowflake Cortex Agent Skills from dbt models.

[Agent skills](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-skills)
are modular packages of instructions (and optional scripts) that give agents repeatable,
task-specific capabilities. Snowflake stores them as files on a named stage — there is no
`CREATE SKILL` SQL statement.

The `cortex_skill` materialization uploads a skill's `SKILL.md` file to a Snowflake stage
automatically during `dbt build`, before any agent that depends on it is created.

---

## Defining a skill

Skill files live in a directory alongside the `.sql` model — same name as the model, no
extension. The directory must contain at least `SKILL.md` and may include any companion
scripts (e.g. `.py` files for the code execution tool). The `.sql` model is config only:

```
models/
  skills/
    forecaster_skill.sql       ← dbt model (config only)
    forecaster_skill/          ← skill directory (all files uploaded to stage)
      SKILL.md                 ← required
      forecaster.py            ← optional companion scripts
```

`models/skills/forecaster_skill.sql`:

```sql
{{
  config(
    materialized = 'cortex_skill',
    stage        = '@my_db.my_schema.skill_stage'
  )
}}
```

At runtime the materialization runs:

```sql
CREATE STAGE IF NOT EXISTS my_db.my_schema.skill_stage;

PUT 'file:///absolute/path/to/forecaster_skill/*'
    @my_db.my_schema.skill_stage/skills/forecaster_skill/
AUTO_COMPRESS = FALSE
OVERWRITE = TRUE;
```

Every file in the directory is uploaded in a single `PUT`. Filenames on the stage exactly
match the local filenames — no suffix is appended.

---

## Wiring a skill to an agent

Use the `cortex_skill_path()` macro with `ref()` to wire a skill to an agent. This both
registers the DAG dependency (so the skill file is deployed before the agent is created) and
derives the correct stage path from the skill model's `stage` config automatically — no
hard-coded paths or variables needed:

`models/my_agent.sql`:

```sql
{{
  config(materialized = 'cortex_agent')
}}
models:
  orchestration: claude-4-sonnet
instructions:
  response: "Be concise."
  orchestration: "Use the forecaster skill to answer forecasting questions."
skills:
  - name: forecaster
    source:
      type: STAGE
      path: "{{ dbt_cortex_agent.cortex_skill_path(ref('forecaster_skill')) }}"
```

`dbt build` will deploy `forecaster_skill` first (writing `SKILL.md` to the stage), then create
or replace the agent with the resolved path in the spec.

---

## Configuration reference

| Config  | Required | Type   | Description |
|---------|----------|--------|-------------|
| `stage` | Yes      | string | Fully-qualified stage path, e.g. `@my_db.my_schema.skill_stage`. |

Standard dbt configs (`database`, `schema`, `alias`, `tags`, `pre_hook`, `post_hook`, …) work
as usual. The model `alias` becomes the skill folder name on the stage.

---

## Notes

- The stage is created automatically with `CREATE STAGE IF NOT EXISTS` if it does not already exist.
- The `SKILL.md` content must not contain `$$` (used as the SQL dollar-quote delimiter internally).
- To remove a deployed skill file, run `REMOVE @<stage>/skills/<name>/SKILL.md` in Snowflake directly.
