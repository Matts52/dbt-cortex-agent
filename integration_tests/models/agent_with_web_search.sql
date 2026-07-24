{{
  config(
    materialized    = 'cortex_agent',
    comment         = 'Agent with web search enabled (integration test)',
    web_search_tool = true
  )
}}
models:
  orchestration: claude-4-sonnet
orchestration:
  budget:
    seconds: 30
    tokens: 16000
instructions:
  response: "Be concise."
  orchestration: "Use web search to answer questions about current events."
