#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

response="$(curl --fail --silent --show-error --max-time 300 \
  "${LOCAL_AI_BASE_URL}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg model "${LOCAL_AI_MODEL_ALIAS}" '{
    model: $model,
    messages: [{role: "user", content: "Use the calculator tool to multiply 1234 by 5678. Do not calculate it yourself."}],
    tools: [{
      type: "function",
      function: {
        name: "calculator",
        description: "Multiply two numbers",
        parameters: {
          type: "object",
          properties: {
            a: {type: "number"},
            b: {type: "number"}
          },
          required: ["a", "b"]
        }
      }
    }],
    tool_choice: "auto",
    temperature: 0,
    max_tokens: 1024,
    chat_template_kwargs: {enable_thinking: false}
  }')")"

echo "${response}" | jq '.choices[0].message | {content, tool_calls}'
echo "${response}" | jq --exit-status '
  .choices[0].message.tool_calls
  | length > 0 and .[0].function.name == "calculator"
' >/dev/null

arguments="$(echo "${response}" | jq -r '.choices[0].message.tool_calls[0].function.arguments')"
echo "${arguments}" | jq --exit-status \
  '((.a == 1234 and .b == 5678) or (.a == 5678 and .b == 1234))' >/dev/null
echo "Tool-calling test passed."
